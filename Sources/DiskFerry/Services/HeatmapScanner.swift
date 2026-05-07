import Foundation

enum HeatmapScanner {
    static func aggregateTargetSummary(from items: [FolderHeatmapItem]) -> SourceSummary {
        SourceSummary(
            fileCount: items.reduce(0) { $0 + $1.targetFiles },
            folderCount: items.reduce(0) { $0 + $1.targetFolders },
            totalBytes: items.reduce(0) { $0 + $1.targetBytes }
        )
    }

    static func scan(sourcePath: String, targetPath: String, excludes: [String], limit: Int = 240) -> [FolderHeatmapItem] {
        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: sourcePath, isDirectory: true)
        let targetURL = URL(fileURLWithPath: targetPath, isDirectory: true)
        let excludedNames = Set(excludes.compactMap(simpleExcludedName)).union(["_transfer_logs"])

        guard let children = try? fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children
            .filter { child in
                let name = child.lastPathComponent
                return !excludedNames.contains(name) && !name.hasPrefix("._")
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(limit)
            .map { sourceChild in
                let name = sourceChild.lastPathComponent
                let targetChild = targetURL.appendingPathComponent(name)
                let sourceSummary = summarizeFast(url: sourceChild, excludes: excludes)
                let targetSummary = summarizeFast(url: targetChild, excludes: excludes)
                let kind: HeatmapItemKind = isDirectory(sourceChild) ? .folder : .file
                return FolderHeatmapItem(
                    name: name,
                    path: sourceChild.path,
                    kind: kind,
                    sourceBytes: sourceSummary.totalBytes,
                    targetBytes: targetSummary.totalBytes,
                    sourceFiles: sourceSummary.fileCount,
                    targetFiles: targetSummary.fileCount,
                    sourceFolders: sourceSummary.folderCount,
                    targetFolders: targetSummary.folderCount
                )
            }
    }

    private static func summarizeFast(url: URL, excludes: [String]) -> SourceSummary {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return SourceSummary(fileCount: 0, folderCount: 0, totalBytes: 0)
        }

        if isDirectory.boolValue {
            return shallowDirectorySummary(url: url, excludes: excludes)
        }

        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey])
        guard values?.isRegularFile == true else {
            return SourceSummary(fileCount: 0, folderCount: 0, totalBytes: 0)
        }
        let size = values?.totalFileAllocatedSize ?? values?.fileSize ?? 0
        return SourceSummary(fileCount: 1, folderCount: 0, totalBytes: Int64(size))
    }

    private static func shallowDirectorySummary(url: URL, excludes: [String]) -> SourceSummary {
        let excludedNames = Set(excludes.compactMap(simpleExcludedName)).union(["_transfer_logs"])
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return SourceSummary(fileCount: 0, folderCount: 1, totalBytes: 0)
        }

        var fileCount = 0
        var folderCount = 1
        var totalBytes: Int64 = 0

        for child in children.prefix(500) {
            let name = child.lastPathComponent
            guard !excludedNames.contains(name), !name.hasPrefix("._") else { continue }
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey])
            if values?.isDirectory == true {
                folderCount += 1
            } else if values?.isRegularFile == true {
                fileCount += 1
                totalBytes += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            }
        }

        return SourceSummary(fileCount: max(fileCount, children.isEmpty ? 0 : 1), folderCount: folderCount, totalBytes: max(totalBytes, children.isEmpty ? 0 : 1))
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
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
