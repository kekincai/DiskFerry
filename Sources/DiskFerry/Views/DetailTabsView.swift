import SwiftUI

struct DetailTabsView: View {
    @ObservedObject var store: TransferStore
    let monitor: TransferMonitor

    @AppStorage("detailTab") private var tab: Tab = .files

    enum Tab: String, CaseIterable, Identifiable {
        case files
        case checks
        case compare

        var id: String { rawValue }

        var title: String {
            switch self {
            case .files: "正在传输"
            case .checks: "检查结果"
            case .compare: "目录对比"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(title(for: tab)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Group {
                switch tab {
                case .files:
                    ActiveFilesView(monitor: monitor, isRunning: store.status.isRunningProcess)
                case .checks:
                    ChecksView(items: store.precheckItems)
                case .compare:
                    HeatmapView(
                        lastRefresh: store.lastHeatmapRefresh,
                        items: store.heatmapItems,
                        isRefreshing: store.isRefreshingHeatmap,
                        canRefresh: store.task.isReady,
                        onRefresh: store.refreshHeatmapOnce
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cardStyle(padding: 12)
        }
        .frame(minHeight: 180)
    }

    private func title(for tab: Tab) -> String {
        if tab == .checks, store.precheckItems.contains(where: { $0.severity == .error }) {
            return "检查结果 ⚠︎"
        }
        return tab.title
    }
}

private struct ActiveFilesView: View {
    @ObservedObject var monitor: TransferMonitor
    var isRunning: Bool

    var body: some View {
        let active = monitor.progress.active
        if active.isEmpty {
            Placeholder(
                symbol: "doc.on.doc",
                text: isRunning
                    ? (monitor.progress.phase == .comparing ? "正在比对源和目标，比对完成后开始传输。" : "等待下一个文件…")
                    : "复制时，这里实时显示正在传输的文件。"
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(active) { file in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(file.name)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(file.name)
                                Spacer()
                                Text(detail(file))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: file.fraction)
                                .progressViewStyle(.linear)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func detail(_ file: ActiveTransfer) -> String {
        var text = "\(TransferFormatters.byteCount(file.bytes)) / \(TransferFormatters.byteCount(file.size))"
        if let speed = file.speed, speed > 0 {
            text += " · \(TransferFormatters.speed(speed))"
        }
        return text
    }
}

private struct ChecksView: View {
    var items: [PrecheckItem]

    var body: some View {
        if items.isEmpty {
            Placeholder(symbol: "checklist", text: "开始复制或预演时会自动检查 rclone、源、目标和写入权限。")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: icon(for: item.severity))
                                .foregroundStyle(color(for: item.severity))
                                .frame(width: 16)
                            Text(item.title)
                                .font(.callout.weight(.medium))
                                .frame(width: 110, alignment: .leading)
                            Text(item.message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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

struct Placeholder: View {
    var symbol: String
    var text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
