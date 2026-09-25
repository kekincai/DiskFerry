import AppKit
import Foundation
import UserNotifications

enum LocationRole: String, Identifiable {
    case source
    case target

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: "从"
        case .target: "复制到"
        }
    }

    var emptyTitle: String {
        switch self {
        case .source: "选择要复制的文件夹"
        case .target: "选择目标位置"
        }
    }
}

/// Reachability and volume details for one side of the route, gathered off the main thread.
struct LocationStatus: Equatable {
    var isChecking = false
    var exists = true
    var volume: VolumeDescriptor?
}

@MainActor
final class TransferStore: ObservableObject {
    // Route being edited / run.
    @Published var task: TransferTask {
        didSet { taskDidChange(from: oldValue) }
    }
    @Published private(set) var routes: [TransferTask] = []

    // Run state. Live numbers live in `monitor`, not here.
    @Published private(set) var status: TransferStatus = .idle
    @Published private(set) var headline = "拖入或选择源文件夹和目标位置。"
    @Published private(set) var failureDetails: [String] = []
    @Published private(set) var precheckItems: [PrecheckItem] = []
    /// rclone output of the last failed run, in memory only.
    @Published private(set) var failureLog: [String] = []
    @Published private(set) var startedAt: Date?
    @Published private(set) var finishedAt: Date?
    @Published private(set) var lastResult: RunRecord?
    @Published private(set) var isDryRunResult = false

    // Locations.
    @Published private(set) var sourceStatus = LocationStatus()
    @Published private(set) var targetStatus = LocationStatus()
    @Published private(set) var mountedVolumes: [VolumeDescriptor] = []
    @Published private(set) var inputErrors: [LocationRole: String] = [:]
    @Published private(set) var mountingRole: LocationRole?

    // Directory comparison (manual).
    @Published private(set) var heatmapItems: [FolderHeatmapItem] = []
    @Published private(set) var lastHeatmapRefresh: Date?
    @Published private(set) var isRefreshingHeatmap = false

    @Published var rclonePath: String {
        didSet { UserDefaults.standard.set(rclonePath, forKey: Self.rclonePathKey) }
    }

    let monitor = TransferMonitor()

    private static let rclonePathKey = "rclonePath"
    private let runner = RcloneRunner()
    private let storage = TaskStorage()
    private var isStopping = false
    private var pollTask: Task<Void, Never>?
    private var heatmapTask: Task<Void, Never>?
    private var locationTasks: [LocationRole: Task<Void, Never>] = [:]
    private var activeDestinationSnapshot: DestinationPathPolicy.Snapshot?
    private var copyProgress: TransferProgress?
    private var activity: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []

    init() {
        let saved = storage.loadRecentTasks()
        self.routes = saved
        self.task = saved.first(where: { !$0.isPinned }) ?? saved.first ?? .empty
        let storedPath = UserDefaults.standard.string(forKey: Self.rclonePathKey) ?? ""
        self.rclonePath = storedPath.isEmpty ? (RcloneLocator.locate(preferredPath: nil) ?? "") : storedPath
        if task.isReady {
            headline = "已载入上次的路线。"
        }
        applyLaunchArguments()
        refreshLocationStatus(.source)
        refreshLocationStatus(.target)
        refreshMountedVolumes()
        observeMounts()
    }

    /// `open -a DiskFerry --args -source /path -target /path [-autostart YES]`
    /// for scripts and Shortcuts. Read from the argument domain only, never persisted.
    private func applyLaunchArguments() {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        guard let source = arguments["source"] as? String, let target = arguments["target"] as? String else { return }
        var route = TransferTask.empty
        route.sourcePath = URL(fileURLWithPath: (source as NSString).expandingTildeInPath).standardizedFileURL.path
        route.targetPath = URL(fileURLWithPath: (target as NSString).expandingTildeInPath).standardizedFileURL.path
        if let existing = routes.first(where: { $0.hasSameRoute(as: route) }) {
            route = existing
        }
        task = route
        headline = "已从启动参数载入路线。"

        let autostart = (arguments["autostart"] as? String).map { ["1", "yes", "true"].contains($0.lowercased()) } ?? false
        if autostart {
            Task {
                // Let the location checks settle so `canStart` reflects reality.
                try? await Task.sleep(for: .milliseconds(500))
                startCopy()
            }
        }
    }

