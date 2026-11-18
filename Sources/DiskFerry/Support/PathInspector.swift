import Darwin
import Foundation

enum PathInspector {
    /// `/Volumes/<name>` exactly. String-only on purpose: callers run during decoding
    /// and rendering, where a stalled SMB mount must not block the main thread.
    static func isVolumeRoot(_ path: String) -> Bool {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        return components.count == 3 && components[1] == "Volumes"
    }

    /// Is `candidate` the same as, or nested inside, `container`?
    static func isSameOrInside(_ candidate: String, _ container: String) -> Bool {
        hasPathPrefix(
            URL(fileURLWithPath: candidate).standardizedFileURL.path,
            URL(fileURLWithPath: container).standardizedFileURL.path
        )
    }

    private static func hasPathPrefix(_ child: String, _ parent: String) -> Bool {
        if child == parent { return true }
        let prefix = parent.hasSuffix("/") ? parent : parent + "/"
        return child.hasPrefix(prefix)
    }

    /// `isSameOrInside` for the precheck: resolves symlinks in both paths and ignores case
    /// (and Unicode normalization) when the container's volume does, so an alias or a
    /// differently cased path cannot slip a destination into the source. Touches the
    /// filesystem; never call it on the main thread.
    static func resolvedIsSameOrInside(_ candidate: String, _ container: String) -> Bool {
        // Compared as plain strings: `standardizedFileURL` drops a leading `/private`
        // only for paths that exist, which would make canonical paths disagree.
        let child = canonicalPath(candidate)
        let parent = canonicalPath(container)
        if hasPathPrefix(child, parent) { return true }

        let caseSensitive = (try? URL(fileURLWithPath: parent)
            .resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames ?? false
        guard !caseSensitive else { return false }
        return hasPathPrefix(folded(child), folded(parent))
    }

    /// Resolves symlinks in the deepest existing ancestor and appends the missing tail
    /// (for example the folder a copy is about to create) unchanged.
    private static func canonicalPath(_ path: String) -> String {
        var existing = URL(fileURLWithPath: path).standardizedFileURL
        var tail: [String] = []
        while existing.path != "/", !FileManager.default.fileExists(atPath: existing.path) {
            tail.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        guard let resolved = realpath(existing.path, nil) else { return existing.path }
        defer { free(resolved) }
        var url = URL(fileURLWithPath: String(cString: resolved))
        for component in tail {
            url.appendPathComponent(component)
        }
        return url.path
    }

    private static func folded(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: nil)
    }

    /// Shortens a path for display: `~/…` for home, otherwise unchanged.
    static func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

/// Information about the volume that holds a path. Gathering it calls `statfs`, which can
/// block on a disconnected share, so build it off the main thread.
struct VolumeDescriptor: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case network
        case external
        case internalDisk
    }

    var id: String { mountPoint }
    var mountPoint: String
    var name: String
    var kind: Kind
    /// For network shares, the server-side location, e.g. `smb://minipc/G`.
    var networkLocation: String?
    var availableBytes: Int64?
    /// `f_fstypename`, e.g. `apfs`, `exfat`, `msdos`, `smbfs`. Lets the command preview
    /// match the real run without touching the filesystem while rendering.
    var fileSystem: String = ""

    var symbolName: String {
        switch kind {
        case .network: "server.rack"
        case .external: "externaldrive"
        case .internalDisk: "internaldrive"
        }
    }
}

/// What the destination volume can store, read once in the preflight and carried through
/// the run, so neither rclone's arguments nor the cleanup step look at the disk again.
struct VolumeTraits: Equatable, Sendable {
    /// `f_fstypename`, e.g. `apfs`, `exfat`, `msdos`.
    var fileSystem: String
    /// False on exFAT/FAT, where macOS writes every xattr into a `._name` sidecar file.
    var storesExtendedAttributesNatively: Bool
}

enum VolumeCatalog {
    /// User-visible mounted volumes: network shares first, then external disks, then this Mac.
    static func mountedVolumes() -> [VolumeDescriptor] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls
            .compactMap { describe(mountPoint: $0.path) }
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind { return rank(lhs.kind) < rank(rhs.kind) }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// Describes the volume containing `path`, or nil if the path is not reachable.
    static func describe(path: String) -> VolumeDescriptor? {
        guard let mount = MountInfo(path: path) else { return nil }
        return describe(mount: mount)
    }

    /// Mount point for an SMB share if it is already mounted.
    static func mountPoint(forServer server: String, share: String) -> String? {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        for url in urls {
            guard let mount = MountInfo(path: url.path), mount.isNetwork,
                  let location = NetworkLocation(mountSource: mount.source) else { continue }
            if location.matches(server: server, share: share) {
                return mount.mountPoint
            }
        }
        return nil
    }

    private static func describe(mountPoint: String) -> VolumeDescriptor? {
        guard let mount = MountInfo(path: mountPoint), mount.mountPoint == mountPoint else { return nil }
        return describe(mount: mount)
    }

