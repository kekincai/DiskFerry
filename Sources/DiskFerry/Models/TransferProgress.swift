import Foundation

/// What the UI shows about the running rclone process. Built only from rclone's own
/// `core/stats` numbers, so it never guesses from partial directory scans.
struct TransferProgress: Equatable {
    enum Phase: Equatable {
        case waiting
        case comparing
        case transferring
        case verifying
        case finished
    }

    var phase: Phase = .waiting
    var bytes: Int64 = 0
    var totalBytes: Int64 = 0
    var transfers = 0
    var totalTransfers = 0
    var checks = 0
    var totalChecks = 0
    var listed = 0
    var errors = 0
    var lastError: String?
    var currentSpeed: Double = 0
    var averageSpeed: Double = 0
    var eta: TimeInterval?
    var elapsed: TimeInterval = 0
    var active: [ActiveTransfer] = []
    /// False while rclone may still discover more work (no `--check-first`).
    var totalsAreFinal = false

    static let empty = TransferProgress()

    var hasStarted: Bool {
        phase != .waiting || elapsed > 0
    }

    /// nil means indeterminate: rclone has not yet worked out how much there is to do.
    var fraction: Double? {
        switch phase {
        case .waiting, .comparing:
            return nil
        case .verifying:
            guard totalChecks > 0 else { return nil }
            return clamp(Double(checks) / Double(totalChecks))
        case .transferring:
            if totalBytes > 0 {
                return clamp(Double(bytes) / Double(totalBytes))
            }
            if totalTransfers > 0 {
                return clamp(Double(transfers) / Double(totalTransfers))
            }
            return nil
        case .finished:
            return 1
        }
    }

    var remainingFiles: Int {
        max(0, totalTransfers - transfers)
    }

    var remainingBytes: Int64 {
        max(0, totalBytes - bytes)
    }

    /// Files rclone compared and found already present on the destination.
    var skippedFiles: Int {
        checks
    }

    init() {}

    init(stats: RcloneCoreStats, verifying: Bool, checkFirst: Bool, currentSpeed: Double) {
        bytes = stats.bytes
        totalBytes = stats.totalBytes
        transfers = stats.transfers
        totalTransfers = stats.totalTransfers
        checks = stats.checks
        totalChecks = stats.totalChecks
        listed = stats.listed
        errors = stats.errors
        lastError = stats.lastError.flatMap { $0.isEmpty ? nil : $0 }
        // rclone's `speed` only counts time with an active transfer, which overstates
        // throughput on a link with gaps. Bytes over wall-clock time is what users expect.
        averageSpeed = stats.elapsedTime > 0 ? Double(stats.bytes) / stats.elapsedTime : stats.speed
        self.currentSpeed = currentSpeed
        eta = stats.eta.flatMap { $0 >= 0 ? $0 : nil }
        elapsed = stats.elapsedTime
        active = stats.transferring
            .map(ActiveTransfer.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        if verifying {
            phase = .verifying
            totalsAreFinal = true
        } else if stats.bytes > 0 || stats.transfers > 0 || !stats.transferring.isEmpty {
            phase = .transferring
            // With --check-first rclone finishes every comparison before the first byte moves.
            totalsAreFinal = checkFirst
        } else if stats.listed > 0 || stats.checks > 0 || stats.totalTransfers > 0 || stats.totalChecks > 0 {
            phase = .comparing
        } else {
            phase = .waiting
        }
    }

    /// rclone exits before a final poll can land, so a clean exit fills in the totals.
    mutating func markSucceeded() {
        if totalBytes > 0 {
            bytes = totalBytes
        }
        transfers = max(transfers, totalTransfers)
        if phase == .verifying {
            checks = max(checks, totalChecks)
        }
        active = []
        eta = 0
        currentSpeed = 0
        totalsAreFinal = true
        phase = .finished
    }

    mutating func markStopped() {
        active = []
        eta = nil
        currentSpeed = 0
    }

    private func clamp(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}

struct ActiveTransfer: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var size: Int64
    var bytes: Int64
    var speed: Double?

    var fraction: Double {
        guard size > 0 else { return 0 }
        return max(0, min(1, Double(bytes) / Double(size)))
    }

    init(name: String, size: Int64, bytes: Int64, speed: Double?) {
        self.name = name
        self.size = size
        self.bytes = bytes
        self.speed = speed
    }

    init(_ item: RcloneCoreStats.Item) {
        self.init(name: item.name, size: item.size, bytes: item.bytes, speed: item.speedAvg)
    }
}

/// Current throughput over a short sliding window. rclone's own `speed` is the average
/// since the transfer started, which hides stalls on a flaky SMB link.
struct SpeedMeter {
    private var samples: [(time: TimeInterval, bytes: Int64)] = []
    private let window: TimeInterval

    init(window: TimeInterval = 5) {
        self.window = window
    }

    mutating func add(bytes: Int64, at time: TimeInterval) -> Double {
        if let last = samples.last, bytes < last.bytes {
            samples.removeAll()
        }
        samples.append((time, bytes))
        while let first = samples.first, time - first.time > window, samples.count > 2 {
            samples.removeFirst()
        }
        guard let first = samples.first, let last = samples.last, last.time > first.time else {
            return 0
        }
        return Double(last.bytes - first.bytes) / (last.time - first.time)
    }
}

struct SourceSummary: Equatable {
    var fileCount: Int
    var folderCount: Int
    var totalBytes: Int64
}