    // MARK: - State

    var canEdit: Bool {
        !status.isBusy
    }

    var canStart: Bool {
        canEdit && task.isReady && blockingIssue == nil
    }

    var canStop: Bool {
        status.isRunningProcess
    }

    var pinnedRoutes: [TransferTask] {
        routes.filter(\.isPinned)
    }

    var recentRoutes: [TransferTask] {
        routes.filter { !$0.isPinned }
    }

    /// Problems that can be detected instantly, before the full precheck runs.
    var blockingIssue: String? {
        guard task.isReady else { return nil }
        if !sourceStatus.isChecking, !sourceStatus.exists {
            return "源文件夹当前无法访问，磁盘或共享可能已断开。"
        }
        if !targetStatus.isChecking, !targetStatus.exists {
            return "目标位置当前无法访问，共享可能已断开。"
        }
        let source = URL(fileURLWithPath: task.sourcePath).standardizedFileURL.path
        let target = URL(fileURLWithPath: task.resolvedTargetPath).standardizedFileURL.path
        if source == target {
            return "源和目标是同一个文件夹。"
        }
        if PathInspector.isSameOrInside(target, source) {
            return "目标位于源文件夹内部，请换一个目标。"
        }
        return nil
    }

    func locationStatus(for role: LocationRole) -> LocationStatus {
        role == .source ? sourceStatus : targetStatus
    }

    func path(for role: LocationRole) -> String {
        role == .source ? task.sourcePath : task.targetPath
    }

    /// Distinct folders used in earlier routes, most recent first.
    func recentPaths(for role: LocationRole) -> [String] {
        var seen = Set<String>()
        return routes
            .map { role == .source ? $0.sourcePath : $0.targetPath }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(8)
            .map { $0 }
    }

    // MARK: - Editing the route

    func setPath(_ path: String, for role: LocationRole) {
        guard canEdit else { return }
        inputErrors[role] = nil
        switch role {
        case .source: task.sourcePath = path
        case .target: task.targetPath = path
        }
    }

    func choose(_ role: LocationRole) {
        guard canEdit else { return }
        let current = path(for: role)
        guard let path = FileDialogs.chooseFolder(
            startingAt: current,
            canCreateDirectories: role == .target,
            message: role == .source ? "选择要复制的文件夹" : "选择复制到哪里"
        ) else { return }
        setPath(path, for: role)
    }

    /// Accepts a pasted or typed path, including smb:// and \\server\share forms.
    /// Mounts the share first when needed.
    func submitInput(_ raw: String, for role: LocationRole) {
        guard canEdit else { return }
        inputErrors[role] = nil
        Task {
            let resolution = await Task.detached(priority: .userInitiated) {
                PathInput.resolve(raw)
            }.value

            switch resolution {
            case let .folder(path):
                setPath(path, for: role)
            case let .failure(message):
                inputErrors[role] = message
            case let .needsMount(url, _, _, _):
                await mountAndApply(url: url, raw: raw, role: role)
            }
        }
    }

    func pasteFromClipboard(into role: LocationRole) {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let first = urls.first {
            submitInput(first.path, for: role)
        } else if let text = pasteboard.string(forType: .string) {
            submitInput(text, for: role)
        } else {
            inputErrors[role] = "剪贴板里没有路径。可以在 Finder 中选中文件夹后按 ⌘C，或复制 smb:// 地址。"
        }
    }

    func handleDrop(_ urls: [URL], on role: LocationRole) -> Bool {
        guard canEdit, let url = urls.first else { return false }
        submitInput(url.path, for: role)
        return true
    }

    func swapLocations() {
        guard canEdit else { return }
        let source = task.sourcePath
        task.sourcePath = task.targetPath
        task.targetPath = source
        inputErrors = [:]
    }

    func setLayout(_ layout: TargetLayout) {
        guard canEdit else { return }
        task.targetLayout = layout
    }

    func setMode(_ mode: CopyMode) {
        guard canEdit else { return }
        task.applyMode(mode)
    }

