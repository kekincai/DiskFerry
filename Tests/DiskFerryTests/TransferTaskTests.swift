import Foundation
import XCTest
@testable import DiskFerry

final class TransferTaskTests: XCTestCase {
    func testIntoFolderLayoutNestsSourceName() {
        var task = TransferTask.empty
        task.sourcePath = "/Volumes/PhotoDisk/Photos"
        task.targetPath = "/Volumes/minipc/Backup"
        task.targetLayout = .intoFolder
        XCTAssertEqual(task.resolvedTargetPath, "/Volumes/minipc/Backup/Photos")

        task.targetLayout = .merge
        XCTAssertEqual(task.resolvedTargetPath, "/Volumes/minipc/Backup")
    }

    func testDecodesLegacyTaskFile() throws {
        // Shape written by the previous release: no layout / pin / run fields,
        // plus since-removed live preview flags.
        let json = """
        [{
          "id": "20260101-000000-photos", "name": "Photos Backup",
          "sourcePath": "/Volumes/PhotoDisk/Photos", "targetPath": "/Volumes/minipc",
          "logDirectory": "/Volumes/minipc/Photos/_transfer_logs", "engine": "rclone",
          "mode": "conservative", "transfers": 1, "checkers": 2, "retries": 10,
          "lowLevelRetries": 20, "excludes": [".DS_Store"], "verifyMode": "size-only",
          "verifyAfterCopy": false, "liveHeatmapEnabled": false, "liveLogPreviewEnabled": false,
          "createdAt": "2026-01-01T00:00:00Z"
        },
        {
          "id": "b", "name": "Docs", "sourcePath": "/Users/me/Docs", "targetPath": "/Volumes/minipc/Docs",
          "logDirectory": "", "engine": "rclone", "mode": "normal", "transfers": 2, "checkers": 4,
          "retries": 10, "lowLevelRetries": 20, "excludes": [], "verifyMode": "size-only",
          "verifyAfterCopy": true, "createdAt": "2026-01-01T00:00:00Z"
        }]
        """
        let tasks = try JSONCoding.decoder.decode([TransferTask].self, from: Data(json.utf8))
        XCTAssertEqual(tasks.count, 2)

        // Volume root targets used to nest into the source folder name: keep that.
        XCTAssertEqual(tasks[0].targetLayout, .intoFolder)
        XCTAssertEqual(tasks[0].resolvedTargetPath, "/Volumes/minipc/Photos")
        // Other targets used to receive the contents directly: keep that too.
        XCTAssertEqual(tasks[1].targetLayout, .merge)
        XCTAssertEqual(tasks[1].resolvedTargetPath, "/Volumes/minipc/Docs")

        XCTAssertTrue(tasks[0].checkFirst)
        XCTAssertFalse(tasks[0].isPinned)
        XCTAssertNil(tasks[0].lastRun)
    }

    func testRoundTripsNewFields() throws {
        var task = TransferTask.empty
        task.sourcePath = "/a"
        task.targetPath = "/b"
        task.isPinned = true
        task.targetLayout = .merge
        // ISO 8601 stores whole seconds.
        task.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        task.lastRun = RunRecord(finishedAt: Date(timeIntervalSince1970: 0), outcome: .verified, bytes: 5, files: 1, errors: 0, duration: 3)
        let data = try JSONCoding.encoder.encode([task])
        let decoded = try JSONCoding.decoder.decode([TransferTask].self, from: data)
        XCTAssertEqual(decoded.first, task)
    }

    func testStorageKeepsPinnedAndCapsRecents() {
        var tasks: [TransferTask] = (0..<30).map { index in
            var task = TransferTask.empty
            task.sourcePath = "/src/\(index)"
            task.targetPath = "/dst"
            return task
        }
        tasks[25].isPinned = true
        tasks[29].isPinned = true

        let trimmed = TaskStorage.trimmed(tasks)
        XCTAssertEqual(trimmed.filter(\.isPinned).count, 2)
        XCTAssertEqual(trimmed.filter { !$0.isPinned }.count, TaskStorage.recentLimit)
    }

    func testDisplayName() {
        var task = TransferTask.empty
        XCTAssertEqual(task.displayName, "新路线")
        task.sourcePath = "/Volumes/PhotoDisk/Photos"
        task.targetPath = "/Volumes/minipc"
        XCTAssertEqual(task.displayName, "Photos → minipc")
        task.name = "每周照片备份"
        XCTAssertEqual(task.displayName, "每周照片备份")
    }
}
