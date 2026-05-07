import SwiftUI

struct StatusPanelView: View {
    @ObservedObject var store: TransferStore
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 8) {
                    infoRow("当前状态", store.status.label)
                    infoRow("消息", store.lastMessage)
                    infoRow("日志文件", store.currentLogFile.isEmpty ? "尚未生成" : store.currentLogFile)
                    infoRow("Summary", store.currentSummaryFile.isEmpty ? "尚未生成" : store.currentSummaryFile)
                    infoRow("开始时间", store.startedAt.map { $0.formatted(date: .numeric, time: .standard) } ?? "尚未开始")
                    infoRow("结束时间", store.finishedAt.map { $0.formatted(date: .numeric, time: .standard) } ?? "尚未结束")
                }
            }
            .padding(.top, 8)
        } label: {
            Label("状态", systemImage: "info.circle")
                .font(.headline)
        }
        .panelStyle()
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
