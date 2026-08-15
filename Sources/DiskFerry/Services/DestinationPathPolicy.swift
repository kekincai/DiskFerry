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
        let logDirectory: URL
        let selectedRootIdentity: DirectoryIdentity
        let destinationIdentity: DirectoryIdentity
        let logDirectoryIdentity: DirectoryIdentity
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
        guard !task.targetPath.isEmpty, !task.resolvedTargetPath.isEmpty else {
            throw PolicyError.emptyPath
        }

        let root = standardizedDirectoryURL(path: task.targetPath)
        let destination = standardizedDirectoryURL(path: task.resolvedTargetPath)
        let logDirectory = destination.appendingPathComponent("_transfer_logs", isDirectory: true).standardizedFileURL

        try ensureDirectory(at: root, within: root, createIfMissing: false)
        try ensureDirectory(at: destination, within: root, createIfMissing: true)
        try ensureDirectory(at: logDirectory, within: root, createIfMissing: true)
        try verifyCanonicalContainment(candidate: destination, root: root)
        try verifyCanonicalContainment(candidate: logDirectory, root: root)

        return Snapshot(
            selectedRoot: root,
            destination: destination,
            logDirectory: logDirectory,
            selectedRootIdentity: try directoryIdentity(at: root),
            destinationIdentity: try directoryIdentity(at: destination),
            logDirectoryIdentity: try directoryIdentity(at: logDirectory)
        )
    }

    static func validate(_ snapshot: Snapshot) throws {
        try validateDirectory(snapshot.selectedRoot, expected: snapshot.selectedRootIdentity)
        try validateDirectory(snapshot.destination, expected: snapshot.destinationIdentity)
        try validateDirectory(snapshot.logDirectory, expected: snapshot.logDirectoryIdentity)
        try verifyCanonicalContainment(candidate: snapshot.destination, root: snapshot.selectedRoot)
        try verifyCanonicalContainment(candidate: snapshot.logDirectory, root: snapshot.selectedRoot)
    }

    private static func standardizedDirectoryURL(path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    private static func ensureDirectory(at candidate: URL, within root: URL, createIfMissing: Bool) throws {
        guard isContained(candidate, in: root) else {
            throw PolicyError.outsideSelectedRoot(candidate.path)
        }

        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        var current = root

        if candidate.path == root.path {
            _ = try directoryIdentity(at: root)
            return
        }

        for component in candidateComponents.dropFirst(rootComponents.count) {
            current.appendPathComponent(component, isDirectory: true)
            switch try itemKind(at: current) {
            case .missing:
                guard createIfMissing else {
                    throw PolicyError.notDirectory(current.path)
                }
                do {
                    try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
                } catch {
                    throw PolicyError.filesystem("无法创建目标目录 \(current.path)：\(error.localizedDescription)")
                }
            case .symbolicLink:
                throw PolicyError.symbolicLink(current.path)
            case .directory:
                break
            case .other:
                throw PolicyError.notDirectory(current.path)
            }
        }

        _ = try directoryIdentity(at: candidate)
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
        candidate.path == root.path || candidate.path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/")
    }
}
