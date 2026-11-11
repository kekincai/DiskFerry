import Foundation
import XCTest
@testable import DiskFerry

final class PrecheckServiceSecurityTests: XCTestCase {
    func testPrecheckRejectsSymlinkedDestinationFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("Photos", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)

        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        // target/Photos (the real write location) points outside the selected target.
        try FileManager.default.createSymbolicLink(
            at: target.appendingPathComponent("Photos"),
            withDestinationURL: outside
        )
        defer { try? FileManager.default.removeItem(at: root) }

        var task = TransferTask.empty
        task.sourcePath = source.path
        task.targetPath = target.path
        task.targetLayout = .intoFolder

        let result = PrecheckService().run(task: task, rclonePath: "/usr/bin/true")

        XCTAssertTrue(result.hasErrors)
        XCTAssertTrue(result.items.contains {
            $0.title == "目标路径安全检查" && $0.severity == .error
        })
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
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

        try FileManager.default.removeItem(at: snapshot.destination)
        try FileManager.default.createDirectory(at: snapshot.destination, withIntermediateDirectories: false)

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

    func testDryRunPrecheckWritesNothingToDestination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("Photos", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var task = TransferTask.empty
        task.sourcePath = source.path
        task.targetPath = target.path
        task.targetLayout = .intoFolder

        let result = PrecheckService().run(task: task, rclonePath: "/usr/bin/true", dryRun: true)

        XCTAssertFalse(result.hasErrors, result.items.map(\.message).joined(separator: "\n"))
        XCTAssertNil(result.destination)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty,
            "a dry run must not create the destination folder or a write-test file"
        )
    }

    func testDryRunPrecheckStillRejectsSymlinkedDestination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("Photos", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: target.appendingPathComponent("Photos"), withDestinationURL: outside)
        defer { try? FileManager.default.removeItem(at: root) }

        var task = TransferTask.empty
        task.sourcePath = source.path
        task.targetPath = target.path
        task.targetLayout = .intoFolder

        let result = PrecheckService().run(task: task, rclonePath: "/usr/bin/true", dryRun: true)
        XCTAssertTrue(result.items.contains { $0.title == "目标路径安全检查" && $0.severity == .error })
    }

    func testPrecheckRejectsTargetInsideSourceThroughSymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("backup"), withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        defer { try? FileManager.default.removeItem(at: root) }

        var task = TransferTask.empty
        task.sourcePath = source.path
        task.targetPath = alias.appendingPathComponent("backup").path
        task.targetLayout = .merge

        let result = PrecheckService().run(task: task, rclonePath: "/usr/bin/true")
        XCTAssertTrue(result.items.contains { $0.title == "路径检查" && $0.severity == .error })
        XCTAssertNil(result.destination)
    }

    func testPrecheckRejectsTargetInsideSourceWithDifferentCase() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("backup"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let caseSensitive = try root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            .volumeSupportsCaseSensitiveNames ?? true
        if caseSensitive {
            throw XCTSkip("temporary directory is on a case-sensitive volume")
        }

        var task = TransferTask.empty
        task.sourcePath = source.path
        task.targetPath = root.appendingPathComponent("PHOTOS/backup").path
        task.targetLayout = .merge

        XCTAssertFalse(PathInspector.isSameOrInside(task.targetPath, task.sourcePath), "plain string check differs by case")
        let result = PrecheckService().run(task: task, rclonePath: "/usr/bin/true")
        XCTAssertTrue(result.items.contains { $0.title == "路径检查" && $0.severity == .error })
        let entries = try FileManager.default.contentsOfDirectory(atPath: source.appendingPathComponent("backup").path)
        XCTAssertTrue(entries.isEmpty, "precheck must not create folders inside the source")
    }

    func testOrdinaryDestinationPassesWithoutWritingLogs() throws {
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.destination.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: snapshot.destination.path).isEmpty)
    }
}
