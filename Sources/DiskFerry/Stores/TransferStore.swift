import AppKit
import Foundation

@MainActor
final class TransferStore: ObservableObject {
    @Published var task: TransferTask
    @Published var status: TransferStatus = .idle
    @Published var outputText = ""
    @Published var precheckItems: [PrecheckItem] = []
    @Published var lastMessage = "请选择源目录和目标目录。"
    @Published var currentLogFile = ""
    @Published var currentSummaryFile = ""
    @Published var startedAt: Date?
    @Published var finishedAt: Date?
    @Published var rclonePath: String
    @Published var recentTasks: [TransferTask] = []
    @Published var progress: TransferProgress = .empty
    @Published var heatmapItems: [FolderHeatmapItem] = []
    @Published var lastHeatmapRefresh: Date?

    private let sampler = TransferSampler()
    private let runner = RcloneRunner()
    private let prechecker = PrecheckService()
    private let storage = TaskStorage()
    private var isStopping = false
    private var sourceScanTask: Task<Void, Never>?
    private var targetScanTask: Task<Void, Never>?
    private var logMonitorTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?
    private var heatmapRefreshTask: Task<Void, Never>?
    private var activeDestinationSnapshot: DestinationPathPolicy.Snapshot?
    private var lastLogReadOffset: UInt64 = 0

    init() {
        self.task = .empty
        self.rclonePath = RcloneLocator.locate(preferredPath: nil) ?? ""
        self.recentTasks = storage.loadRecentTasks()
        if let first = recentTasks.first {
            self.task = first
        }
        self.task.refreshLogDirectory()
    }

    var canStart: Bool {
        ![.running, .dryRunning, .verifying, .prechecking, .stopping].contains(status)
    }

    var canStop: Bool {
        [.running, .dryRunning, .verifying].contains(status)
    }

    func chooseSource() {
        guard canStart else { return }
        guard let path = FileDialogs.chooseFolder(startingAt: task.sourcePath) else { return }
        task.sourcePath = path
        updateNameFromPaths()
    }

    func chooseTarget() {
        guard canStart else { return }
        guard let path = FileDialogs.chooseFolder(startingAt: task.targetPath, canCreateDirectories: true) else { return }
        task.targetPath = path
        task.refreshLogDirectory()
        updateNameFromPaths()
    }

    func setMode(_ mode: CopyMode) {
        task.applyMode(mode)
    }

    func precheck() {
        status = .prechecking
        let result = prechecker.run(task: task, rclonePath: rclonePath)
        precheckItems = result.items
        lastMessage = result.summaryText
        status = result.hasErrors ? .failed : .idle
    }

    func startDryRun() {
        start(dryRun: true)
    }

    func startCopy() {
        start(dryRun: false)
    }

    func rerunLastTask() {
        guard !task.sourcePath.isEmpty, !task.targetPath.isEmpty else { return }
        startCopy()
    }

    func stop() {
        guard canStop else { return }
        isStopping = true
        status = .stopping
        lastMessage = "正在停止 rclone。已经完成的文件通常不需要重新复制。"
        sourceScanTask?.cancel()
        targetScanTask?.cancel()
        logMonitorTask?.cancel()
        snapshotTask?.cancel()
        heatmapRefreshTask?.cancel()
        runner.stop()
    }

