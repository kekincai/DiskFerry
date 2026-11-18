import Darwin
import Foundation
import XCTest
@testable import DiskFerry

/// Decision logic of `SidecarCleaner` in an ordinary temp folder. `com.apple.provenance`
/// cannot be written by hand, so the xattr lookup is replaced by a table keyed by the
/// sibling's name; the `._` files are plain files made by the test.
final class SidecarCleanerTests: XCTestCase {
    private let provenance = SidecarCleaner.provenance
    private let tags = "com.apple.metadata:_kMDItemUserTags"
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDeletesOnlyProvenanceSidecarsWithASibling() throws {
        let dest = try folder("dest")
        try pair(dest, "plain.txt")
        try pair(dest, "tagged.txt")
        try pair(dest, "quarantined.txt")
        try pair(dest, "named.txt")
        try file(dest, "._orphan.txt")

        let result = cleaner([
            "plain.txt": [provenance],
            "tagged.txt": [provenance, tags],
            "quarantined.txt": [provenance, "com.apple.quarantine"],
            // A `._` file that is not AppleDouble: its sibling has no attributes at all.
            "named.txt": []
        ]).clean(folders: [dest.path], selectedRoot: dest.path, device: try device(dest))

        XCTAssertEqual(result, SidecarCleaner.Result(deleted: 1, kept: 4, failed: 0, wasCancelled: false))
        XCTAssertEqual(try sidecars(in: dest), ["._named.txt", "._orphan.txt", "._quarantined.txt", "._tagged.txt"])
        // The real files are never touched.
        XCTAssertEqual(try names(in: dest).filter { !$0.hasPrefix("._") },
                       ["named.txt", "plain.txt", "quarantined.txt", "tagged.txt"])
    }

    func testKeepsSymlinkAndFolderSidecarsAndDoesNotFollowSymlinkedFolders() throws {
        let dest = try folder("dest")
        let outside = try folder("outside")
        try pair(outside, "inner.txt")
        try file(outside, "target.txt")

        // `._link.txt` is a symlink, `._dir.txt` a folder: neither is a regular file.
        try file(dest, "link.txt")
        try FileManager.default.createSymbolicLink(
            at: dest.appendingPathComponent("._link.txt"),
            withDestinationURL: outside.appendingPathComponent("target.txt")
        )
        try file(dest, "dir.txt")
        try FileManager.default.createDirectory(at: dest.appendingPathComponent("._dir.txt"), withIntermediateDirectories: false)
        // A symlinked folder inside the destination leads to sidecars that would qualify.
        try FileManager.default.createSymbolicLink(at: dest.appendingPathComponent("linked"), withDestinationURL: outside)

        let everything = ["link.txt", "dir.txt", "inner.txt", "target.txt", "linked"]
        var asked: [String] = []
        let cleaner = SidecarCleaner(attributeNames: { target in
            asked.append(target.name)
            return everything.contains(target.name) ? [self.provenance] : []
        })
        let result = cleaner.clean(folders: [dest.path], selectedRoot: dest.path, device: try device(dest))

        XCTAssertEqual(result.deleted, 0)
        XCTAssertEqual(result.kept, 2)
        XCTAssertEqual(asked, [], "non-regular sidecars are rejected before reading attributes")
        XCTAssertEqual(try sidecars(in: dest), ["._dir.txt", "._link.txt"])
        XCTAssertEqual(try sidecars(in: outside), ["._inner.txt"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.appendingPathComponent("target.txt").path))
    }

    func testCleansNestedFoldersAndTheDestinationsOwnSidecar() throws {
        // root is the selected target; dest is the folder the app created in it.
        let dest = try folder("Photos")
        let deeper = try folder("Photos/sub/deeper")
        try file(root, "._Photos")
        try pair(dest, "sub")
        try pair(dest.appendingPathComponent("sub"), "deeper")
        try pair(deeper, "f.txt")
        // Unrelated folder next to the destination: not part of this copy.
        _ = try folder("Other")
        try file(root, "._Other")

        let result = cleaner(Dictionary(uniqueKeysWithValues: ["Photos", "sub", "deeper", "f.txt", "Other"].map { ($0, [provenance]) }))
            .clean(folders: [dest.path], selectedRoot: root.path, device: try device(root))

        XCTAssertEqual(result.deleted, 4)
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(try sidecars(in: root), ["._Other"])
        XCTAssertEqual(try sidecars(in: dest), [])
        XCTAssertEqual(try sidecars(in: dest.appendingPathComponent("sub")), [])
        XCTAssertEqual(try sidecars(in: deeper), [])
    }

