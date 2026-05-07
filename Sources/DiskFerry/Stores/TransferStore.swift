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

    private let runner = RcloneRunner()
    private let prechecker = PrecheckService()
    private let storage = TaskStorage()
    private var isStopping = false
    private var pendingOutput = ""
    private var outputFlushTask: Task<Void, Never>?
    private var sourceScanTask: Task<Void, Never>?
    private var targetScanTask: Task<Void, Never>?
    private var lastTargetScanBytes: Int64?
    private var lastTargetScanDate: Date?
    private let maxDisplayedLogCharacters = 80_000

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
        ![.running, .dryRunning, .prechecking, .stopping].contains(status)
    }

    var canStop: Bool {
        [.running, .dryRunning].contains(status)
    }

    func chooseSource() {
        guard let path = FileDialogs.chooseFolder() else { return }
        task.sourcePath = path
        updateNameFromPaths()
    }

    func chooseTarget() {
        guard let path = FileDialogs.chooseFolder() else { return }
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

    private func start(dryRun: Bool) {
        guard canStart else { return }

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

        let startDate = Date()
        let stamp = DateStamp.makeLogStamp(date: startDate)
        let logURL = URL(fileURLWithPath: task.logDirectory)
            .appendingPathComponent("\(stamp)\(dryRun ? "-dry-run" : "").log")
        let summaryURL = URL(fileURLWithPath: task.logDirectory)
            .appendingPathComponent("\(stamp)\(dryRun ? "-dry-run" : "").summary.json")

        do {
            try FileManager.default.createDirectory(atPath: task.logDirectory, withIntermediateDirectories: true)
        } catch {
            status = .failed
            lastMessage = "无法创建日志目录：\(error.localizedDescription)"
            return
        }

        currentLogFile = logURL.path
        currentSummaryFile = summaryURL.path
        startedAt = startDate
        finishedAt = nil
        isStopping = false
        pendingOutput = ""
        outputFlushTask?.cancel()
        sourceScanTask?.cancel()
        targetScanTask?.cancel()
        lastTargetScanBytes = nil
        lastTargetScanDate = nil
        outputText = ""
        progress = TransferProgress(isScanningSource: true)
        status = dryRun ? .dryRunning : .running
        lastMessage = dryRun ? "正在预演，不会写入目标目录。" : "正在复制。"

        appendOutput(commandPreview(rclonePath: resolvedRclone, logFile: logURL.path, dryRun: dryRun))
        scanSourceSummary()
        if !dryRun {
            startTargetProgressScanner()
        }

        do {
            try runner.start(
                rclonePath: resolvedRclone,
                task: task,
                logFile: logURL.path,
                dryRun: dryRun,
                onOutput: { [weak self] text in
                    self?.appendOutput(text)
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
        flushOutputNow()
        sourceScanTask?.cancel()
        targetScanTask?.cancel()

        if isStopping {
            status = .cancelled
            lastMessage = "任务已中断。稍后可以点击“再次运行”继续。"
            writeSummary(status: "cancelled", finishedAt: endDate, summaryURL: summaryURL)
            return
        }

        if exitCode == 0 {
            status = .completed
            if !dryRun {
                progress.markFinished()
            }
            lastMessage = dryRun ? "预演完成。" : "复制完成。"
            writeSummary(status: dryRun ? "dry-run-completed" : "completed", finishedAt: endDate, summaryURL: summaryURL)
            saveRecentTask()
        } else {
            status = .failed
            lastMessage = "rclone 退出码：\(exitCode)。请查看日志。"
            writeSummary(status: "failed", finishedAt: endDate, summaryURL: summaryURL)
            saveRecentTask()
        }
    }

    private func writeSummary(status: String, finishedAt: Date, summaryURL: URL) {
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
            appendOutput("\n[Disk Ferry] 无法写入 summary.json：\(error.localizedDescription)\n")
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

    private func appendOutput(_ text: String) {
        RcloneStatsParser.apply(text, to: &progress)
        pendingOutput.append(text)

        if pendingOutput.count > maxDisplayedLogCharacters {
            pendingOutput.removeFirst(pendingOutput.count - maxDisplayedLogCharacters)
        }

        guard outputFlushTask == nil else { return }
        outputFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            await MainActor.run {
                self?.flushOutputNow()
            }
        }
    }

    private func flushOutputNow() {
        outputFlushTask?.cancel()
        outputFlushTask = nil

        guard !pendingOutput.isEmpty else { return }
        outputText.append(pendingOutput)
        pendingOutput = ""

        if outputText.count > maxDisplayedLogCharacters {
            outputText.removeFirst(outputText.count - maxDisplayedLogCharacters)
        }
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
        targetScanTask = Task { [weak self] in
            while !Task.isCancelled {
                let summary = await Task.detached(priority: .utility) {
                    SourceScanner.scan(path: targetPath, excludes: ["_transfer_logs/**"])
                }.value

                await MainActor.run { [weak self] in
                    guard let self, !Task.isCancelled else { return }
                    let now = Date()
                    self.progress.applyTargetSummary(
                        summary,
                        previousBytes: self.lastTargetScanBytes,
                        previousDate: self.lastTargetScanDate,
                        date: now
                    )
                    self.lastTargetScanBytes = summary.totalBytes
                    self.lastTargetScanDate = now
                }

                try? await Task.sleep(for: .seconds(5))
            }
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
