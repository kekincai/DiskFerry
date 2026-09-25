import Foundation
import XCTest
@testable import DiskFerry

/// End-to-end: runs real rclone with the same arguments the app uses and checks that
/// live stats arrive over rc even though all console output goes to --log-file.
final class RcloneLiveStatsTests: XCTestCase {
    func testLiveStatsArriveDuringCopy() async throws {
        guard let rclone = RcloneLocator.locate(preferredPath: nil) else {
            throw XCTSkip("rclone is not installed")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("Photos", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileSize = 8 * 1_024 * 1_024
        for index in 0..<4 {
            try Data(repeating: UInt8(index), count: fileSize)
                .write(to: source.appendingPathComponent("file-\(index).bin"))
        }

        var task = TransferTask.empty
        task.sourcePath = source.path
        task.targetPath = target.path
        task.targetLayout = .intoFolder

        let remote = try RcloneRemoteControl.makeLocal()
        let logFile = root.appendingPathComponent("run.log").path
        // Throttle so the copy lasts long enough to observe mid-flight numbers.
        XCTAssertTrue(RcloneCapabilities.supportsLocalNoClone(rclonePath: rclone))
        var arguments = RcloneRunner().makeArguments(
            task: task,
            logFile: logFile,
            dryRun: false,
            streamLocalCopies: true
        )
        arguments += remote.arguments + ["--bwlimit", "8M"]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: rclone)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }

        let client = RcloneStatsClient(remote: remote)
        var sawTotals = false
        var sawMidFlight = false
        for _ in 0..<40 where process.isRunning {
            try await Task.sleep(for: .milliseconds(250))
            guard let stats = try? await client.fetch() else { continue }
            if stats.totalBytes == Int64(fileSize * 4), stats.totalTransfers == 4 {
                sawTotals = true
            }
            let progress = TransferProgress(stats: stats, verifying: false, checkFirst: true, currentSpeed: 0)
            if let fraction = progress.fraction, fraction > 0, fraction < 1 {
                sawMidFlight = true
            }
            if sawTotals, sawMidFlight { break }
        }

        XCTAssertTrue(sawTotals, "rc should report exact totals up front with --check-first")
        XCTAssertTrue(sawMidFlight, "rc should report partial progress while copying")

        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: task.resolvedTargetPath).filter { $0.hasSuffix(".bin") }.count,
            4
        )
    }
}