    /// "Merge" layout: the destination is the selected folder itself, so the folder above
    /// it is none of the app's business.
    func testMergeLayoutDoesNotLookAboveTheSelectedFolder() throws {
        let dest = try folder("Backup")
        try file(root, "._Backup")
        try pair(dest, "a.txt")

        let result = cleaner(["Backup": [provenance], "a.txt": [provenance]])
            .clean(folders: [dest.path], selectedRoot: dest.path, device: try device(dest))

        XCTAssertEqual(result.deleted, 1)
        XCTAssertEqual(try sidecars(in: root), ["._Backup"])
    }

    func testSeveralDestinationsEachGetTheirOwnSidecarChecked() throws {
        let first = try folder("2024")
        let second = try folder("2025")
        try file(root, "._2024")
        try file(root, "._2025")
        try pair(first, "a.txt")
        try pair(second, "b.txt")

        let result = cleaner(["2024": [provenance], "2025": [provenance], "a.txt": [provenance], "b.txt": [provenance]])
            .clean(folders: [first.path, second.path], selectedRoot: root.path, device: try device(root))

        XCTAssertEqual(result.deleted, 4)
        XCTAssertEqual(try sidecars(in: root), [])
    }

    func testStopsWhenCancelled() throws {
        let dest = try folder("dest")
        for index in 0..<5 {
            try pair(dest, "f\(index).txt")
        }

        // Cancelled from the start: nothing is read or deleted.
        var reads = 0
        let stopped = SidecarCleaner(
            attributeNames: { _ in reads += 1; return [self.provenance] },
            isCancelled: { true }
        ).clean(folders: [dest.path], selectedRoot: dest.path, device: try device(dest))
        XCTAssertTrue(stopped.wasCancelled)
        XCTAssertEqual(stopped.deleted, 0)
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(try sidecars(in: dest).count, 5)

        // Cancelled mid-way: the first sidecar goes, the walk stops before the second unlink.
        reads = 0
        let partial = SidecarCleaner(
            attributeNames: { _ in reads += 1; return [self.provenance] },
            isCancelled: { reads >= 2 }
        ).clean(folders: [dest.path], selectedRoot: dest.path, device: try device(dest))
        XCTAssertTrue(partial.wasCancelled)
        XCTAssertEqual(partial.deleted, 1)
        XCTAssertEqual(try sidecars(in: dest).count, 4)
    }

