import SwiftUI

struct HeatmapView: View {
    var lastRefresh: Date?
    var items: [FolderHeatmapItem]
    var onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("文件夹热力图")
                    .font(.headline)
                Spacer()
                if let lastRefresh {
                    Text("更新于 \(lastRefresh.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    onRefresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                Text("颜色越深，复制越接近完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                Text("默认不自动扫描，以保证复制时窗口滚动流畅。需要查看子文件夹状态时点“刷新”。")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
                    ForEach(items) { item in
                        HeatmapCell(item: item)
                    }
                }
            }
        }
        .panelStyle()
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
