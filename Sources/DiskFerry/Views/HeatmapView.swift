import SwiftUI

struct HeatmapView: View {
    var lastRefresh: Date?
    var items: [FolderHeatmapItem]
    var isRefreshing: Bool
    var canRefresh: Bool
    var onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("按顶层子文件夹对比源和目标的大小，颜色越深越接近完成。只看每个文件夹的第一层，结果仅供参考。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let lastRefresh {
                    Text(lastRefresh.formatted(date: .omitted, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    onRefresh()
                } label: {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("扫描", systemImage: "arrow.clockwise")
                    }
                }
                .controlSize(.small)
                .disabled(!canRefresh || isRefreshing)
            }

            if items.isEmpty {
                Placeholder(symbol: "square.grid.3x3", text: "需要时点“扫描”。为了不拖慢复制，这里不会自动刷新。")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                        ForEach(items) { item in
                            HeatmapCell(item: item)
                        }
                    }
                }
            }
        }
    }
}

private struct HeatmapCell: View {
    var item: FolderHeatmapItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: item.kind == .folder ? "folder.fill" : "doc.fill")
                    .font(.caption2)
                Text(item.statusText)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(foregroundColor)

            Text(item.name)
                .font(.caption2)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .foregroundStyle(foregroundColor)

            Spacer(minLength: 0)
        }
        .padding(7)
        .frame(height: 62)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fillColor, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.primary.opacity(0.08))
        }
        .help("\(item.name)\n\(TransferFormatters.percent(item.fraction * 100))\n\(TransferFormatters.byteCount(item.targetBytes)) / \(TransferFormatters.byteCount(item.sourceBytes))")
    }

    private var fillColor: Color {
        let fraction = item.fraction
        if fraction >= 0.999 {
            return Color.green.opacity(0.86)
        }
        if fraction <= 0 {
            return Color.gray.opacity(0.16)
        }
        return Color.green.opacity(0.18 + fraction * 0.62)
    }

    private var foregroundColor: Color {
        item.fraction > 0.62 ? .white : .primary
    }
}
