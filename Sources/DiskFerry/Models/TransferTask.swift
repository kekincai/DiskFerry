import Foundation

/// A saved source → destination route plus its copy options.
struct TransferTask: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var sourcePath: String
    var targetPath: String
    var logDirectory: String
    var engine: String
    var mode: CopyMode
    var transfers: Int
    var checkers: Int
    var retries: Int
    var lowLevelRetries: Int
    var excludes: [String]
    var verifyMode: VerifyMode
    var verifyAfterCopy: Bool
    var targetLayout: TargetLayout
    var checkFirst: Bool
    var isPinned: Bool
    var createdAt: Date
    var lastRun: RunRecord?

    static let defaultExcludes = [
        ".DS_Store",
        "._*",
        ".Spotlight-V100/**",
        ".Trashes/**",
        ".fseventsd/**",
        ".TemporaryItems/**"
    ]

    static var empty: TransferTask {
        TransferTask(
            id: UUID().uuidString,
            name: "",
            sourcePath: "",
            targetPath: "",
            logDirectory: "",
            engine: "rclone",
            mode: .conservative,
            transfers: 1,
            checkers: 2,
            retries: 10,
            lowLevelRetries: 20,
            excludes: TransferTask.defaultExcludes,
            verifyMode: .sizeOnly,
            verifyAfterCopy: false,
            targetLayout: .intoFolder,
            checkFirst: true,
            isPinned: false,
            createdAt: Date(),
            lastRun: nil
        )
    }

    init(
        id: String,
        name: String,
        sourcePath: String,
        targetPath: String,
        logDirectory: String,
        engine: String,
        mode: CopyMode,
        transfers: Int,
        checkers: Int,
        retries: Int,
        lowLevelRetries: Int,
        excludes: [String],
        verifyMode: VerifyMode,
        verifyAfterCopy: Bool,
        targetLayout: TargetLayout,
        checkFirst: Bool,
        isPinned: Bool,
        createdAt: Date,
        lastRun: RunRecord?
    ) {
        self.id = id
        self.name = name
        self.sourcePath = sourcePath
        self.targetPath = targetPath
        self.logDirectory = logDirectory
        self.engine = engine
        self.mode = mode
        self.transfers = transfers
        self.checkers = checkers
        self.retries = retries
        self.lowLevelRetries = lowLevelRetries
        self.excludes = excludes
        self.verifyMode = verifyMode
        self.verifyAfterCopy = verifyAfterCopy
        self.targetLayout = targetLayout
        self.checkFirst = checkFirst
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.lastRun = lastRun
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, sourcePath, targetPath, logDirectory, engine, mode, transfers, checkers
        case retries, lowLevelRetries, excludes, verifyMode, verifyAfterCopy, targetLayout
        case checkFirst, isPinned, createdAt, lastRun
    }

    /// Tolerates task files written by older versions, which had no layout, pin or run fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = TransferTask.empty
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? fallback.id
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath) ?? ""
        targetPath = try container.decodeIfPresent(String.self, forKey: .targetPath) ?? ""
        logDirectory = try container.decodeIfPresent(String.self, forKey: .logDirectory) ?? ""
        engine = try container.decodeIfPresent(String.self, forKey: .engine) ?? fallback.engine
        mode = try container.decodeIfPresent(CopyMode.self, forKey: .mode) ?? fallback.mode
        transfers = try container.decodeIfPresent(Int.self, forKey: .transfers) ?? fallback.transfers
        checkers = try container.decodeIfPresent(Int.self, forKey: .checkers) ?? fallback.checkers
        retries = try container.decodeIfPresent(Int.self, forKey: .retries) ?? fallback.retries
        lowLevelRetries = try container.decodeIfPresent(Int.self, forKey: .lowLevelRetries) ?? fallback.lowLevelRetries
        excludes = try container.decodeIfPresent([String].self, forKey: .excludes) ?? fallback.excludes
        verifyMode = try container.decodeIfPresent(VerifyMode.self, forKey: .verifyMode) ?? fallback.verifyMode
        verifyAfterCopy = try container.decodeIfPresent(Bool.self, forKey: .verifyAfterCopy) ?? false
        checkFirst = try container.decodeIfPresent(Bool.self, forKey: .checkFirst) ?? true
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastRun = try container.decodeIfPresent(RunRecord.self, forKey: .lastRun)

        if let layout = try container.decodeIfPresent(TargetLayout.self, forKey: .targetLayout) {
            targetLayout = layout
        } else {
            // Older versions only nested into a folder when the target was a mounted volume root.
            targetLayout = PathInspector.isVolumeRoot(targetPath) ? .intoFolder : .merge
        }
    }

    var sourceName: String {
        guard !sourcePath.isEmpty else { return "" }
        return URL(fileURLWithPath: sourcePath).lastPathComponent
    }

    var targetName: String {
        guard !targetPath.isEmpty else { return "" }
        return URL(fileURLWithPath: targetPath).lastPathComponent
    }

    var displayName: String {
        if !name.isEmpty { return name }
        switch (sourceName.isEmpty, targetName.isEmpty) {
        case (false, false): return "\(sourceName) → \(targetName)"
        case (false, true): return sourceName
        default: return "新路线"
        }
    }

    var isReady: Bool {
        !sourcePath.isEmpty && !targetPath.isEmpty
    }

    /// Where rclone actually writes. Pure string logic: this runs on every render,
    /// so it must never touch a (possibly stalled) network mount.
    var resolvedTargetPath: String {
        guard !sourcePath.isEmpty, !targetPath.isEmpty else { return targetPath }
        switch targetLayout {
        case .merge:
            return targetPath
        case .intoFolder:
            let folderName = sourceName
            guard !folderName.isEmpty, folderName != "/" else { return targetPath }
            return URL(fileURLWithPath: targetPath, isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true)
                .path
        }
    }

    mutating func applyMode(_ mode: CopyMode) {
        self.mode = mode
        switch mode {
        case .conservative:
            transfers = 1
            checkers = 2
        case .normal:
            transfers = 2
            checkers = 4
        case .fast:
            transfers = 4
            checkers = 8
        case .custom:
            transfers = max(1, min(transfers, 8))
            checkers = max(1, min(checkers, 16))
        }
    }

    var logDirectoryPath: String {
        let destination = resolvedTargetPath
        guard !destination.isEmpty else { return "" }
        return URL(fileURLWithPath: destination).appendingPathComponent("_transfer_logs").path
    }

    mutating func refreshLogDirectory() {
        let destination = resolvedTargetPath
        guard !destination.isEmpty else {
            logDirectory = ""
            return
        }
        logDirectory = URL(fileURLWithPath: destination)
            .appendingPathComponent("_transfer_logs")
            .path
    }

    /// Same route, ignoring run history and display name.
    func hasSameRoute(as other: TransferTask) -> Bool {
        sourcePath == other.sourcePath && targetPath == other.targetPath && targetLayout == other.targetLayout
    }
}

