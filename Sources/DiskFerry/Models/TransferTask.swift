import Foundation

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
    var createdAt: Date

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
            id: DateStamp.makeID(suffix: "task"),
            name: "Photos Backup",
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
            createdAt: Date()
        )
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
        case .custom:
            transfers = max(1, min(transfers, 4))
            checkers = max(1, min(checkers, 8))
        }
    }

    mutating func refreshLogDirectory() {
        guard !targetPath.isEmpty else {
            logDirectory = ""
            return
        }
        logDirectory = URL(fileURLWithPath: targetPath)
            .appendingPathComponent("_transfer_logs")
            .path
    }
}

enum CopyMode: String, Codable, CaseIterable, Identifiable {
    case conservative
    case normal
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conservative: "保守模式"
        case .normal: "普通模式"
        case .custom: "自定义"
        }
    }

    var detail: String {
        switch self {
        case .conservative: "transfers=1 checkers=2"
        case .normal: "transfers=2 checkers=4"
        case .custom: "手动设置，transfers 第一版限制最高 4"
        }
    }
}

enum VerifyMode: String, Codable {
    case sizeOnly = "size-only"
}
