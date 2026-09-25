import Foundation

enum RcloneLocator {
    static let commonPaths = [
        "/opt/homebrew/bin/rclone",
        "/usr/local/bin/rclone",
        "/usr/bin/rclone"
    ]

    static func locate(preferredPath: String?) -> String? {
        let fileManager = FileManager.default

        if let preferredPath, !preferredPath.isEmpty,
           fileManager.isExecutableFile(atPath: preferredPath) {
            return preferredPath
        }

        for path in commonPaths where fileManager.isExecutableFile(atPath: path) {
            return path
        }

        let pathEnvironment = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathEnvironment.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent("rclone")
                .path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }
}

/// Optional flags that only newer rclone builds understand. Probed once per binary.
enum RcloneCapabilities {
    private static let lock = NSLock()
    private static var cache: [String: Set<String>] = [:]

    /// `--local-no-clone` (rclone ≥ 1.69). Without it, local → mounted-volume copies go
    /// through the OS file copy, which rclone reports only once each file finishes.
    static func supportsLocalNoClone(rclonePath: String) -> Bool {
        flags(rclonePath: rclonePath).contains("--local-no-clone")
    }

    private static func flags(rclonePath: String) -> Set<String> {
        lock.lock()
        if let cached = cache[rclonePath] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: rclonePath)
        process.arguments = ["help", "flags", "local"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        var found = Set<String>()
        if (try? process.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            if text.contains("--local-no-clone") {
                found.insert("--local-no-clone")
            }
        }

        lock.lock()
        cache[rclonePath] = found
        lock.unlock()
        return found
    }
}
