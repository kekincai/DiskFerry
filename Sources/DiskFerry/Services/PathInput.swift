import Foundation
import NetFS

/// Turns whatever the user pasted or dropped into a local folder path. Understands
/// Finder paths, `file://` URLs, `~`, `smb://server/share/…`, Windows UNC paths
/// (`\\server\share\…`) and mount sources (`//user@server/share/…`).
enum PathInput {
    enum Parsed: Equatable {
        case local(String)
        case smb(server: String, share: String, subpath: [String])
        case invalid(String)
    }

    enum Resolution: Equatable {
        case folder(String)
        /// The share is not mounted yet; mounting `smbURL` makes `subpath` reachable.
        case needsMount(smbURL: URL, server: String, share: String, subpath: [String])
        case failure(String)
    }

    static func parse(_ raw: String) -> Parsed {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotes: Set<Character> = ["\"", "'", "“", "”", "‘", "’"]
        while let first = text.first, let last = text.last, text.count >= 2, quotes.contains(first), quotes.contains(last) {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty else { return .invalid("路径为空。") }

        let lower = text.lowercased()
        if lower.hasPrefix("file://") {
            guard let url = URL(string: text), url.isFileURL else { return .invalid("无法识别的文件地址。") }
            return .local(url.standardizedFileURL.path)
        }
        if lower.hasPrefix("smb://") || lower.hasPrefix("cifs://") {
            return parseSMBURL(text)
        }
        if text.hasPrefix("\\\\") {
            return parseServerPath(text.replacingOccurrences(of: "\\", with: "/").dropFirst(2), encoded: false)
        }
        if text.hasPrefix("//") {
            return parseServerPath(text.dropFirst(2), encoded: true)
        }
        if text.hasPrefix("~") {
            return .local((text as NSString).expandingTildeInPath)
        }
        if text.hasPrefix("/") {
            return .local(URL(fileURLWithPath: text).standardizedFileURL.path)
        }
        if text.count >= 2, text.dropFirst().first == ":", text.first?.isLetter == true {
            return .invalid("这是 Windows 本地盘符路径。请在 Windows 上共享该文件夹，然后粘贴 \\\\电脑名\\共享名 形式的地址。")
        }
        return .invalid("无法识别的路径：\(text)")
    }

    /// Resolves a parsed input against the currently mounted volumes. Calls `statfs`,
    /// so run it off the main thread.
    static func resolve(_ raw: String) -> Resolution {
        switch parse(raw) {
        case let .invalid(message):
            return .failure(message)
        case let .local(path):
            return checkFolder(path)
        case let .smb(server, share, subpath):
            if let mountPoint = VolumeCatalog.mountPoint(forServer: server, share: share) {
                let path = subpath.reduce(URL(fileURLWithPath: mountPoint, isDirectory: true)) {
                    $0.appendingPathComponent($1, isDirectory: true)
                }.path
                return checkFolder(path)
            }
            var components = URLComponents()
            components.scheme = "smb"
            components.host = server
            components.path = "/" + share
            guard let url = components.url else {
                return .failure("无法识别的共享地址：\(server)/\(share)")
            }
            return .needsMount(smbURL: url, server: server, share: share, subpath: subpath)
        }
    }

    /// Mounts an SMB share under /Volumes, letting macOS show its own login dialog and
    /// use Keychain credentials. Blocks until the user finishes, so call it off the main thread.
    static func mount(_ smbURL: URL) -> Result<String, MountError> {
        let openOptions = NSMutableDictionary()
        openOptions[kNAUIOptionKey] = kNAUIOptionAllowUI
        var mountPoints: Unmanaged<CFArray>?
        let status = NetFSMountURLSync(
            smbURL as CFURL,
            nil,
            nil,
            nil,
            openOptions as CFMutableDictionary,
            nil,
            &mountPoints
        )
        let points = mountPoints?.takeRetainedValue() as? [String] ?? []

        if status == 0, let first = points.first {
            return .success(first)
        }
        // EEXIST: already mounted (possibly under a different host alias).
        if status == EEXIST,
           let host = smbURL.host,
           let share = smbURL.pathComponents.dropFirst().first,
           let existing = VolumeCatalog.mountPoint(forServer: host, share: share) {
            return .success(existing)
        }
        // -128 is userCanceledErr from the login sheet.
        if status == ECANCELED || status == -128 {
            return .failure(.cancelled)
        }
        return .failure(.failed(Int(status)))
    }

    enum MountError: Error, Equatable {
        case cancelled
        case failed(Int)

        var message: String {
            switch self {
            case .cancelled:
                return "已取消连接服务器。"
            case let .failed(code):
                return "无法连接共享（错误 \(code)）。请确认电脑名 / IP、共享名和账号是否正确。"
            }
        }
    }

    private static func checkFolder(_ path: String) -> Resolution {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .failure("找不到这个位置：\(path)")
        }
        guard isDirectory.boolValue else {
            return .failure("这是一个文件，请选择文件夹：\(path)")
        }
        return .folder(URL(fileURLWithPath: path).standardizedFileURL.path)
    }

    private static func parseSMBURL(_ text: String) -> Parsed {
        // URLComponents rejects unescaped spaces and CJK; escape the path part first.
        let schemeEnd = text.range(of: "://")!.upperBound
        let rest = String(text[schemeEnd...])
        let escaped = rest.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.union(["@", ":", "%"])) ?? rest
        guard let components = URLComponents(string: "smb://" + escaped),
              let host = components.host, !host.isEmpty else {
            return .invalid("无法识别的 smb 地址：\(text)")
        }
        let parts = components.path
            .split(separator: "/")
            .map { String($0).removingPercentEncoding ?? String($0) }
        return makeSMB(host: host.removingPercentEncoding ?? host, parts: parts)
    }

    private static func parseServerPath(_ text: Substring, encoded: Bool) -> Parsed {
        var parts = text.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return .invalid("缺少服务器名称。") }
        var host = parts.removeFirst()
        if let at = host.lastIndex(of: "@") {
            host = String(host[host.index(after: at)...])
        }
        if encoded {
            parts = parts.map { $0.removingPercentEncoding ?? $0 }
        }
        return makeSMB(host: host, parts: parts)
    }

    private static func makeSMB(host: String, parts: [String]) -> Parsed {
        guard let share = parts.first, !share.isEmpty else {
            return .invalid("请包含共享名，例如 smb://\(host)/共享名")
        }
        let subpath = parts.dropFirst().filter { $0 != "." && !$0.isEmpty }
        guard !subpath.contains("..") else {
            return .invalid("路径中不能包含 “..”。")
        }
        return .smb(server: host, share: share, subpath: Array(subpath))
    }
}
