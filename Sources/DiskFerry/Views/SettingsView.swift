import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: TransferStore
    /// Edited locally and committed on Return, so typing does not save to UserDefaults
    /// or launch `rclone version` on every keystroke.
    @State private var draftPath = ""
    @State private var version = ""

    var body: some View {
        Form {
            Section {
                TextField("rclone 路径", text: $draftPath, prompt: Text("自动检测"))
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(commit)
                HStack {
                    Text(versionText)
                        .font(.caption)
                        .foregroundStyle(version.hasPrefix("rclone") && !hasUncommittedEdit ? Color.secondary : Color.red)
                    Spacer()
                    Button("自动检测") {
                        draftPath = RcloneLocator.locate(preferredPath: nil) ?? ""
                        commit()
                    }
                }
            } header: {
                Text("rclone")
            } footer: {
                Text("输入路径后按回车生效。通过 Homebrew 安装：brew install rclone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear { draftPath = store.rclonePath }
        .onDisappear(perform: commit)
        .task(id: store.rclonePath) {
            let path = store.rclonePath
            version = await Task.detached(priority: .utility) {
                Self.detectVersion(path: path)
            }.value
        }
    }

    private var hasUncommittedEdit: Bool {
        draftPath != store.rclonePath
    }

    private var versionText: String {
        if hasUncommittedEdit { return "按回车检测这个路径" }
        return version.isEmpty ? "未检测" : version
    }

    private func commit() {
        let trimmed = draftPath.trimmingCharacters(in: .whitespacesAndNewlines)
        draftPath = trimmed
        if trimmed != store.rclonePath { store.rclonePath = trimmed }
    }

    nonisolated private static func detectVersion(path: String) -> String {
        guard let resolved = RcloneLocator.locate(preferredPath: path) else {
            return "没有找到可执行的 rclone"
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = ["version"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let firstLine = String(decoding: data, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? ""
            return firstLine.isEmpty ? "无法读取版本" : "\(firstLine)  (\(resolved))"
        } catch {
            return "无法运行：\(error.localizedDescription)"
        }
    }
}
