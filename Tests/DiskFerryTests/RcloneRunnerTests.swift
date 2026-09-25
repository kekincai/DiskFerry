import Foundation
import XCTest
@testable import DiskFerry

final class RcloneRunnerTests: XCTestCase {
    /// A process that prints its error and exits immediately must keep that output.
    /// Foundation does not order the termination handler after the pipe's readability
    /// handler, so the runner drains the pipe at exit. The race rarely shows on a fast
    /// machine; this guards the behavior and that the drain never blocks.
    func testOutputWrittenJustBeforeExitIsKept() async throws {
        for attempt in 0..<40 {
            // A burst of output right before exit leaves bytes in the pipe when the
            // process ends; the error line comes last, as rclone's does.
            let script = "head -c 200000 /dev/zero | tr '\\0' '.' >&2; printf '\\nError: boom-\(attempt)\\n' >&2; exit 3"
            let output = try await run("/bin/sh", ["-c", script])
            XCTAssertEqual(output.status, 3)
            XCTAssertTrue(output.text.contains("boom-\(attempt)"), "attempt \(attempt) lost output: \(output.text.debugDescription)")
        }
    }

    /// A copy that finishes before the first rc poll still reports real totals.
    func testFinalStatsCoverRunsFasterThanFirstPoll() async throws {
        guard let rclone = RcloneLocator.locate(preferredPath: nil) else {
            throw XCTSkip("rclone is not installed")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("tiny", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("hello".utf8).write(to: source.appendingPathComponent("a.txt"))
        try Data("world!".utf8).write(to: source.appendingPathComponent("b.txt"))

        var task = TransferTask.empty
        task.sourcePath = source.path
        task.targetPath = target.path
        let arguments = RcloneRunner().makeArguments(task: task, dryRun: false, streamLocalCopies: true)

        let output = try await run(rclone, arguments)
        XCTAssertEqual(output.status, 0)
        let stats = try XCTUnwrap(RcloneOutput.finalStats(output.text), output.text)
        XCTAssertEqual(stats.totalTransfers, 2)
        XCTAssertEqual(stats.transfers, 2)
        XCTAssertEqual(stats.bytes, 11)
    }

    private func run(_ executable: String, _ arguments: [String]) async throws -> (status: Int32, text: String) {
        let runner = RcloneRunner()
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try runner.start(rclonePath: executable, arguments: arguments) { status, text in
                    continuation.resume(returning: (status, text))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