    func clearLocation(_ role: LocationRole) {
        setPath("", for: role)
    }

    // MARK: - Routes

    func newRoute() {
        guard canEdit else { return }
        var fresh = TransferTask.empty
        // Keep the user's preferred options for the next route.
        fresh.applyMode(task.mode)
        if task.mode == .custom {
            fresh.transfers = task.transfers
            fresh.checkers = task.checkers
        }
        fresh.verifyAfterCopy = task.verifyAfterCopy
        fresh.checkFirst = task.checkFirst
        task = fresh
        resetRunState(message: "拖入或选择源文件夹和目标位置。")
    }

    func loadRoute(_ route: TransferTask) {
        guard canEdit else { return }
        task = route
        resetRunState(message: "已载入路线：\(route.displayName)")
        lastResult = route.lastRun
    }

    func runRoute(_ route: TransferTask) {
        loadRoute(route)
        start(dryRun: false)
    }

    func togglePin(_ route: TransferTask) {
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else { return }
        routes[index].isPinned.toggle()
        if task.id == route.id {
            task.isPinned = routes[index].isPinned
        }
        persistRoutes()
    }

    /// Saves the current draft as a pinned route without running it.
    func pinCurrentRoute() {
        guard task.isReady else { return }
        var route = upsertRoute(task)
        route.isPinned = true
        if let index = routes.firstIndex(where: { $0.id == route.id }) {
            routes[index] = route
        }
        task.id = route.id
        task.isPinned = true
        persistRoutes()
    }

    func rename(_ route: TransferTask, to name: String) {
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        routes[index].name = trimmed
        if task.id == route.id {
            task.name = trimmed
        }
        persistRoutes()
    }

    func delete(_ route: TransferTask) {
        routes.removeAll { $0.id == route.id }
        persistRoutes()
    }

    func isCurrent(_ route: TransferTask) -> Bool {
        route.id == task.id && route.hasSameRoute(as: task)
    }

    // MARK: - Running

    func startCopy() {
        start(dryRun: false)
    }

    func startDryRun() {
        start(dryRun: true)
    }

    func stop() {
        guard canStop else { return }
        isStopping = true
        status = .stopping
        headline = "正在停止…已经复制完的文件下次会自动跳过。"
        runner.stop()
    }

    /// Stops rclone synchronously-enough for app termination.
    func stopForTermination() {
        guard runner.isRunning else { return }
        isStopping = true
        runner.stop()
    }

    private func start(dryRun: Bool) {
        guard canStart else { return }

        status = .prechecking
        headline = "正在检查源、目标和 rclone…"
        failureDetails = []
        failureLog = []
        precheckItems = []
        lastResult = nil
        isDryRunResult = dryRun
        activeDestinationSnapshot = nil
        copyProgress = nil
        monitor.reset()

        let snapshotTask = task
        let preferredRclone = rclonePath
        Task {
            let preflight = await Task.detached(priority: .userInitiated) {
                Preflight.run(task: snapshotTask, rclonePath: preferredRclone)
            }.value

            precheckItems = preflight.items
            switch preflight.outcome {
            case let .blocked(message):
                status = .failed
                headline = message
                failureDetails = preflight.items.filter { $0.severity == .error }.map(\.message)
            case let .ready(rclone, snapshot, streamLocalCopies):
                if rclone != rclonePath { rclonePath = rclone }
                launch(dryRun: dryRun, rclone: rclone, snapshot: snapshot, streamLocalCopies: streamLocalCopies)
            }
        }
    }

    private func launch(dryRun: Bool, rclone: String, snapshot: DestinationPathPolicy.Snapshot, streamLocalCopies: Bool) {
        startedAt = Date()
        finishedAt = nil
        isStopping = false
        activeDestinationSnapshot = snapshot

        do {
            try DestinationPathPolicy.validate(snapshot)
            let remote = try RcloneRemoteControl.makeLocal()
            try runner.start(
                rclonePath: rclone,
                task: task,
                dryRun: dryRun,
                streamLocalCopies: streamLocalCopies,
                remote: remote,
                onFinish: { [weak self] exitCode, output in
                    self?.finishCopy(exitCode: exitCode, output: output, dryRun: dryRun)
                }
            )
            status = dryRun ? .dryRunning : .running
            headline = dryRun ? "正在预演：只比对，不写入任何文件。" : "正在复制…"
            startPolling(remote: remote, verifying: false)
            beginActivity()
            requestNotificationPermissionIfNeeded()
        } catch {
            status = .failed
            finishedAt = Date()
            headline = "无法启动 rclone：\(error.localizedDescription)"
        }
    }

