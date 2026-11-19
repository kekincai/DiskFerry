import SwiftUI

struct OptionsBar: View {
    @ObservedObject var store: TransferStore
    @State private var showsAdvanced = false

    var body: some View {
        HStack(spacing: 16) {
            Picker("速度", selection: Binding(
                get: { store.task.mode },
                set: { store.setMode($0) }
            )) {
                ForEach(CopyMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help(store.task.mode.detail)

            Toggle("先统计再复制", isOn: $store.task.checkFirst)
                .help("先比对完所有文件再开始传输，总量和剩余时间从一开始就准确。关闭后会边比对边复制。")

            Toggle("复制后校验", isOn: $store.task.verifyAfterCopy)
                .help("复制完成后再按文件大小核对一遍（rclone check --size-only），不读取文件内容。")

            Spacer(minLength: 0)

            Button {
                showsAdvanced.toggle()
            } label: {
                Label("高级", systemImage: "slider.horizontal.3")
            }
            .popover(isPresented: $showsAdvanced, arrowEdge: .bottom) {
                AdvancedOptionsView(store: store)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(!store.canEdit)
    }
}

private struct AdvancedOptionsView: View {
    @ObservedObject var store: TransferStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("高级选项")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text(store.task.mode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    Stepper("并行传输：\(store.task.transfers)", value: $store.task.transfers, in: 1...8)
                    Stepper("并行比对：\(store.task.checkers)", value: $store.task.checkers, in: 1...16)
                }
                .disabled(store.task.mode != .custom)
                if store.task.mode != .custom {
                    Text("选择“自定义”速度后可以调整。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("始终跳过的系统文件")
                    .font(.subheadline.weight(.medium))
                Text(store.task.excludes.joined(separator: "   "))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("清理 macOS 生成的 ._ 文件", isOn: $store.task.cleanSidecars)
                    .toggleStyle(.checkbox)
                Text("复制到 exFAT、FAT 这类磁盘时，macOS 会给每个文件附带一个 4KB 的 ._ 文件。开启后复制完成时自动删除，带标签等信息的不删。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("rclone 命令")
                    .font(.subheadline.weight(.medium))
                Text(commandPreview)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("拷贝命令") {
                    store.copyPathToClipboard(commandPreview)
                }
                .controlSize(.small)
                .disabled(!store.task.isReady)
            }

            Text("预览不含实时统计用的 --rc 参数（每次运行随机生成端口和密码），可以直接在终端运行。除了复制的文件，不会在目标或本机写入任何日志。rclone 路径可在“设置”中修改。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 440)
        .disabled(!store.canEdit)
    }

    private var commandPreview: String {
        guard store.task.isReady else { return "选择源和目标后显示。" }
        // The target's file system comes from the off-main location check, so the
        // preview shows `--modify-window` like the real run without touching the disk.
        let arguments = RcloneRunner().makeArguments(
            task: store.task,
            dryRun: false,
            streamLocalCopies: store.rcloneSupportsLocalNoClone,
            destinationFileSystem: store.targetStatus.volume?.fileSystem
        )
        let rclone = store.rclonePath.isEmpty ? "rclone" : store.rclonePath
        return ([rclone] + arguments).map(shellQuote).joined(separator: " ")
    }

    private func shellQuote(_ value: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./=:"))
        if value.unicodeScalars.allSatisfy(safe.contains) { return value }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