    func openLogDirectory() {
        let path = task.logDirectory.isEmpty
            ? URL(fileURLWithPath: task.resolvedTargetPath).appendingPathComponent("_transfer_logs").path
            : task.logDirectory
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    func loadRecentTask(_ recent: TransferTask) {
        guard canStart else { return }
        task = recent
        task.refreshLogDirectory()
        lastMessage = "已载入任务：\(recent.name)"
    }

    func refreshHeatmapOnce() {
        guard !task.sourcePath.isEmpty, !task.resolvedTargetPath.isEmpty else { return }
        let sourcePath = task.sourcePath
        let targetPath = task.resolvedTargetPath
        let excludes = task.excludes
        heatmapRefreshTask?.cancel()
        heatmapRefreshTask = Task.detached(priority: .utility) { [weak self] in
            let heatmap = HeatmapScanner.scan(sourcePath: sourcePath, targetPath: targetPath, excludes: excludes, limit: 120)
            await MainActor.run { [weak self] in
                guard !Task.isCancelled else { return }
                self?.heatmapItems = heatmap
                self?.lastHeatmapRefresh = Date()
            }
        }
    }

    private func start(dryRun: Bool) {
        guard canStart else { return }
        activeDestinationSnapshot = nil

        let result = prechecker.run(task: task, rclonePath: rclonePath)
        precheckItems = result.items
        guard !result.hasErrors else {
            status = .failed
            lastMessage = result.summaryText
            return
        }

        guard let resolvedRclone = RcloneLocator.locate(preferredPath: rclonePath) else {
            status = .failed
            lastMessage = "没有找到 rclone。请确认已经通过 Homebrew 安装：brew install rclone"
            return
        }
        rclonePath = resolvedRclone

        task.refreshLogDirectory()

        let destinationSnapshot: DestinationPathPolicy.Snapshot
        do {
            destinationSnapshot = try DestinationPathPolicy.prepare(task: task)
            try DestinationPathPolicy.validate(destinationSnapshot)
        } catch {
            status = .failed
            lastMessage = "目标路径安全检查失败：\(error.localizedDescription)"
            return
        }

        let startDate = Date()
        let stamp = DateStamp.makeLogStamp(date: startDate)
        let logURL = URL(fileURLWithPath: task.logDirectory)
            .appendingPathComponent("\(stamp)\(dryRun ? "-dry-run" : "").log")
        let summaryURL = URL(fileURLWithPath: task.logDirectory)
            .appendingPathComponent("\(stamp)\(dryRun ? "-dry-run" : "").summary.json")

        currentLogFile = logURL.path
        currentSummaryFile = summaryURL.path
        startedAt = startDate
        finishedAt = nil
        isStopping = false
        sourceScanTask?.cancel()
        targetScanTask?.cancel()
        logMonitorTask?.cancel()
        snapshotTask?.cancel()
        heatmapRefreshTask?.cancel()
        lastLogReadOffset = 0
        outputText = ""
        heatmapItems = []
        progress = .empty
        status = dryRun ? .dryRunning : .running
        activeDestinationSnapshot = destinationSnapshot
        lastMessage = dryRun ? "正在预演，不会写入目标目录。" : "正在复制。"

        let liveLogPreviewEnabled = task.liveLogPreviewEnabled
        let commandText = commandPreview(rclonePath: resolvedRclone, logFile: logURL.path, dryRun: dryRun)
        Task { [weak self] in
            guard let self else { return }
            await self.sampler.reset(liveLogPreviewEnabled: liveLogPreviewEnabled)
            await self.sampler.ingestOutput(commandText)
            await MainActor.run { [weak self] in
                self?.beginTransferProcess(
                    rclonePath: resolvedRclone,
                    logFile: logURL.path,
                    dryRun: dryRun,
                    summaryURL: summaryURL,
                    destinationSnapshot: destinationSnapshot
                )
            }
        }
    }

    private func beginTransferProcess(
        rclonePath: String,
        logFile: String,
        dryRun: Bool,
        summaryURL: URL,
        destinationSnapshot: DestinationPathPolicy.Snapshot
    ) {
        do {
            try DestinationPathPolicy.validate(destinationSnapshot)
            startSnapshotPump()
            if !dryRun, task.liveHeatmapEnabled {
                startTargetProgressScanner()
            }
            let sampler = sampler
            try runner.start(
                rclonePath: rclonePath,
                task: task,
                logFile: logFile,
                dryRun: dryRun,
                onOutput: { text in
                    Task {
                        await sampler.ingestOutput(text)
                    }
                },
                onFinish: { [weak self] exitCode in
                    self?.finish(exitCode: exitCode, dryRun: dryRun, summaryURL: summaryURL)
                }
            )
        } catch {
            status = .failed
            finishedAt = Date()
            lastMessage = "无法启动 rclone：\(error.localizedDescription)"
            writeSummary(status: "failed", finishedAt: finishedAt ?? Date(), summaryURL: summaryURL)
        }
    }

    private func finish(exitCode: Int32, dryRun: Bool, summaryURL: URL) {
        let endDate = Date()
        finishedAt = endDate
        sourceScanTask?.cancel()
        targetScanTask?.cancel()
        logMonitorTask?.cancel()
        snapshotTask?.cancel()
        publishSnapshot()

        if isStopping {
            status = .cancelled
            lastMessage = "任务已中断。稍后可以点击“再次运行”继续。"
            writeSummary(status: "cancelled", finishedAt: endDate, summaryURL: summaryURL)
            return
        }

        if exitCode == 0 {
            if !dryRun, task.verifyAfterCopy {
                startVerification(summaryURL: summaryURL)
            } else {
                status = .completed
                if !dryRun {
                    Task {
                        await sampler.markFinished()
                        await MainActor.run {
                            self.publishSnapshot()
                        }
                    }
                }
                lastMessage = dryRun ? "预演完成。" : "复制完成。"
                writeSummary(status: dryRun ? "dry-run-completed" : "completed", finishedAt: endDate, summaryURL: summaryURL)
                saveRecentTask()
            }
        } else {
            status = .failed
            lastMessage = "rclone 退出码：\(exitCode)。请查看日志。"
            writeSummary(status: "failed", finishedAt: endDate, summaryURL: summaryURL)
            saveRecentTask()
        }
    }

    private func startVerification(summaryURL: URL) {
        do {
            guard let activeDestinationSnapshot else {
                throw DestinationPathPolicy.PolicyError.emptyPath
            }
            try DestinationPathPolicy.validate(activeDestinationSnapshot)
        } catch {
            status = .failed
            lastMessage = "复制完成，但目标路径安全检查失败：\(error.localizedDescription)"
            return
        }

        guard let resolvedRclone = RcloneLocator.locate(preferredPath: rclonePath) else {
            status = .failed
            lastMessage = "复制完成，但无法开始校验：没有找到 rclone。"
            writeSummary(status: "copy-completed-check-failed", finishedAt: Date(), summaryURL: summaryURL)
            saveRecentTask()
            return
        }

        status = .verifying
        lastMessage = "复制完成，正在执行 size-only 校验。"
        let checkLogURL = URL(fileURLWithPath: task.logDirectory)
            .appendingPathComponent("\(DateStamp.makeLogStamp())-check.log")
        let sampler = sampler
        Task {
            await sampler.ingestOutput("\n[Disk Ferry] 开始校验：\(checkLogURL.path)\n")
        }

        do {
            try runner.startCheck(
                rclonePath: resolvedRclone,
                task: task,
                logFile: checkLogURL.path,
                onOutput: { text in
                    Task {
                        await sampler.ingestOutput(text)
                    }
                },
                onFinish: { [weak self] exitCode in
                    self?.finishVerification(exitCode: exitCode, summaryURL: summaryURL)
                }
            )
        } catch {
            status = .failed
            lastMessage = "复制完成，但无法启动校验：\(error.localizedDescription)"
            writeSummary(status: "copy-completed-check-failed", finishedAt: Date(), summaryURL: summaryURL)
            saveRecentTask()
        }
    }

    private func finishVerification(exitCode: Int32, summaryURL: URL) {
        let endDate = Date()
        finishedAt = endDate

        if isStopping {
            status = .cancelled
            lastMessage = "校验已中断。复制本身已经完成。"
            writeSummary(status: "copy-completed-check-cancelled", finishedAt: endDate, summaryURL: summaryURL)
            saveRecentTask()
            return
        }

        if exitCode == 0 {
            status = .completed
            Task {
                await sampler.markFinished()
                await MainActor.run {
                    self.publishSnapshot()
                }
            }
            lastMessage = "复制完成，size-only 校验通过。"
            writeSummary(status: "completed-verified-size-only", finishedAt: endDate, summaryURL: summaryURL)
        } else {
            status = .failed
            lastMessage = "复制完成，但 size-only 校验发现差异。请查看校验日志。"
            writeSummary(status: "completed-check-failed", finishedAt: endDate, summaryURL: summaryURL)
        }
        saveRecentTask()
    }

    private func writeSummary(status: String, finishedAt: Date, summaryURL: URL) {
        do {
            guard let activeDestinationSnapshot else {
                throw DestinationPathPolicy.PolicyError.emptyPath
            }
            try DestinationPathPolicy.validate(activeDestinationSnapshot)
        } catch {
            Task {
                await sampler.ingestOutput("\n[Disk Ferry] 已阻止 summary.json 写入：\(error.localizedDescription)\n")
            }
            return
        }

        let summary = TransferSummary(
            taskName: task.name,
            source: task.sourcePath,
            target: task.resolvedTargetPath,
            startedAt: startedAt ?? Date(),
            finishedAt: finishedAt,
            status: status,
            engine: task.engine,
            transfers: task.transfers,
            checkers: task.checkers,
            logFile: currentLogFile
        )

        do {
            let data = try JSONCoding.encoder.encode(summary)
            try data.write(to: summaryURL, options: .atomic)
            currentSummaryFile = summaryURL.path
        } catch {
            Task {
                await sampler.ingestOutput("\n[Disk Ferry] 无法写入 summary.json：\(error.localizedDescription)\n")
            }
        }
    }

    private func saveRecentTask() {
        task.id = DateStamp.makeID(suffix: safeSuffix(task.name))
        task.createdAt = Date()
        recentTasks.removeAll { $0.sourcePath == task.sourcePath && $0.targetPath == task.targetPath }
        recentTasks.insert(task, at: 0)
        recentTasks = Array(recentTasks.prefix(20))
        storage.saveRecentTasks(recentTasks)
    }

    private func scanSourceSummary() {
        let sourcePath = task.sourcePath
        let excludes = task.excludes
        sourceScanTask = Task.detached(priority: .utility) {
            let summary = SourceScanner.scan(path: sourcePath, excludes: excludes)
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.progress.apply(sourceSummary: summary)
            }
        }
    }

