import Foundation

enum TransferFormatters {
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter
    }()

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func integer(_ value: Int?) -> String {
        guard let value else { return "-" }
        return value.formatted()
    }

    static func byteCount(_ value: Int64?) -> String {
        guard let value else { return "-" }
        return bytes.string(fromByteCount: value)
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "-" }
        return bytes.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "-" }
        let value = fraction * 100
        // Never show 100% until it really is complete.
        if value >= 99.95, fraction < 1 { return "99.9%" }
        return String(format: "%.1f%%", value)
    }

    static func duration(_ interval: TimeInterval?) -> String {
        guard let interval, interval.isFinite, interval >= 0 else { return "-" }
        let seconds = Int(interval.rounded())
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        if days > 0 { return "\(days)天 \(hours)小时" }
        if hours > 0 { return "\(hours)小时 \(minutes)分" }
        if minutes > 0 { return "\(minutes)分 \(remainder)秒" }
        return "\(remainder)秒"
    }

    static func relativeDate(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return "刚刚" }
        return relative.localizedString(for: date, relativeTo: now)
    }
}
