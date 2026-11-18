import Darwin
import Foundation
import XCTest
@testable import DiskFerry

/// End to end on a real exFAT volume: a small disk image made with `hdiutil` (no admin
/// rights needed). Skipped when the image cannot be made, or when this environment does
/// not make macOS write `._` files (the test process may not be provenance-tracked).
final class SidecarCleanerExFATTests: XCTestCase {
    private let tags = "com.apple.metadata:_kMDItemUserTags"

    func testCopyThenCleanLeavesOnlyMeaningfulSidecars() async throws {
        guard let rclone = RcloneLocator.locate(preferredPath: nil) else {
            throw XCTSkip("rclone is not installed")
        }
        let work = try makeWorkFolder()
        let volume = try mountExFAT(in: work)

        // Source on the internal disk, with a sidecar of its own that rclone must skip.
        let source = work.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("sub"), withIntermediateDirectories: true)
        let contents = ["a.txt": "alpha", "b.txt": "bravo", "sub/c.txt": "charlie"]
        for (path, text) in contents {
            try Data(text.utf8).write(to: source.appendingPathComponent(path))
        }
        try Data(count: 4_096).write(to: source.appendingPathComponent("._a.txt"))

        let traits = try XCTUnwrap(VolumeCatalog.traits(path: volume.path))
        XCTAssertEqual(traits.fileSystem, "exfat")
        XCTAssertFalse(traits.storesExtendedAttributesNatively)

        var task = TransferTask.empty
        task.sourcePath = source.path
        task.targetPath = volume.path
        task.targetLayout = .intoFolder
        // As the app does it: the precheck creates the destination folder, then rclone runs.
        let snapshot = try DestinationPathPolicy.prepare(task: task)
        let arguments = RcloneRunner().makeArguments(
            task: task,
            dryRun: false,
            streamLocalCopies: RcloneCapabilities.supportsLocalNoClone(rclonePath: rclone),
            destinationFileSystem: traits.fileSystem
        )
        XCTAssertTrue(arguments.joined(separator: " ").contains("--modify-window 2s"))
        let copy = try await run(rclone, arguments)
        XCTAssertEqual(copy.status, 0, copy.text)

        let created = try sidecars(under: volume)
        guard created.contains("Photos/._a.txt") else {
            throw XCTSkip("macOS wrote no ._ files here (found \(created)); the process is probably not provenance-tracked")
        }

        // A Finder tag on one copied file: its sidecar now holds data worth keeping.
        let destination = volume.appendingPathComponent("Photos", isDirectory: true)
        try setTag(on: destination.appendingPathComponent("b.txt"))
        XCTAssertTrue(try sidecars(under: volume).contains("Photos/._b.txt"))

        let result = try clean(task: task, snapshot: snapshot)
        XCTAssertEqual(result.failed, 0)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertEqual(try sidecars(under: volume), ["Photos/._b.txt"])
        XCTAssertEqual(result.deleted, created.count - (created.contains("Photos/._b.txt") ? 1 : 0))