    private func startTargetProgressScanner() {
        let targetPath = task.resolvedTargetPath
        let sourcePath = task.sourcePath
        let excludes = task.excludes
        targetScanTask = Task { [weak self] in
            while !Task.isCancelled {
                let scanTask = Task.detached(priority: .utility) {
                    let heatmap = HeatmapScanner.scan(sourcePath: sourcePath, targetPath: targetPath, excludes: excludes)
                    let summary = HeatmapScanner.aggregateTargetSummary(from: heatmap)
                    return (summary: summary, heatmap: heatmap)
                }
                let result = await withTaskCancellationHandler {
                    await scanTask.value
                } onCancel: {
                    scanTask.cancel()
                }

                await MainActor.run { [weak self] in
                    guard let self, !Task.isCancelled else { return }
                    let now = Date()
                    self.heatmapItems = result.heatmap
                    Task {
                        await self.sampler.applyTargetSummary(result.summary, date: now)
                    }
                }

                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func startSnapshotPump() {
        snapshotTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let startedAt = await MainActor.run {
                    self.startedAt
                }
                let snapshot = await self.sampler.snapshot(startedAt: startedAt)
                await MainActor.run { [weak self] in
                    guard let self, !Task.isCancelled else { return }
                    self.applySnapshot(snapshot)
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func publishSnapshot() {
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.sampler.snapshot(startedAt: self.startedAt)
            await MainActor.run { [weak self] in
                self?.applySnapshot(snapshot)
            }
        }
    }

    private func applySnapshot(_ snapshot: TransferSnapshot) {
        if progress != snapshot.progress {
            progress = snapshot.progress
        }
        if outputText != snapshot.logText {
            outputText = snapshot.logText
        }
    }

    private func startLogMonitor(logFile: String) {
        logMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                let offset = await MainActor.run {
                    self?.lastLogReadOffset ?? 0
                }
                let chunk = await Task.detached(priority: .utility) {
                    Self.readLogChunk(path: logFile, offset: offset)
                }.value

                if let chunk {
                    await MainActor.run { [weak self] in
                        guard let self, !Task.isCancelled else { return }
                        self.lastLogReadOffset = chunk.nextOffset
                        if !chunk.text.isEmpty {
                            Task {
                                await self.sampler.ingestOutput(chunk.text)
                            }
                        }
                    }
                }

                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    nonisolated private static func readLogChunk(path: String, offset: UInt64) -> LogChunk? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
        let safeOffset = min(offset, fileSize)
        do {
            try handle.seek(toOffset: safeOffset)
            let data = try handle.readToEnd() ?? Data()
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            return LogChunk(text: text, nextOffset: fileSize)
        } catch {
            return nil
        }
    }

    private func updateNameFromPaths() {
        if !task.sourcePath.isEmpty {
            let name = URL(fileURLWithPath: task.sourcePath).lastPathComponent
            if !name.isEmpty {
                task.name = "\(name) Backup"
            }
        }
    }

    private func safeSuffix(_ name: String) -> String {
        let clean = name.lowercased().map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        return String(clean).split(separator: "-").joined(separator: "-")
    }

    private func commandPreview(rclonePath: String, logFile: String, dryRun: Bool) -> String {
        let args = runner.makeArguments(task: task, logFile: logFile, dryRun: dryRun)
        return "[Disk Ferry] \(rclonePath) \(args.map(shellQuote).joined(separator: " "))\n\n"
    }

    private func shellQuote(_ value: String) -> String {
        if value.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "\"'"))) == nil {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private struct LogChunk {
    var text: String
    var nextOffset: UInt64
}
