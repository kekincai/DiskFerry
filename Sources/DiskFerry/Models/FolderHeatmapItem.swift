import Foundation

struct FolderHeatmapItem: Identifiable, Equatable {
    var id: String { path }
    var name: String
    var path: String
    var kind: HeatmapItemKind
    var sourceBytes: Int64
    var targetBytes: Int64
    var sourceFiles: Int
    var targetFiles: Int
    var sourceFolders: Int
    var targetFolders: Int

    var fraction: Double {
        if sourceBytes > 0 {
            return max(0, min(1, Double(targetBytes) / Double(sourceBytes)))
        }
        if sourceFiles > 0 {
            return max(0, min(1, Double(targetFiles) / Double(sourceFiles)))
        }
        return targetFiles > 0 || targetFolders > 0 ? 1 : 0
    }

    var statusText: String {
        if fraction >= 0.999 {
            return "完成"
        }
        if fraction > 0 {
            return String(format: "%.0f%%", fraction * 100)
        }
        return "等待"
    }
}

enum HeatmapItemKind: Equatable {
    case folder
    case file
}