    func testFailedDeletionIsCountedNotThrown() throws {
        try XCTSkipIf(getuid() == 0, "root can delete from a read-only folder")
        let dest = try folder("dest")
        try pair(dest, "a.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dest.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path) }

        let result = cleaner(["a.txt": [provenance]])
            .clean(folders: [dest.path], selectedRoot: dest.path, device: try device(dest))

        XCTAssertEqual(result, SidecarCleaner.Result(deleted: 0, kept: 0, failed: 1, wasCancelled: false))
        XCTAssertEqual(try sidecars(in: dest), ["._a.txt"])
    }

    func testSkipsFoldersOnAnotherDevice() throws {
        let dest = try folder("dest")
        try pair(dest, "a.txt")

        let result = cleaner(["a.txt": [provenance]])
            .clean(folders: [dest.path], selectedRoot: dest.path, device: try device(dest) &+ 1)

        XCTAssertEqual(result.deleted, 0)
        XCTAssertEqual(try sidecars(in: dest), ["._a.txt"])
    }

    func testSymlinkedDestinationIsNotEntered() throws {
        let outside = try folder("outside")
        try pair(outside, "a.txt")
        let link = root.appendingPathComponent("dest")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let result = cleaner(["a.txt": [provenance]])
            .clean(folders: [link.path], selectedRoot: root.path, device: try device(root))

        XCTAssertEqual(result.deleted, 0)
        XCTAssertEqual(try sidecars(in: outside), ["._a.txt"])
    }

    /// The real reader on a native volume: a file with a Finder tag lists more than
    /// provenance, so its sidecar would be kept.
    func testDefaultReaderListsAttributesWithoutFollowingSymlinks() throws {
        let dest = try folder("dest")
        try file(dest, "tagged.txt")
        let value = Data("tag".utf8)
        XCTAssertEqual(value.withUnsafeBytes {
            setxattr(dest.appendingPathComponent("tagged.txt").path, tags, $0.baseAddress, value.count, 0, 0)
        }, 0)
        try FileManager.default.createSymbolicLink(
            at: dest.appendingPathComponent("link.txt"),
            withDestinationURL: dest.appendingPathComponent("tagged.txt")
        )

        let directory = open(dest.path, O_RDONLY | O_DIRECTORY)
        XCTAssertGreaterThanOrEqual(directory, 0)
        defer { close(directory) }
        let read = { (name: String) in
            SidecarCleaner.readAttributeNames(.init(directory: directory, name: name, path: dest.appendingPathComponent(name).path))
        }
        XCTAssertTrue(try XCTUnwrap(read("tagged.txt")).contains(tags))
        XCTAssertNil(read("link.txt"), "a symlinked sibling is never read through")
        XCTAssertNil(read("missing.txt"))
    }

    func testTempFolderVolumeStoresAttributesNatively() throws {
        let traits = try XCTUnwrap(VolumeCatalog.traits(path: root.path))
        XCTAssertTrue(traits.storesExtendedAttributesNatively, "\(traits)")
        XCTAssertFalse(traits.fileSystem.isEmpty)
        XCTAssertNil(VolumeCatalog.traits(path: root.appendingPathComponent("missing/deeper").path))
    }

    func testHeadlineNote() {
        XCTAssertNil(TransferStore.cleanupNote(for: .init()))
        XCTAssertNil(TransferStore.cleanupNote(for: .init(deleted: 0, kept: 3, failed: 0)))
        XCTAssertEqual(TransferStore.cleanupNote(for: .init(deleted: 1_234)), "已清理 \(1_234.formatted()) 个 ._ 文件")
        XCTAssertEqual(TransferStore.cleanupNote(for: .init(deleted: 2, failed: 1)), "已清理 2 个 ._ 文件，1 个没能删除")
        XCTAssertEqual(TransferStore.cleanupNote(for: .init(failed: 3)), "但有 3 个 ._ 文件没能删除")
    }

    // MARK: - Helpers

    private func cleaner(_ attributes: [String: [String]]) -> SidecarCleaner {
        SidecarCleaner(attributeNames: { attributes[$0.name] ?? [] })
    }

    @discardableResult
    private func folder(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func file(_ directory: URL, _ name: String, size: Int = 0) throws {
        try Data(count: size).write(to: directory.appendingPathComponent(name))
    }

    /// `name` (a file, unless it already exists as a folder) plus a 4 KB `._name`.
    private func pair(_ directory: URL, _ name: String) throws {
        if !FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            try file(directory, name, size: 3)
        }
        try file(directory, "._" + name, size: 4_096)
    }

    private func names(in directory: URL) throws -> [String] {
        try SidecarTestListing.names(in: directory.path)
    }

    private func sidecars(in directory: URL) throws -> [String] {
        try names(in: directory).filter { $0.hasPrefix("._") }
    }

    private func device(_ url: URL) throws -> UInt64 {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw POSIXError(.ENOENT) }
        return UInt64(info.st_dev)
    }
}

/// Directory listings straight from `readdir`. FileManager's `contentsOfDirectory` and
/// `subpaths` silently leave out `._` files, which are exactly what these tests count.
enum SidecarTestListing {
    static func names(in path: String) throws -> [String] {
        guard let stream = opendir(path) else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { closedir(stream) }
        var names: [String] = []
        while let entry = readdir(stream) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if name != ".", name != ".." { names.append(name) }
        }
        return names.sorted()
    }

    /// Every entry below `path`, relative to it, without following symlinks or entering
    /// other volumes.
    static func subpaths(of path: String) throws -> [String] {
        var root = stat()
        guard lstat(path, &root) == 0 else { throw POSIXError(.ENOENT) }
        var result: [String] = []
        var pending = [""]
        while let relative = pending.popLast() {
            let folder = relative.isEmpty ? path : (path as NSString).appendingPathComponent(relative)
            for name in try names(in: folder) {
                let child = relative.isEmpty ? name : (relative as NSString).appendingPathComponent(name)
                result.append(child)
                var info = stat()
                if lstat((path as NSString).appendingPathComponent(child), &info) == 0,
                   info.st_mode & S_IFMT == S_IFDIR, info.st_dev == root.st_dev {
                    pending.append(child)
                }
            }
        }
        return result.sorted()
    }
}
