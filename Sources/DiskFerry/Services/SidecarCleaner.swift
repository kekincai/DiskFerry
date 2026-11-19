import Darwin
import Foundation

/// Deletes the 4 KB `._name` AppleDouble files that macOS writes next to every file a
/// process creates on a volume without native xattrs (exFAT, FAT). They only carry the
/// `com.apple.provenance` attribute, which the app cannot stop macOS from adding, and
/// they show up as clutter on Windows.
///
/// A `._X` file is deleted only when all of these hold:
/// - it is a regular file (not a symlink or folder) whose name starts with `._`;
/// - `X` exists in the same folder;
/// - `X`'s xattr list is exactly `["com.apple.provenance"]`.
///
/// Anything else is kept: a sidecar that also holds Finder tags, a resource fork or a
/// quarantine flag has data the user may care about, an orphan cannot be attributed, and
/// a file that merely happens to start with `._` leaves `X` with no attributes at all.
///
/// The walk works on directory file descriptors: it never follows symlinks, never leaves
/// the volume it started on, checks every folder is still the one it listed, and `lstat`s
/// each sidecar right before unlinking it. It touches the (possibly slow, possibly
/// removable) destination, so run it off the main thread.
struct SidecarCleaner {
    struct Result: Equatable {
        var deleted = 0
        /// `._` files looked at and left in place.
        var kept = 0
        /// Sidecars that qualified but could not be deleted.
        var failed = 0
        var wasCancelled = false
    }

    /// The sibling `X` whose attributes decide the fate of `._X`. `path` is for reading
    /// by path (tests); the default reader uses `directory` + `name` so a folder swapped
    /// after it was opened cannot redirect the read.
    struct AttributeTarget {
        var directory: Int32
        var name: String
        var path: String
    }

    static let provenance = "com.apple.provenance"
    static let prefix = "._"

    /// Returns `X`'s xattr names, or nil when they cannot be read (the sidecar is kept).
    var attributeNames: (AttributeTarget) -> [String]? = SidecarCleaner.readAttributeNames
    /// Checked before every directory and every deletion.
    var isCancelled: () -> Bool = { false }

    /// Scans each folder in `folders` recursively. For a folder other than `selectedRoot`
    /// (which the app created inside it), its own `._<folder>` in the parent folder is
    /// checked too. Everything outside `device` is skipped.
    func clean(folders: [String], selectedRoot: String, device: UInt64) -> Result {
        var result = Result()
        let root = Self.standardized(selectedRoot)
        var seen = Set<String>()

        for folder in folders.map(Self.standardized) where seen.insert(folder).inserted {
            if isCancelled() { result.wasCancelled = true; break }

            if folder != root, PathInspector.isSameOrInside(folder, root) {
                let url = URL(fileURLWithPath: folder)
                let parent = url.deletingLastPathComponent().path
                let name = url.lastPathComponent
                if let identity = Self.directoryIdentity(atPath: parent), identity.device == device {
                    withDirectory(parent, expected: identity) { directory in
                        let entries = Self.index(Self.entries(of: directory))
                        process(sidecar: Self.prefix + name, in: directory, path: parent, entries: entries, result: &result)
                    }
                }
            }

            guard let identity = Self.directoryIdentity(atPath: folder), identity.device == device else { continue }
            walk(folder, identity: identity, device: device, result: &result)
            if result.wasCancelled { break }
        }
        return result
    }

    // MARK: - Walking

    private struct Identity: Equatable {
        var device: UInt64
        var inode: UInt64
    }

    private struct Entry {
        var name: String
        var type: UInt8
    }

