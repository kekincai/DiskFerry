import SwiftUI

struct HeatmapView: View {
    var items: [FolderHeatmapItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("文件夹热力图")
                    .font(.headline)
                Spacer()
                Text("颜色越深，复制越接近完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                Text("开始复制后，这里会显示源目录第一层子文件夹和文件的复制状态。")
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
