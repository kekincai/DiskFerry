import Foundation

struct TransferProgress: Equatable {
    var totalFiles: Int?
    var totalFolders: Int?
    var totalBytes: Int64?
    var transferredFiles: Int?
    var transferredBytes: Int64?
    var percent: Double?
    var speedText: String?
    var etaText: String?
    var isScanningSource: Bool = false
    var progressSource: ProgressSource = .waiting

    static let empty = TransferProgress()

    var remainingFiles: Int? {
        guard let totalFiles else { return nil }
        return max(0, totalFiles - (transferredFiles ?? 0))
    }

    var remainingFoldersEstimate: Int? {
        guard let totalFolders else { return nil }
        if let copiedFolders {
            return max(0, totalFolders - copiedFolders)
        }
        guard let percent else { return totalFolders }
        let remainingRatio = max(0, min(1, 1 - percent / 100))
        return max(0, Int((Double(totalFolders) * remainingRatio).rounded()))
    }

    var copiedFolders: Int?

    var fraction: Double {
        if let percent {
            return max(0, min(1, percent / 100))
        }
        guard let transferredBytes, let totalBytes, totalBytes > 0 else { return 0 }
        return max(0, min(1, Double(transferredBytes) / Double(totalBytes)))
    }

    mutating func apply(sourceSummary: SourceSummary) {
        totalFiles = sourceSummary.fileCount
        totalFolders = sourceSummary.folderCount
        totalBytes = sourceSummary.totalBytes
        isScanningSource = false
        progressSource = .sourceScanned
    }

    mutating func applyTargetSummary(_ summary: SourceSummary, previousBytes: Int64?, previousDate: Date?, date: Date) {
        copiedFolders = summary.folderCount
        transferredFiles = summary.fileCount
        transferredBytes = summary.totalBytes

        if let totalBytes, totalBytes > 0 {
            percent = min(100, Double(summary.totalBytes) / Double(totalBytes) * 100)
        } else if let totalFiles, totalFiles > 0 {
            percent = min(100, Double(summary.fileCount) / Double(totalFiles) * 100)
        }

        if let previousBytes, let previousDate {
            let seconds = date.timeIntervalSince(previousDate)
            if seconds > 0 {
                let delta = max(0, summary.totalBytes - previousBytes)
                let bytesPerSecond = Double(delta) / seconds
                if bytesPerSecond > 0 {
                    speedText = TransferFormatters.bytes.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
                    if let totalBytes {
                        let remainingBytes = max(0, totalBytes - summary.totalBytes)
                        etaText = formatDuration(TimeInterval(Double(remainingBytes) / bytesPerSecond))
                    }
                }
            }
        }

        progressSource = .targetScan
    }

    mutating func updateElapsedEstimate(startedAt: Date?, now: Date) {
        guard let startedAt,
              let transferredBytes,
              let totalBytes,
              transferredBytes > 0,
              totalBytes > transferredBytes else {
            return
        }

        let elapsed = now.timeIntervalSince(startedAt)
        guard elapsed > 0 else { return }

        let averageBytesPerSecond = Double(transferredBytes) / elapsed
        guard averageBytesPerSecond > 0 else { return }

        if speedText == nil || progressSource == .targetScan || progressSource == .sourceScanned {
            speedText = TransferFormatters.bytes.string(fromByteCount: Int64(averageBytesPerSecond)) + "/s"
        }

        let remainingBytes = totalBytes - transferredBytes
        etaText = formatDuration(TimeInterval(Double(remainingBytes) / averageBytesPerSecond))
    }

    mutating func markFinished() {
        if let totalFiles {
            transferredFiles = totalFiles
        }
        if let totalBytes {
            transferredBytes = totalBytes
        }
        if let totalFolders {
            copiedFolders = totalFolders
        }
        percent = 100
        etaText = "0s"
        progressSource = .completed
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        guard duration.isFinite else { return "-" }
        let seconds = max(0, Int(duration.rounded()))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }
}

struct SourceSummary: Equatable {
    var fileCount: Int
    var folderCount: Int
    var totalBytes: Int64
}

enum ProgressSource: Equatable {
    case waiting
    case sourceScanned
    case rcloneOutput
    case targetScan
    case completed
}
