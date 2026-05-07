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
