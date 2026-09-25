import AppKit
import Foundation

/// Live numbers for the running transfer. Kept separate from `TransferStore` so the
/// once-per-second updates only re-render the progress views, not the whole window.
@MainActor
final class TransferMonitor: ObservableObject {
    @Published private(set) var progress: TransferProgress = .empty

    private var badgePercent: Int?

    func reset() {
        progress = .empty
        updateDockBadge()
    }

    func apply(_ next: TransferProgress) {
        guard next != progress else { return }
        progress = next
        updateDockBadge()
    }

    func markSucceeded() {
        var next = progress
        next.markSucceeded()
        progress = next
        clearDockBadge()
    }

    func markStopped() {
        var next = progress
        next.markStopped()
        progress = next
        clearDockBadge()
    }

    func clearDockBadge() {
        badgePercent = nil
        NSApp?.dockTile.badgeLabel = nil
    }

    private func updateDockBadge() {
        guard let fraction = progress.fraction, progress.phase != .finished else {
            if badgePercent != nil { clearDockBadge() }
            return
        }
        let percent = Int(fraction * 100)
        guard percent != badgePercent else { return }
        badgePercent = percent
        NSApp?.dockTile.badgeLabel = "\(percent)%"
    }
}
