import SwiftUI

struct HeaderView: View {
    @ObservedObject var store: TransferStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ShipMarkView()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Disk Ferry")
                        .font(.title2.weight(.semibold))
                    Text("低缓存、大规模、安全迁移控制器")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StatusBadge(status: store.status)
            }

            ProgressStrip(progress: store.progress, status: store.status)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct StatusBadge: View {
    var status: TransferStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.color)
                .frame(width: 9, height: 9)
            Text(status.label)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
    }
}

private struct ProgressStrip: View {
    var progress: TransferProgress
    var status: TransferStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(TransferFormatters.percent(progress.percent))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 76, alignment: .leading)

                WaveProgressView(fraction: progress.fraction)
                    .frame(maxWidth: .infinity)

                Text(progress.etaText.map { "剩余 \($0)" } ?? "剩余 -")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 120, alignment: .trailing)
            }

            HStack(spacing: 14) {
                MetricPill(title: "速度", value: progress.speedText ?? "-")
                MetricPill(
                    title: "已复制文件",
                    value: "\(TransferFormatters.integer(progress.transferredFiles)) / \(TransferFormatters.integer(progress.totalFiles))"
                )
                MetricPill(title: "剩余文件", value: TransferFormatters.integer(progress.remainingFiles))
                MetricPill(title: "剩余文件夹", value: TransferFormatters.integer(progress.remainingFoldersEstimate))
                MetricPill(
                    title: "数据",
                    value: "\(TransferFormatters.byteCount(progress.transferredBytes)) / \(TransferFormatters.byteCount(progress.totalBytes))"
                )

                if progress.isScanningSource {
                    Label("正在统计源目录", systemImage: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .opacity(status == .idle && progress.totalFiles == nil ? 0.72 : 1)
    }
}

private struct MetricPill: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 82, alignment: .leading)
    }
}
