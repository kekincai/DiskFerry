import Foundation
import XCTest
@testable import DiskFerry

final class PathInputTests: XCTestCase {
    func testParsesSMBURLWithSpacesAndChinese() {
        XCTAssertEqual(
            PathInput.parse("smb://minipc/G/照片 2024/Raw"),
            .smb(server: "minipc", share: "G", subpath: ["照片 2024", "Raw"])
        )
    }

    func testParsesSMBURLWithUserAndEncoding() {
        XCTAssertEqual(
            PathInput.parse("smb://kc@192.168.1.10/My%20Share/a"),
            .smb(server: "192.168.1.10", share: "My Share", subpath: ["a"])
        )
    }

    func testParsesWindowsUNCPath() {
        XCTAssertEqual(
            PathInput.parse(#"\\DESKTOP-01\Backup\Photos\2024"#),
            .smb(server: "DESKTOP-01", share: "Backup", subpath: ["Photos", "2024"])
        )
    }

    func testParsesMountSourceForm() {
        XCTAssertEqual(
            PathInput.parse("//kekincai@minipc/G/Photos"),
            .smb(server: "minipc", share: "G", subpath: ["Photos"])
        )
    }

    func testStripsQuotesAndWhitespace() {
        XCTAssertEqual(PathInput.parse("  '/Volumes/Photo Disk/2024'\n"), .local("/Volumes/Photo Disk/2024"))
        XCTAssertEqual(PathInput.parse("“/tmp”"), .local("/tmp"))
    }

    func testParsesFileURLAndTilde() {
        XCTAssertEqual(PathInput.parse("file:///Volumes/Photo%20Disk/"), .local("/Volumes/Photo Disk"))
        XCTAssertEqual(PathInput.parse("~/Pictures"), .local(NSHomeDirectory() + "/Pictures"))
    }

    func testRejectsWindowsDriveLetterAndParentTraversal() {
        guard case .invalid = PathInput.parse(#"D:\Photos"#) else {
            return XCTFail("drive letters are not reachable from the Mac")
        }
        guard case .invalid = PathInput.parse("smb://minipc/G/../etc") else {
            return XCTFail("parent traversal must be rejected")
        }
        guard case .invalid = PathInput.parse("smb://minipc") else {
            return XCTFail("a share name is required")
        }
    }

    func testResolveReportsMissingFolder() {
        let missing = "/nonexistent-\(UUID().uuidString)"
        guard case .failure = PathInput.resolve(missing) else {
            return XCTFail("missing folders should fail")
        }
    }

    func testResolveUnmountedShareAsksToMount() {
        let resolution = PathInput.resolve("smb://no-such-server-\(UUID().uuidString.prefix(8))/share/sub")
        guard case let .needsMount(url, _, share, subpath) = resolution else {
            return XCTFail("expected needsMount, got \(resolution)")
        }
        XCTAssertEqual(url.scheme, "smb")
        XCTAssertEqual(share, "share")
        XCTAssertEqual(subpath, ["sub"])
    }

    func testNetworkLocationFromMountSource() {
        let location = NetworkLocation(mountSource: "//kekincai@minipc/G%20Drive")
        XCTAssertEqual(location, NetworkLocation(server: "minipc", share: "G Drive"))
        XCTAssertEqual(location?.matches(server: "MiniPC.local", share: "g drive"), true)
        XCTAssertEqual(location?.matches(server: "other", share: "G Drive"), false)
    }

    func testPathContainment() {
        XCTAssertTrue(PathInspector.isSameOrInside("/Volumes/A/Photos/x", "/Volumes/A/Photos"))
        XCTAssertTrue(PathInspector.isSameOrInside("/Volumes/A/Photos/", "/Volumes/A/Photos"))
        XCTAssertFalse(PathInspector.isSameOrInside("/Volumes/A/Photos2", "/Volumes/A/Photos"))
        XCTAssertTrue(PathInspector.isVolumeRoot("/Volumes/minipc"))
        XCTAssertFalse(PathInspector.isVolumeRoot("/Volumes/minipc/Photos"))
    }
}
