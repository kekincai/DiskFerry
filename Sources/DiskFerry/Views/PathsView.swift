import SwiftUI

struct PathsView: View {
    @ObservedObject var store: TransferStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("目录")
                .font(.headline)

            PathRow(
                title: "源文件夹",
                path: store.task.sourcePath,
                placeholder: "/Volumes/PhotoDisk/Photos",
                actionTitle: "选择...",
                action: store.chooseSource
            )

            PathRow(
                title: "目标文件夹",
                path: store.task.targetPath,
                placeholder: "/Volumes/WinBackup/PhotosBackup",
                actionTitle: "选择...",
                action: store.chooseTarget
            )

            PathRow(
                title: "日志目录",
                path: store.task.logDirectory,
                placeholder: "目标目录/_transfer_logs/",
                actionTitle: "打开",
                action: store.openLogDirectory
            )

            Text("推荐选择 /Volumes/ 下的 SMB 挂载目录或外置磁盘目录。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }
}

private struct PathRow: View {
    var title: String
    var path: String
    var placeholder: String
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)

            Text(path.isEmpty ? placeholder : path)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(path.isEmpty ? .tertiary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(actionTitle, action: action)
        }
    }
}
