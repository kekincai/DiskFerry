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

    /// The dry run's precheck no longer creates the destination folder, so rclone must
    /// handle a missing one without creating it either.
    func testDryRunIntoMissingFolderCreatesNothing() async throws {
        guard let rclone = RcloneLocator.locate(preferredPath: nil) else {
            throw XCTSkip("rclone is not installed")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("Photos", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("hello".utf8).write(to: source.appendingPathComponent("a.txt"))

        var task = TransferTask.empty
        task.sourcePath = source.path
        task.targetPath = target.path
        task.targetLayout = .intoFolder
        let arguments = RcloneRunner().makeArguments(task: task, dryRun: true, streamLocalCopies: true)

        let output = try await run(rclone, arguments)
        XCTAssertEqual(output.status, 0, output.text)
        XCTAssertEqual(RcloneOutput.finalStats(output.text)?.totalTransfers, 1)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }

    /// Plan B: exFAT and FAT store coarse modification times; only those get a window,
    /// and only for `copy`.
    func testModifyWindowOnlyForCoarseTimestampVolumes() {
        var task = TransferTask.empty
        task.sourcePath = "/Volumes/PhotoDisk/Photos"
        task.targetPath = "/Volumes/Stick"
        let runner = RcloneRunner()

        func window(_ fileSystem: String?) -> String? {
            let arguments = runner.makeArguments(task: task, dryRun: false, destinationFileSystem: fileSystem)
            guard let index = arguments.firstIndex(of: "--modify-window") else { return nil }
            return arguments[index + 1]
        }
        XCTAssertEqual(window("exfat"), "2s")
        XCTAssertEqual(window("msdos"), "2s")
        for other in ["apfs", "hfs", "smbfs", "ntfs", ""] {
            XCTAssertNil(window(other), other)
        }
        XCTAssertNil(window(nil))
        XCTAssertTrue(runner.makeArguments(task: task, dryRun: true, destinationFileSystem: "exfat").contains("--modify-window"))
        XCTAssertFalse(runner.makeCheckArguments(task: task).contains("--modify-window"))
    }

    func testGlobCharactersInFolderNamesAreEscaped() {
        XCTAssertEqual(RcloneRunner.escapeGlob("Photos [2024] {raw}*?"), #"Photos \[2024\] \{raw\}\*\?"#)
        XCTAssertEqual(RcloneRunner.escapeGlob(#"a\b"#), #"a\\b"#)
    }

    /// Several folders from one parent are copied in one run: only those folders, each
    /// into its own folder in the target, still without the system files.
    func testSeveralSourceFoldersCopyOnlyTheSelectedOnes() async throws {
        guard let rclone = RcloneLocator.locate(preferredPath: nil) else {
            throw XCTSkip("rclone is not installed")
        }
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let parent = root.appendingPathComponent("Disk", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        // "[2024]" would match a single character as a glob; "Photos" alone would not be selected.
        for folder in ["Photos [2024]", "Docs", "Photos", "Skip"] {
            let url = parent.appendingPathComponent(folder, isDirectory: true)
            try fileManager.createDirectory(at: url.appendingPathComponent("sub", isDirectory: true), withIntermediateDirectories: true)
            try Data(folder.utf8).write(to: url.appendingPathComponent("sub/file.txt"))
            try Data().write(to: url.appendingPathComponent(".DS_Store"))
        }
        try Data("top".utf8).write(to: parent.appendingPathComponent("loose.txt"))
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)

        var task = TransferTask.empty
        task.sourcePath = parent.path
        task.sourceItems = ["Docs", "Photos [2024]"]
        task.targetPath = target.path
        let output = try await run(rclone, RcloneRunner().makeArguments(task: task, dryRun: false))
        XCTAssertEqual(output.status, 0, output.text)

        let copied = try XCTUnwrap(fileManager.subpaths(atPath: target.path)).sorted()
        XCTAssertEqual(copied, [
            "Docs", "Docs/sub", "Docs/sub/file.txt",
            "Photos [2024]", "Photos [2024]/sub", "Photos [2024]/sub/file.txt"
        ])

        let check = try await run(rclone, RcloneRunner().makeCheckArguments(task: task))
        XCTAssertEqual(check.status, 0, check.text)
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