    /// Depth-first with an explicit stack, holding only one folder open at a time.
    private func walk(_ start: String, identity: Identity, device: UInt64, result: inout Result) {
        var pending: [(path: String, identity: Identity)] = [(start, identity)]
        while let (path, expected) = pending.popLast() {
            if isCancelled() { result.wasCancelled = true; return }
            withDirectory(path, expected: expected) { directory in
                let entries = Self.entries(of: directory)
                let sidecars = entries.filter { $0.name.hasPrefix(Self.prefix) }
                if !sidecars.isEmpty {
                    let byName = Self.index(entries)
                    for sidecar in sidecars {
                        if isCancelled() { result.wasCancelled = true; return }
                        process(sidecar: sidecar.name, in: directory, path: path, entries: byName, result: &result)
                    }
                }
                // Folders only; DT_UNKNOWN (some network file systems) needs an lstat.
                for entry in entries where entry.type == DT_DIR || entry.type == DT_UNKNOWN {
                    var info = stat()
                    guard fstatat(directory, entry.name, &info, AT_SYMLINK_NOFOLLOW) == 0,
                          info.st_mode & S_IFMT == S_IFDIR,
                          UInt64(info.st_dev) == device else { continue }
                    let child = (path as NSString).appendingPathComponent(entry.name)
                    pending.append((child, Identity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))))
                }
            }
            if result.wasCancelled { return }
        }
    }

    /// Opens `path` without following a final symlink and runs `body` only if it is still
    /// the directory identified earlier. Since a directory has exactly one location, a
    /// matching device and inode also rules out a swapped parent along the path.
    private func withDirectory(_ path: String, expected: Identity, _ body: (Int32) -> Void) {
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              Identity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino)) == expected else { return }
        body(descriptor)
    }

    // MARK: - One sidecar

    /// `entries` maps each name in the folder to itself, as listed.
    private func process(
        sidecar: String,
        in directory: Int32,
        path: String,
        entries: [String: String],
        result: inout Result
    ) {
        guard sidecar.hasPrefix(Self.prefix) else { return }
        var info = stat()
        // Only an existing regular file is ever a candidate.
        guard fstatat(directory, sidecar, &info, AT_SYMLINK_NOFOLLOW) == 0 else { return }
        guard info.st_mode & S_IFMT == S_IFREG else {
            result.kept += 1
            return
        }
        // The sibling as the directory listed it, which may differ from `._X`'s bytes in
        // Unicode normalization (Swift compares strings canonically).
        let wanted = String(sidecar.dropFirst(Self.prefix.count))
        guard !wanted.isEmpty, let sibling = entries[wanted] else {
            result.kept += 1
            return
        }
        let target = AttributeTarget(
            directory: directory,
            name: sibling,
            path: (path as NSString).appendingPathComponent(sibling)
        )
        guard attributeNames(target) == [Self.provenance] else {
            result.kept += 1
            return
        }

        if isCancelled() {
            result.wasCancelled = true
            return
        }
        // Re-check right before deleting: still a regular file, still the same one.
        var again = stat()
        guard fstatat(directory, sidecar, &again, AT_SYMLINK_NOFOLLOW) == 0,
              again.st_mode & S_IFMT == S_IFREG,
              again.st_dev == info.st_dev, again.st_ino == info.st_ino else {
            result.kept += 1
            return
        }
        if unlinkat(directory, sidecar, 0) == 0 {
            result.deleted += 1
        } else {
            result.failed += 1
        }
    }

    // MARK: - Helpers

    /// Every entry except `.` and `..`. Names that are not valid UTF-8 are left out;
    /// exFAT and FAT store UTF-16 names, so they cannot occur there.
    private static func entries(of directory: Int32) -> [Entry] {
        // fdopendir takes ownership of the descriptor it is given, so hand it a copy.
        let copy = dup(directory)
        guard copy >= 0 else { return [] }
        guard let stream = fdopendir(copy) else {
            close(copy)
            return []
        }
        defer { closedir(stream) }
        rewinddir(stream)

        var entries: [Entry] = []
        while let entry = readdir(stream) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw -> String? in
                let bytes = raw.prefix(Int(entry.pointee.d_namlen))
                return String(bytes: bytes, encoding: .utf8)
            }
            guard let name, name != ".", name != ".." else { continue }
            entries.append(Entry(name: name, type: entry.pointee.d_type))
        }
        return entries
    }

    private static func index(_ entries: [Entry]) -> [String: String] {
        var byName: [String: String] = [:]
        for entry in entries {
            byName[entry.name] = entry.name
        }
        return byName
    }

    private static func directoryIdentity(atPath path: String) -> Identity? {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
        return Identity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }

    /// Lists `X`'s xattrs through a descriptor opened relative to its folder, without
    /// following a symlink. Opening for reading does not make macOS write a new sidecar.
    static func readAttributeNames(_ target: AttributeTarget) -> [String]? {
        let descriptor = openat(target.directory, target.name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        let size = flistxattr(descriptor, nil, 0, 0)
        guard size >= 0 else { return nil }
        guard size > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: size)
        let read = flistxattr(descriptor, &buffer, size, 0)
        guard read >= 0 else { return nil }
        return buffer.prefix(read)
            .split(separator: 0)
            .map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
    }
}
