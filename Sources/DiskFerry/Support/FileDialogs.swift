import AppKit

enum FileDialogs {
    /// Where the folder picker should open. Checks the filesystem, which can stall on a
    /// dropped share, so call it off the main thread.
    static func startingDirectory(for path: String) -> URL? {
        let fileManager = FileManager.default
        if !path.isEmpty {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
            return isDirectory.boolValue
                ? URL(fileURLWithPath: path, isDirectory: true)
                : URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        return fileManager.fileExists(atPath: "/Volumes") ? URL(fileURLWithPath: "/Volumes", isDirectory: true) : nil
    }

    /// Returns the chosen folders; more than one only when `allowsMultipleSelection` is set.
    @MainActor
    static func chooseFolders(
        startingAt directory: URL?,
        allowsMultipleSelection: Bool = false,
        canCreateDirectories: Bool = false,
        message: String? = nil
    ) -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.canCreateDirectories = canCreateDirectories
        panel.prompt = "选择"
        panel.treatsFilePackagesAsDirectories = false
        panel.message = message ?? ""
        panel.directoryURL = directory
        return panel.runModal() == .OK ? panel.urls.map(\.path) : []
    }
}
