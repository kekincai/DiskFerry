import Foundation

enum SourceScanner {
    static func scan(path: String, excludes: [String]) -> SourceSummary {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let excludedNames = Set(excludes.compactMap(simpleExcludedName))
            .union(["_transfer_logs"])
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey
        ]

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return SourceSummary(fileCount: 0, folderCount: 0, totalBytes: 0)
        }

        var fileCount = 0
        var folderCount = 0
        var totalBytes: Int64 = 0

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if excludedNames.contains(name) || name.hasPrefix("._") {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                folderCount += 1
            } else if values?.isRegularFile == true {
                fileCount += 1
                let size = values?.totalFileAllocatedSize ?? values?.fileSize ?? 0
                totalBytes += Int64(size)
            }
        }

        return SourceSummary(fileCount: fileCount, folderCount: folderCount, totalBytes: totalBytes)
    }

    private static func simpleExcludedName(from pattern: String) -> String? {
        if pattern.hasSuffix("/**") {
            return String(pattern.dropLast(3))
        }
        if pattern.contains("*") {
            return nil
        }
        return pattern
    }
}
