import Foundation

enum PathInspector {
    static func volumeHint(for path: String) -> String? {
        guard !path.isEmpty else { return nil }

        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [
            .volumeLocalizedNameKey,
            .volumeURLKey
        ])

        let volumeName = values?.volumeLocalizedName
        let volumePath = values?.volume?.path

        if path == volumePath, path.hasPrefix("/Volumes/") {
            let namePart = volumeName.map { "“\($0)”" } ?? "这个挂载卷"
            return "\(namePart) 是 SMB 或外置盘的挂载根目录。若 Windows 把 D 盘共享为该名称，\(path) 就是 D 盘根目录。"
        }

        if let volumePath, path.hasPrefix("/Volumes/") {
            return "所在挂载卷：\(volumeName ?? URL(fileURLWithPath: volumePath).lastPathComponent)（\(volumePath)）"
        }

        return nil
    }
}
