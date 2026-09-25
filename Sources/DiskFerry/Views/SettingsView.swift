import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: TransferStore
    @State private var version = ""

    var body: some View {
        Form {
            Section {
                TextField("rclone 路径", text: $store.rclonePath, prompt: Text("自动检测"))
                    .font(.system(.body, design: .monospaced))
                HStack {
                    Text(version.isEmpty ? "未检测" : version)
                        .font(.caption)
                        .foregroundStyle(version.hasPrefix("rclone") ? Color.secondary : Color.red)
                    Spacer()
                    Button("自动检测") {
                        store.rclonePath = RcloneLocator.locate(preferredPath: nil) ?? ""
                    }
                }
            } header: {
                Text("rclone")
            } footer: {
                Text("通过 Homebrew 安装：brew install rclone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .task(id: store.rclonePath) {
            let path = store.rclonePath
            version = await Task.detached(priority: .utility) {
                Self.detectVersion(path: path)
            }.value
        }
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
