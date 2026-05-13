import Foundation

actor TransferSampler {
    private var progress: TransferProgress = .empty
    private var logText = ""
    private var liveLogPreviewEnabled = false
    private var lastTargetScanBytes: Int64?
    private var lastTargetScanDate: Date?
    private let maxDisplayedLogCharacters = 80_000

    func reset(liveLogPreviewEnabled: Bool) {
        progress = .empty
        logText = ""
        self.liveLogPreviewEnabled = liveLogPreviewEnabled
        lastTargetScanBytes = nil
        lastTargetScanDate = nil
    }

    func ingestOutput(_ text: String) {
        RcloneStatsParser.apply(text, to: &progress)

        guard liveLogPreviewEnabled else { return }
        logText.append(text)
        if logText.count > maxDisplayedLogCharacters {
            logText.removeFirst(logText.count - maxDisplayedLogCharacters)
        }
    }

    func applyTargetSummary(_ summary: SourceSummary, date: Date) {
        progress.applyTargetSummary(
            summary,
            previousBytes: lastTargetScanBytes,
            previousDate: lastTargetScanDate,
            date: date
        )
        lastTargetScanBytes = summary.totalBytes
        lastTargetScanDate = date
    }

    func markFinished() {
        progress.markFinished()
    }

    func snapshot(startedAt: Date?, now: Date = Date()) -> TransferSnapshot {
        var current = progress
        current.updateElapsedEstimate(startedAt: startedAt, now: now)
        return TransferSnapshot(progress: current, logText: logText)
    }
}
