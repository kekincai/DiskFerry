import Foundation
import XCTest
@testable import DiskFerry

final class PrecheckServiceSecurityTests: XCTestCase {
    func testPrecheckRejectsSymlinkedLogDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("Photos", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)

        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: target.appendingPathComponent("_transfer_logs"),
            withDestinationURL: outside
        )
        defer { try? FileManager.default.removeItem(at: root) }

        var task = TransferTask.empty
        task.sourcePath = source.path
        task.targetPath = target.path
        // Logs then live directly in the selected target, next to the planted symlink.
        task.targetLayout = .merge

        let result = PrecheckService().run(task: task, rclonePath: "/usr/bin/true")

        XCTAssertTrue(result.hasErrors)
        XCTAssertTrue(result.items.contains {
            $0.title == "目标路径安全检查" && $0.severity == .error
        })
    }

    func testPrecheckRejectsTargetInsideSourceWithoutWritingIntoSource() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("Photos", isDirectory: true)
        let nested = source.appendingPathComponent("backup", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var task = TransferTask.empty
        task.sourcePath = source.path
        task.targetPath = nested.path
        task.targetLayout = .intoFolder

        let result = PrecheckService().run(task: task, rclonePath: "/usr/bin/true")

        XCTAssertTrue(result.hasErrors)
        XCTAssertTrue(result.items.contains { $0.title == "路径检查" && $0.severity == .error })
        let nestedEntries = try FileManager.default.contentsOfDirectory(atPath: nested.path)
        XCTAssertTrue(nestedEntries.isEmpty, "precheck must not create folders inside the source")
    }

    func testDestinationSnapshotDetectsDirectoryReplacement() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var task = TransferTask.empty
        task.sourcePath = source.path
        task.targetPath = target.path
        let snapshot = try DestinationPathPolicy.prepare(task: task)

        try FileManager.default.removeItem(at: snapshot.logDirectory)
        try FileManager.default.createDirectory(at: snapshot.logDirectory, withIntermediateDirectories: false)

        XCTAssertThrowsError(try DestinationPathPolicy.validate(snapshot))
    }

    func testPrecheckRejectsSelectedTargetSymlinkBeforeWriteProbe() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        let targetLink = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: targetLink, withDestinationURL: outside)
        defer { try? FileManager.default.removeItem(at: root) }

        var task = TransferTask.empty
        task.sourcePath = source.path
        task.targetPath = targetLink.path

        let result = PrecheckService().run(task: task, rclonePath: "/usr/bin/true")

        XCTAssertTrue(result.hasErrors)
        XCTAssertTrue(result.items.contains {
            $0.title == "目标路径安全检查" && $0.message.contains("符号链接")
        })
        let outsideEntries = try FileManager.default.contentsOfDirectory(atPath: outside.path)
        XCTAssertTrue(outsideEntries.isEmpty)
    }

    func testOrdinaryDestinationPassesAndCreatesLogDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var task = TransferTask.empty
        task.sourcePath = source.path
        task.targetPath = target.path

        let snapshot = try DestinationPathPolicy.prepare(task: task)
        XCTAssertNoThrow(try DestinationPathPolicy.validate(snapshot))
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.logDirectory.path))
    }
}
