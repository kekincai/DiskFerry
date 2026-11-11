import Darwin
import Foundation

enum DestinationPathPolicy {
    struct DirectoryIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    struct Snapshot {
        let selectedRoot: URL
        let destination: URL
        let selectedRootIdentity: DirectoryIdentity
        let destinationIdentity: DirectoryIdentity
    }

    enum PolicyError: LocalizedError {
        case emptyPath
        case outsideSelectedRoot(String)
        case symbolicLink(String)
        case notDirectory(String)
        case directoryChanged(String)
        case filesystem(String)

        var errorDescription: String? {
            switch self {
            case .emptyPath:
                return "目标路径为空。"
            case let .outsideSelectedRoot(path):
                return "路径不在所选目标目录内：\(path)"
            case let .symbolicLink(path):
                return "目标路径包含符号链接：\(path)"
            case let .notDirectory(path):
                return "目标路径不是目录：\(path)"
            case let .directoryChanged(path):
                return "目标目录在预检查后被替换：\(path)"
            case let .filesystem(message):
                return message
            }
        }
    }

    static func prepare(task: TransferTask) throws -> Snapshot {
        let (root, destination) = try urls(for: task)

        try walk(to: root, within: root, whenMissing: .fail)
        try walk(to: destination, within: root, whenMissing: .create)
        try verifyCanonicalContainment(candidate: destination, root: root)

        return Snapshot(
            selectedRoot: root,
            destination: destination,
            selectedRootIdentity: try directoryIdentity(at: root),
            destinationIdentity: try directoryIdentity(at: destination)
        )
    }

    /// Read-only counterpart of `prepare` for dry runs: the same symlink and containment
    /// checks, but nothing is created and a missing destination folder is fine.
    /// Returns whether the destination folder already exists.
    static func inspect(task: TransferTask) throws -> Bool {
        let (root, destination) = try urls(for: task)

        try walk(to: root, within: root, whenMissing: .fail)
        let deepest = try walk(to: destination, within: root, whenMissing: .stop)
        try verifyCanonicalContainment(candidate: deepest, root: root)
        return deepest.path == destination.path
    }

    static func validate(_ snapshot: Snapshot) throws {
        try validateDirectory(snapshot.selectedRoot, expected: snapshot.selectedRootIdentity)
        try validateDirectory(snapshot.destination, expected: snapshot.destinationIdentity)
        try verifyCanonicalContainment(candidate: snapshot.destination, root: snapshot.selectedRoot)
    }

    private static func standardizedDirectoryURL(path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    private static func urls(for task: TransferTask) throws -> (root: URL, destination: URL) {
        guard !task.targetPath.isEmpty, !task.resolvedTargetPath.isEmpty else {
            throw PolicyError.emptyPath
        }
        return (standardizedDirectoryURL(path: task.targetPath), standardizedDirectoryURL(path: task.resolvedTargetPath))
    }

    private enum MissingAction {
        /// Throw: the folder must already exist.
        case fail
        /// Create it (real copies only).
        case create
        /// Stop walking and report the deepest existing folder (dry runs).
        case stop
    }

    /// Walks from `root` down to `candidate`, rejecting symlinks and non-directories at
    /// every step. Returns the deepest directory that exists afterwards.
    @discardableResult
    private static func walk(to candidate: URL, within root: URL, whenMissing: MissingAction) throws -> URL {
        guard isContained(candidate, in: root) else {
            throw PolicyError.outsideSelectedRoot(candidate.path)
        }

        if candidate.path == root.path {
            _ = try directoryIdentity(at: root)
            return root
        }

        var current = root
        for component in candidate.pathComponents.dropFirst(root.pathComponents.count) {
            let next = current.appendingPathComponent(component, isDirectory: true)
            switch try itemKind(at: next) {
            case .missing:
                switch whenMissing {
                case .fail:
                    throw PolicyError.notDirectory(next.path)
                case .stop:
                    return current
                case .create:
                    do {
                        try FileManager.default.createDirectory(at: next, withIntermediateDirectories: false)
                    } catch {
                        throw PolicyError.filesystem("无法创建目标目录 \(next.path)：\(error.localizedDescription)")
                    }
                }
            case .symbolicLink:
                throw PolicyError.symbolicLink(next.path)
            case .directory:
                break
            case .other:
                throw PolicyError.notDirectory(next.path)
            }
            current = next
        }

        _ = try directoryIdentity(at: candidate)
        return candidate
    }

    private static func validateDirectory(_ url: URL, expected: DirectoryIdentity) throws {
        let actual = try directoryIdentity(at: url)
        guard actual == expected else {
            throw PolicyError.directoryChanged(url.path)
        }
    }

    private static func directoryIdentity(at url: URL) throws -> DirectoryIdentity {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw PolicyError.filesystem("无法检查目标目录 \(url.path)：\(String(cString: strerror(errno)))")
        }
        let kind = info.st_mode & S_IFMT
        if kind == S_IFLNK {
            throw PolicyError.symbolicLink(url.path)
        }
        guard kind == S_IFDIR else {
            throw PolicyError.notDirectory(url.path)
        }
        return DirectoryIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    private enum ItemKind {
        case missing
        case symbolicLink
        case directory
        case other
    }

    private static func itemKind(at url: URL) throws -> ItemKind {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            switch info.st_mode & S_IFMT {
            case S_IFLNK: return .symbolicLink
            case S_IFDIR: return .directory
            default: return .other
            }
        }
        if errno == ENOENT {
            return .missing
        }
        throw PolicyError.filesystem("无法检查目标路径 \(url.path)：\(String(cString: strerror(errno)))")
    }

    private static func verifyCanonicalContainment(candidate: URL, root: URL) throws {
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let canonicalCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard isContained(canonicalCandidate, in: canonicalRoot) else {
            throw PolicyError.outsideSelectedRoot(candidate.path)
        }
    }

    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
        PathInspector.isSameOrInside(candidate.path, root.path)
    }
}
