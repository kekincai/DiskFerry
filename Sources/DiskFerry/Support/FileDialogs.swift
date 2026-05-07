import AppKit

enum FileDialogs {
    static func chooseFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"

        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
