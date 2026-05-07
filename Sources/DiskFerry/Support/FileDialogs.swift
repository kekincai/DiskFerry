import AppKit

enum FileDialogs {
    static func chooseFolder(startingAt path: String? = nil, canCreateDirectories: Bool = false) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = canCreateDirectories
        panel.prompt = "选择"
        panel.treatsFilePackagesAsDirectories = false

        if let path, !path.isEmpty {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
                panel.directoryURL = isDirectory.boolValue
                    ? URL(fileURLWithPath: path, isDirectory: true)
                    : URL(fileURLWithPath: path).deletingLastPathComponent()
            }
        } else if FileManager.default.fileExists(atPath: "/Volumes") {
            panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        }

        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