    private func finishCopy(exitCode: Int32, output: String, dryRun: Bool) {
        stopPolling()
        finishedAt = Date()

        if isStopping {
            monitor.markStopped()
            complete(outcome: .cancelled, headline: "已中断。再次运行会从断点继续，已完成的文件自动跳过。")
            return
        }

        guard exitCode == 0 else {
            monitor.markStopped()
            recordFailure(output: output)
            complete(outcome: .failed, headline: "复制未完成：\(RcloneRunner.describe(exitCode: exitCode))")
            return
        }

        monitor.markSucceeded()
        if !dryRun, task.verifyAfterCopy {
            copyProgress = monitor.progress
            startVerification()
            return
        }

        let progress = monitor.progress
        let message: String
        if dryRun {
            message = progress.totalTransfers == 0
                ? "预演完成：目标已是最新，没有需要复制的文件。"
                : "预演完成：将复制 \(TransferFormatters.integer(progress.totalTransfers)) 个文件，共 \(TransferFormatters.byteCount(progress.totalBytes))。"
        } else {
            message = progress.totalTransfers == 0
                ? "完成：目标已是最新，没有需要复制的文件。"
                : "复制完成。"
        }
        complete(outcome: dryRun ? .dryRun : .completed, headline: message)
    }

    private func startVerification() {
        do {
            guard let activeDestinationSnapshot else {
                throw DestinationPathPolicy.PolicyError.emptyPath
            }
            try DestinationPathPolicy.validate(activeDestinationSnapshot)
        } catch {
            complete(outcome: .failed, headline: "复制完成，但目标路径安全检查失败：\(error.localizedDescription)")
            return
        }

        guard let rclone = RcloneLocator.locate(preferredPath: rclonePath) else {
            complete(outcome: .failed, headline: "复制完成，但找不到 rclone，无法校验。")
            return
        }

        do {
            let remote = try RcloneRemoteControl.makeLocal()
            try runner.startCheck(
                rclonePath: rclone,
                task: task,
                remote: remote,
                onFinish: { [weak self] exitCode, output in
                    self?.finishVerification(exitCode: exitCode, output: output)
                }
            )
            status = .verifying
            headline = "复制完成，正在按文件大小校验…"
            monitor.reset()
            startPolling(remote: remote, verifying: true)
        } catch {
            complete(outcome: .failed, headline: "复制完成，但无法启动校验：\(error.localizedDescription)")
        }
    }

    private func finishVerification(exitCode: Int32, output: String) {
        stopPolling()
        finishedAt = Date()

        if isStopping {
            monitor.markStopped()
            complete(outcome: .completed, headline: "校验已中断。复制本身已经完成。")
            return
        }

        if exitCode == 0 {
            monitor.markSucceeded()
            complete(outcome: .verified, headline: "复制完成，校验通过：所有文件大小一致。")
        } else {
            monitor.markStopped()
            recordFailure(output: output)
            complete(outcome: .failed, headline: "复制完成，但校验发现差异。")
        }
    }

    /// Common bookkeeping once a run is over.
    private func complete(outcome: RunOutcome, headline: String) {
        let endDate = finishedAt ?? Date()
        finishedAt = endDate
        let progress = copyProgress ?? monitor.progress

        switch outcome {
        case .completed, .verified, .dryRun: status = .completed
        case .cancelled: status = .cancelled
        case .failed: status = .failed
        }
        self.headline = headline

        let record = RunRecord(
            finishedAt: endDate,
            outcome: outcome,
            bytes: progress.bytes,
            files: progress.transfers,
            errors: progress.errors + (copyProgress != nil ? monitor.progress.errors : 0),
            duration: endDate.timeIntervalSince(startedAt ?? endDate)
        )
        lastResult = record

        if outcome != .dryRun {
            saveRun(record)
        }
        endActivity()
        monitor.clearDockBadge()
        notifyFinished(outcome: outcome, message: headline)
    }