    private static func describe(mount: MountInfo) -> VolumeDescriptor {
        let url = URL(fileURLWithPath: mount.mountPoint, isDirectory: true)
        let values = try? url.resourceValues(forKeys: [.volumeLocalizedNameKey, .volumeIsInternalKey])

        let kind: VolumeDescriptor.Kind
        if mount.isNetwork {
            kind = .network
        } else if mount.mountPoint == "/" || values?.volumeIsInternal == true {
            kind = .internalDisk
        } else {
            kind = .external
        }

        let name = values?.volumeLocalizedName
            ?? (mount.mountPoint == "/" ? "Macintosh HD" : url.lastPathComponent)

        return VolumeDescriptor(
            mountPoint: mount.mountPoint,
            name: name,
            kind: kind,
            networkLocation: mount.isNetwork ? NetworkLocation(mountSource: mount.source)?.smbURLString : nil,
            availableBytes: mount.availableBytes,
            fileSystem: mount.fileSystem
        )
    }

    /// File system type and xattr support of the volume holding `path`, or nil if the
    /// path is not reachable. Calls `statfs` and `getattrlist`; never on the main thread.
    static func traits(path: String) -> VolumeTraits? {
        guard let mount = MountInfo(path: path) else { return nil }
        return VolumeTraits(
            fileSystem: mount.fileSystem,
            storesExtendedAttributesNatively: storesExtendedAttributesNatively(path: path)
        )
    }

    /// Reads `VOL_CAP_INT_EXTENDED_ATTR` from the volume capabilities. exFAT and FAT report
    /// it as valid and unset; macOS then emulates xattrs with `._` AppleDouble files.
    /// Anything that cannot be read counts as native, so the cleanup never runs on a
    /// volume it is unsure about.
    private static func storesExtendedAttributesNatively(path: String) -> Bool {
        struct Buffer {
            var length: UInt32 = 0
            var capabilities = vol_capabilities_attr_t()
        }
        var request = attrlist(
            bitmapcount: UInt16(ATTR_BIT_MAP_COUNT),
            reserved: 0,
            commonattr: 0,
            volattr: attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_CAPABILITIES),
            dirattr: 0,
            fileattr: 0,
            forkattr: 0
        )
        var buffer = Buffer()
        guard getattrlist(path, &request, &buffer, MemoryLayout<Buffer>.size, 0) == 0 else { return true }
        let index = Int(VOL_CAPABILITIES_INTERFACES)
        let bit = UInt32(VOL_CAP_INT_EXTENDED_ATTR)
        let valid = withUnsafeBytes(of: &buffer.capabilities.valid) { $0.bindMemory(to: UInt32.self)[index] }
        let capable = withUnsafeBytes(of: &buffer.capabilities.capabilities) { $0.bindMemory(to: UInt32.self)[index] }
        guard valid & bit != 0 else { return true }
        return capable & bit != 0
    }

    private static func rank(_ kind: VolumeDescriptor.Kind) -> Int {
        switch kind {
        case .network: 0
        case .external: 1
        case .internalDisk: 2
        }
    }
}

/// Thin wrapper over `statfs`.
private struct MountInfo {
    var mountPoint: String
    var source: String
    var fileSystem: String
    var availableBytes: Int64

    var isNetwork: Bool {
        ["smbfs", "afpfs", "nfs", "webdav"].contains(fileSystem)
    }

    init?(path: String) {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        mountPoint = Self.string(from: &info.f_mntonname)
        source = Self.string(from: &info.f_mntfromname)
        fileSystem = Self.string(from: &info.f_fstypename)
        availableBytes = Int64(info.f_bavail) * Int64(info.f_bsize)
    }

    private static func string<T>(from tuple: inout T) -> String {
        withUnsafeBytes(of: &tuple) { raw in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}

/// Server + share parsed out of an SMB mount source such as `//user@minipc/G%20Drive`.
struct NetworkLocation: Equatable {
    var server: String
    var share: String

    init(server: String, share: String) {
        self.server = server
        self.share = share
    }

    init?(mountSource: String) {
        guard mountSource.hasPrefix("//") else { return nil }
        let trimmed = mountSource.dropFirst(2)
        let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        var host = String(parts[0])
        if let at = host.lastIndex(of: "@") {
            host = String(host[host.index(after: at)...])
        }
        let share = String(parts[1]).removingPercentEncoding ?? String(parts[1])
        guard !host.isEmpty, !share.isEmpty else { return nil }
        self.server = host
        self.share = share
    }

    var smbURLString: String {
        "smb://\(server)/\(share)"
    }

    func matches(server otherServer: String, share otherShare: String) -> Bool {
        Self.normalizedHost(server) == Self.normalizedHost(otherServer)
            && share.caseInsensitiveCompare(otherShare) == .orderedSame
    }

    private static func normalizedHost(_ host: String) -> String {
        var value = host.lowercased()
        if value.hasSuffix(".local") {
            value.removeLast(".local".count)
        }
        if value.hasSuffix(".") {
            value.removeLast()
        }
        return value
    }
}