enum TargetLayout: String, Codable, CaseIterable, Identifiable {
    /// Finder-like: /target/<source folder name>/…
    case intoFolder
    /// rclone default: source contents go straight into /target/…
    case merge

    var id: String { rawValue }
}

enum CopyMode: String, Codable, CaseIterable, Identifiable {
    case conservative
    case normal
    case fast
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conservative: "稳妥"
        case .normal: "标准"
        case .fast: "快速"
        case .custom: "自定义"
        }
    }

    var detail: String {
        switch self {
        case .conservative: "1 个并行传输 · 适合机械硬盘、弱 Wi-Fi"
        case .normal: "2 个并行传输 · 大多数内网环境"
        case .fast: "4 个并行传输 · 千兆有线 + SSD，适合大量小文件"
        case .custom: "手动设置并行数"
        }
    }
}

enum VerifyMode: String, Codable {
    case sizeOnly = "size-only"
}

/// Outcome of the last run of a route, shown in the sidebar.
struct RunRecord: Codable, Equatable {
    var finishedAt: Date
    var outcome: RunOutcome
    var bytes: Int64
    var files: Int
    var errors: Int
    var duration: TimeInterval
}

enum RunOutcome: String, Codable {
    case completed
    case verified
    case dryRun
    case cancelled
    case failed

    var label: String {
        switch self {
        case .completed: "已完成"
        case .verified: "已完成并校验"
        case .dryRun: "预演完成"
        case .cancelled: "已中断"
        case .failed: "失败"
        }
    }

    var isSuccess: Bool {
        self == .completed || self == .verified || self == .dryRun
    }
}
