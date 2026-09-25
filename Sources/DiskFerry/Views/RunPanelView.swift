import SwiftUI

struct RunPanelView: View {
    @ObservedObject var store: TransferStore
    /// Deliberately not observed here: only `LiveProgressView` redraws on each stats tick.
    let monitor: TransferMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                StatusDot(color: store.status.color, size: 10)
                Text(store.headline)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                actions
            }

            if showsProgress, monitor.progress.hasStarted || store.status.isRunningProcess {
                LiveProgressView(monitor: monitor, status: store.status, isDryRun: store.isDryRunResult)
            }

            if let result = store.lastResult, !store.status.isBusy {
                ResultSummary(
                    result: result,
                    isFromEarlierRun: store.status == .idle,
                    onOpenTarget: { store.revealInFinder(.target) }
                )
            }

            if store.status == .failed, !store.failureDetails.isEmpty || !store.failureLog.isEmpty {
                FailureLogView(
                    errors: store.failureDetails,
                    log: store.failureLog,
                    onCopy: { store.copyPathToClipboard(store.failureLog.joined(separator: "\n")) }
                )
            }
        }
        .cardStyle()
    }

    private var showsProgress: Bool {
        store.status.isRunningProcess || store.status == .stopping
            || (store.lastResult != nil && store.status != .idle)
    }

    @ViewBuilder
    private var actions: some View {
        if store.canStop || store.status == .stopping {
            Button(role: .destructive) {
                store.stop()
            } label: {
                Label("停止", systemImage: "stop.fill")
            }
            .controlSize(.large)
            .disabled(!store.canStop)
            .keyboardShortcut(".", modifiers: .command)
        } else {
            Button("预演") {
                store.startDryRun()
            }
            .controlSize(.large)
            .disabled(!store.canStart)
            .help("只比对，列出将要复制的文件数和大小，不写入任何文件（⇧⌘R）")

            Button {
                store.startCopy()
            } label: {
                if store.status == .prechecking {
                    ProgressView().controlSize(.small).padding(.horizontal, 20)
                } else {
                    Label(startTitle, systemImage: "arrow.right.circle.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!store.canStart)
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    private var startTitle: String {
        switch store.status {
        case .cancelled, .failed: "继续复制"
        default: store.task.lastRun == nil ? "开始复制" : "再次同步"
        }
    }
}

private struct LiveProgressView: View {
    @ObservedObject var monitor: TransferMonitor
    var status: TransferStatus
    var isDryRun: Bool

    private var progress: TransferProgress { monitor.progress }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(primaryText)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(phaseText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if let etaText {
                    Text(etaText)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(status == .failed ? .red : (status == .cancelled ? .orange : .accentColor))
            } else if status.isRunningProcess {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            metrics

            if progress.phase == .transferring, !progress.totalsAreFinal {
                Text("正在边比对边复制，总量可能还会增加。开启“先统计再复制”可以让进度从一开始就准确。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if progress.errors > 0, let lastError = progress.lastError {
                Label("\(progress.errors) 个错误 · 最近：\(lastError)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
    }

    private var primaryText: String {
        switch progress.phase {
        case .waiting:
            return status.isRunningProcess ? "启动中" : "-"
        case .comparing:
            return "比对中"
        default:
            return TransferFormatters.percent(progress.fraction)
        }
    }

    private var phaseText: String {
        switch progress.phase {
        case .waiting:
            return ""
        case .comparing:
            var text = "已扫描 \(TransferFormatters.integer(max(progress.listed, progress.checks))) 个项目"
            if progress.totalTransfers > 0 {
                text += " · 需\(isDryRun ? "要" : "")复制 \(TransferFormatters.integer(progress.totalTransfers)) 个（\(TransferFormatters.byteCount(progress.totalBytes))）"
            }
            return text
        case .transferring:
            return isDryRun ? "预演" : "已复制"
        case .verifying:
            return "校验 \(TransferFormatters.integer(progress.checks)) / \(TransferFormatters.integer(progress.totalChecks))"
        case .finished:
            return ""
        }
    }

    private var etaText: String? {
        guard status.isRunningProcess, progress.phase == .transferring || progress.phase == .verifying else { return nil }
        guard let eta = progress.eta, progress.totalsAreFinal || progress.phase == .verifying else {
            return progress.elapsed > 0 ? "已用 \(TransferFormatters.duration(progress.elapsed))" : nil
        }
        return "剩余约 \(TransferFormatters.duration(eta))"
    }

    @ViewBuilder
    private var metrics: some View {
        if progress.phase == .transferring || progress.phase == .finished || progress.bytes > 0 {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 16, alignment: .leading)], alignment: .leading, spacing: 8) {
                Metric(
                    title: "数据",
                    value: "\(TransferFormatters.byteCount(progress.bytes)) / \(TransferFormatters.byteCount(progress.totalBytes))"
                )
                Metric(
                    title: "文件",
                    value: "\(TransferFormatters.integer(progress.transfers)) / \(TransferFormatters.integer(progress.totalTransfers))"
                )
                Metric(title: "当前速度", value: TransferFormatters.speed(progress.currentSpeed))
                Metric(title: "平均速度", value: TransferFormatters.speed(progress.averageSpeed))
                Metric(title: "已跳过（目标已有）", value: TransferFormatters.integer(progress.skippedFiles))
                Metric(title: "用时", value: TransferFormatters.duration(progress.elapsed))
            }
        }
    }
}

private struct Metric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct ResultSummary: View {
    var result: RunRecord
    var isFromEarlierRun: Bool
    var onOpenTarget: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.outcome.symbolName)
                .foregroundStyle(result.outcome.color)
            Text(summaryText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if result.outcome != .dryRun {
                Button("打开目标文件夹", action: onOpenTarget)
            }
        }
        .controlSize(.small)
    }

    private var summaryText: String {
        guard isFromEarlierRun else {
            // The live metrics above already show this run's numbers.
            switch result.outcome {
            case .dryRun: return "预演不会写入任何文件。"
            case .failed, .cancelled: return "已复制的文件会保留，“继续复制”只补齐剩下的。"
            case .completed, .verified: return "已保存到左侧路线，下次一键再次同步。"
            }
        }
        var parts = ["上次：\(TransferFormatters.relativeDate(result.finishedAt)) \(result.outcome.label)"]
        if result.outcome != .dryRun {
            parts.append("\(TransferFormatters.integer(result.files)) 个文件")
            parts.append(TransferFormatters.byteCount(result.bytes))
        }
        parts.append("用时 \(TransferFormatters.duration(result.duration))")
        if result.errors > 0 {
            parts.append("\(result.errors) 个错误")
        }
        return parts.joined(separator: " · ")
    }
}

/// rclone's output for a failed run. Lives only in memory; nothing is written to disk.
private struct FailureLogView: View {
    var errors: [String]
    var log: [String]
    var onCopy: () -> Void

    @State private var showsFullLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(errors.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            if !log.isEmpty {
                HStack {
                    Button(showsFullLog ? "收起 rclone 输出" : "显示 rclone 输出（\(log.count) 行）") {
                        showsFullLog.toggle()
                    }
                    .buttonStyle(.link)
                    Spacer()
                    Button("拷贝", action: onCopy)
                        .controlSize(.small)
                }
                .font(.caption)

                if showsFullLog {
                    ScrollView {
                        Text(log.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
