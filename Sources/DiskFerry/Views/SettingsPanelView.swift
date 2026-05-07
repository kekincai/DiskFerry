import SwiftUI

struct SettingsPanelView: View {
    @ObservedObject var store: TransferStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("复制模式")
                .font(.headline)

            Picker("复制模式", selection: Binding(
                get: { store.task.mode },
                set: { store.setMode($0) }
            )) {
                ForEach(CopyMode.allCases) { mode in
                    Text("\(mode.title)  \(mode.detail)")
                        .tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            HStack(spacing: 18) {
                Stepper("Transfers: \(store.task.transfers)", value: $store.task.transfers, in: 1...4)
                    .disabled(store.task.mode != .custom)
                Stepper("Checkers: \(store.task.checkers)", value: $store.task.checkers, in: 1...8)
                    .disabled(store.task.mode != .custom)
                Spacer()
            }

            Toggle(isOn: .constant(true)) {
                Text("排除 macOS 系统文件")
            }
            .disabled(true)

            Toggle(isOn: $store.task.verifyAfterCopy) {
                Text("复制完成后执行 size-only 校验")
            }
            .disabled(!store.canStart)

            Text("默认关闭。校验会再次读取目录元数据，适合复制完成后手动确认，不影响正常复制速度。")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [.init(.adaptive(minimum: 170), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(store.task.excludes, id: \.self) { exclude in
                    Label(exclude, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack {
                Text("rclone 路径")
                    .foregroundStyle(.secondary)
                TextField("自动检测", text: $store.rclonePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .panelStyle()
    }
}