    /// rclone's console output is kept in memory only and shown just for failed runs.
    private func recordFailure(output: String) {
        failureLog = RcloneOutput.displayLines(output)
        let errors = RcloneOutput.errorLines(output)
        failureDetails = errors.isEmpty ? Array(failureLog.suffix(3)) : errors
    }

    private func resetRunState(message: String) {
        status = .idle
        headline = message
        failureDetails = []
        failureLog = []
        precheckItems = []
        lastResult = nil
        startedAt = nil
        finishedAt = nil
        heatmapItems = []
        lastHeatmapRefresh = nil
        monitor.reset()
    }

    // MARK: - Live stats

    private func startPolling(remote: RcloneRemoteControl, verifying: Bool) {
        pollTask?.cancel()
        let client = RcloneStatsClient(remote: remote)
        let monitor = monitor
        let checkFirst = task.checkFirst
        pollTask = Task.detached(priority: .utility) {
            var meter = SpeedMeter()
            // Give rclone a moment to open its rc port.
            try? await Task.sleep(for: .milliseconds(300))
            while !Task.isCancelled {
                if let stats = try? await client.fetch() {
                    let speed = meter.add(bytes: stats.bytes, at: ProcessInfo.processInfo.systemUptime)
                    let progress = TransferProgress(
                        stats: stats,
                        verifying: verifying,
                        checkFirst: checkFirst,
                        currentSpeed: speed
                    )
                    guard !Task.isCancelled else { break }
                    await monitor.apply(progress)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Locations

    private func taskDidChange(from old: TransferTask) {
        if old.sourcePath != task.sourcePath {
            refreshLocationStatus(.source)
        }
        if old.targetPath != task.targetPath {
            refreshLocationStatus(.target)
        }
    }

    private func refreshLocationStatus(_ role: LocationRole) {
        let path = path(for: role)
        locationTasks[role]?.cancel()
        guard !path.isEmpty else {
            setStatus(LocationStatus(), for: role)
            return
        }
        var checking = locationStatus(for: role)
        checking.isChecking = true
        setStatus(checking, for: role)

        locationTasks[role] = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> LocationStatus in
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
                return LocationStatus(
                    isChecking: false,
                    exists: exists,
                    volume: exists ? VolumeCatalog.describe(path: path) : nil
                )
            }.value
            guard !Task.isCancelled, self.path(for: role) == path else { return }
            setStatus(result, for: role)
        }
    }

    private func setStatus(_ value: LocationStatus, for role: LocationRole) {
        switch role {
        case .source: if sourceStatus != value { sourceStatus = value }
        case .target: if targetStatus != value { targetStatus = value }
        }
    }

    func refreshMountedVolumes() {
        Task {
            let volumes = await Task.detached(priority: .utility) {
                VolumeCatalog.mountedVolumes()
            }.value
            if mountedVolumes != volumes { mountedVolumes = volumes }
        }
    }

    private func observeMounts() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.refreshMountedVolumes()
                    self.refreshLocationStatus(.source)
                    self.refreshLocationStatus(.target)
                }
            }
            workspaceObservers.append(observer)
        }
    }

    private func mountAndApply(url: URL, raw: String, role: LocationRole) async {
        mountingRole = role
        let result = await Task.detached(priority: .userInitiated) {
            PathInput.mount(url)
        }.value
        mountingRole = nil

        switch result {
        case .failure(let error):
            inputErrors[role] = error.message
        case .success:
            refreshMountedVolumes()
            let resolution = await Task.detached(priority: .userInitiated) {
                PathInput.resolve(raw)
            }.value
            switch resolution {
            case let .folder(path):
                setPath(path, for: role)
            case let .failure(message):
                inputErrors[role] = message
            case .needsMount:
                inputErrors[role] = "共享已连接，但没有找到对应的挂载位置。请用“选择…”手动选取。"
            }
        }
    }

    // MARK: - Finder helpers

    func revealInFinder(_ role: LocationRole) {
        let path = role == .source ? task.sourcePath : task.resolvedTargetPath
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: task.targetPath, isDirectory: true))
        }
    }

    func copyPathToClipboard(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    // MARK: - Directory comparison

    func refreshHeatmapOnce() {
        guard task.isReady else { return }
        let sourcePath = task.sourcePath
        let targetPath = task.resolvedTargetPath
        let excludes = task.excludes
        heatmapTask?.cancel()
        isRefreshingHeatmap = true
        heatmapTask = Task {
            let heatmap = await Task.detached(priority: .utility) {
                HeatmapScanner.scan(sourcePath: sourcePath, targetPath: targetPath, excludes: excludes, limit: 120)
            }.value
            guard !Task.isCancelled else { return }
            heatmapItems = heatmap
            lastHeatmapRefresh = Date()
            isRefreshingHeatmap = false
        }
    }

    // MARK: - Persistence

    private func saveRun(_ record: RunRecord) {
        var route = upsertRoute(task)
        route.lastRun = record
        if let index = routes.firstIndex(where: { $0.id == route.id }) {
            routes.remove(at: index)
        }
        routes.insert(route, at: 0)
        task.id = route.id
        task.lastRun = record
        persistRoutes()
    }

    /// Finds the saved route matching the draft (same paths) and refreshes its options,
    /// or creates a new one. Returns the stored route.
    @discardableResult
    private func upsertRoute(_ draft: TransferTask) -> TransferTask {
        if let index = routes.firstIndex(where: { $0.hasSameRoute(as: draft) }) {
            var route = draft
            route.id = routes[index].id
            route.isPinned = routes[index].isPinned
            route.lastRun = routes[index].lastRun
            if draft.name.isEmpty { route.name = routes[index].name }
            routes[index] = route
            return route
        }
        var route = draft
        route.id = UUID().uuidString
        route.createdAt = Date()
        route.isPinned = false
        route.lastRun = nil
        routes.insert(route, at: 0)
        return route
    }

    private func persistRoutes() {
        routes = TaskStorage.trimmed(routes)
        storage.saveRecentTasks(routes)
    }

    // MARK: - System integration

    private func beginActivity() {
        endActivity()
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Disk Ferry 正在复制文件"
        )
    }

    private func endActivity() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
    }

    private var notificationsAvailable: Bool {
        // UNUserNotificationCenter aborts when the binary runs outside an app bundle (swift run).
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    private func requestNotificationPermissionIfNeeded() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyFinished(outcome: RunOutcome, message: String) {
        guard notificationsAvailable, !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(task.displayName) · \(outcome.label)"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Precheck + destination snapshot, run off the main thread because both touch the
/// (possibly slow, possibly remote) destination.
private enum Preflight {
    enum Outcome {
        case blocked(String)
        case ready(rclone: String, snapshot: DestinationPathPolicy.Snapshot, streamLocalCopies: Bool)
    }

    struct Result {
        var items: [PrecheckItem]
        var outcome: Outcome
    }

    static func run(task: TransferTask, rclonePath: String) -> Result {
        let precheck = PrecheckService().run(task: task, rclonePath: rclonePath)
        guard !precheck.hasErrors else {
            return Result(items: precheck.items, outcome: .blocked("检查未通过，请先处理下面的问题。"))
        }
        guard let rclone = RcloneLocator.locate(preferredPath: rclonePath) else {
            return Result(items: precheck.items, outcome: .blocked("没有找到 rclone。请先安装：brew install rclone"))
        }
        do {
            let snapshot = try DestinationPathPolicy.prepare(task: task)
            try DestinationPathPolicy.validate(snapshot)
            return Result(
                items: precheck.items,
                outcome: .ready(
                    rclone: rclone,
                    snapshot: snapshot,
                    streamLocalCopies: RcloneCapabilities.supportsLocalNoClone(rclonePath: rclone)
                )
            )
        } catch {
            return Result(items: precheck.items, outcome: .blocked("目标路径安全检查失败：\(error.localizedDescription)"))
        }
    }
}
