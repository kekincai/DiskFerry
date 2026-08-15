import Foundation
import XCTest
@testable import DiskFerry

final class HeatmapScannerSecurityTests: XCTestCase {
    func testDirectoryEnumerationStopsAtEntryBudget() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for index in 0..<200 {
            XCTAssertTrue(FileManager.default.createFile(
                atPath: directory.appendingPathComponent("file-\(index)").path,
                contents: Data()
            ))
        }

        let children = HeatmapScanner.boundedChildren(
            at: directory,
            entryBudget: 17,
            timeBudget: 5,
            pathByteBudget: 1_000_000
        )

        XCTAssertEqual(children.count, 17)
    }

    func testDirectoryEnumerationHonorsPathByteBudget() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(FileManager.default.createFile(
            atPath: directory.appendingPathComponent("entry").path,
            contents: Data()
        ))

        let children = HeatmapScanner.boundedChildren(
            at: directory,
            entryBudget: 10,
            timeBudget: 5,
            pathByteBudget: 1
        )

        XCTAssertTrue(children.isEmpty)
    }
}