        // Contents are unchanged and the tag survived.
        for (path, text) in contents {
            XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent(path), encoding: .utf8), text)
        }
        XCTAssertTrue(attributeNames(destination.appendingPathComponent("b.txt")).contains(tags))

        // Plan B: with --modify-window a re-run rewrites no file times, so no file sidecar
        // comes back. (A folder's own one may: rclone still sets folder times.)
        let rerun = try await run(rclone, arguments)
        XCTAssertEqual(rerun.status, 0, rerun.text)
        let afterRerun = try sidecars(under: volume)
        XCTAssertFalse(afterRerun.contains("Photos/._a.txt"), "\(afterRerun)")
        XCTAssertFalse(afterRerun.contains("Photos/sub/._c.txt"), "\(afterRerun)")

        _ = try clean(task: task, snapshot: snapshot)
        XCTAssertEqual(try sidecars(under: volume), ["Photos/._b.txt"])
    }

    /// A volume mounted inside the destination is never entered.
    func testDoesNotCrossIntoAnotherVolume() throws {
        let work = try makeWorkFolder()
        let destination = work.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let inner = try mountExFAT(in: destination)
        for folder in [destination, inner] {
            try Data("x".utf8).write(to: folder.appendingPathComponent("a.txt"))
            try Data(count: 4_096).write(to: folder.appendingPathComponent("._a.txt"))
        }

        var info = stat()
        XCTAssertEqual(lstat(destination.path, &info), 0)
        let result = SidecarCleaner(attributeNames: { _ in [SidecarCleaner.provenance] })
            .clean(folders: [destination.path], selectedRoot: destination.path, device: UInt64(info.st_dev))

        XCTAssertEqual(result.deleted, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("._a.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: inner.appendingPathComponent("._a.txt").path))
    }

    // MARK: - Helpers

    private func clean(task: TransferTask, snapshot: DestinationPathPolicy.Snapshot) throws -> SidecarCleaner.Result {
        try DestinationPathPolicy.validate(snapshot)
        return SidecarCleaner().clean(
            folders: task.copyPairs.map(\.destination),
            selectedRoot: snapshot.selectedRoot.path,
            device: snapshot.destinationIdentity.device
        )
    }

    private func makeWorkFolder() throws -> URL {
        // Resolved, so paths compare equal to what the cleaner and statfs report.
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskFerryExFAT-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: work) }
        return work
    }

    /// Creates and mounts a small exFAT image at `<folder>/mnt`. The image is detached
    /// and deleted when the test ends, whether it passed or not.
    private func mountExFAT(in folder: URL) throws -> URL {
        let image = folder.appendingPathComponent("volume-\(UUID().uuidString).dmg")
        let mountPoint = folder.appendingPathComponent("mnt", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        let create = shell("/usr/bin/hdiutil", ["create", "-size", "16m", "-fs", "ExFAT", "-volname", "DFTest", "-o", image.path])
        guard create.status == 0 else {
            throw XCTSkip("hdiutil could not create an exFAT image: \(create.output)")
        }
        // Registered first so it also runs when attaching fails half-way. Runs before the
        // work folder's own cleanup (teardown blocks run last-in, first-out).
        addTeardownBlock { [self] in
            if shell("/usr/bin/hdiutil", ["detach", mountPoint.path]).status != 0 {
                _ = shell("/usr/bin/hdiutil", ["detach", "-force", mountPoint.path])
            }
            try? FileManager.default.removeItem(at: image)
        }
        let attach = shell("/usr/bin/hdiutil", ["attach", "-nobrowse", "-mountpoint", mountPoint.path, image.path])
        guard attach.status == 0 else {
            throw XCTSkip("hdiutil could not attach the image: \(attach.output)")
        }
        return mountPoint
    }

    private func shell(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Every `._` file on the volume, relative to it, sorted.
    private func sidecars(under volume: URL) throws -> [String] {
        try SidecarTestListing.subpaths(of: volume.path)
            .filter { ($0 as NSString).lastPathComponent.hasPrefix("._") }
            .filter { !$0.hasPrefix(".fseventsd") && !$0.hasPrefix(".Spotlight") && !$0.hasPrefix(".Trashes") }
            .sorted()
    }

    private func setTag(on url: URL) throws {
        let plist = try PropertyListSerialization.data(fromPropertyList: ["Red\n6"], format: .binary, options: 0)
        let status = plist.withUnsafeBytes { setxattr(url.path, tags, $0.baseAddress, plist.count, 0, 0) }
        XCTAssertEqual(status, 0, String(cString: strerror(errno)))
    }

    private func attributeNames(_ url: URL) -> [String] {
        let size = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: size)
        let read = listxattr(url.path, &buffer, size, XATTR_NOFOLLOW)
        guard read > 0 else { return [] }
        return buffer.prefix(read).split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
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
