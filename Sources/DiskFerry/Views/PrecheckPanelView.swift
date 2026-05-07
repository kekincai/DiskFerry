import SwiftUI

struct PrecheckPanelView: View {
    var items: [PrecheckItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("预检查")
                .font(.headline)

            if items.isEmpty {
                Text("点击“预检查”后会检查 rclone、源目录、目标目录、写入权限、日志目录和本机剩余空间。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(for: item.severity))
                            .foregroundStyle(color(for: item.severity))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.callout.weight(.medium))
                            Text(item.message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .panelStyle()
    }

    private func icon(for severity: CheckSeverity) -> String {
        switch severity {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private func color(for severity: CheckSeverity) -> Color {
        switch severity {
        case .ok: .green
        case .warning: .orange
        case .error: .red
        }
    }
}
