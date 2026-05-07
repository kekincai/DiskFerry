import Foundation

enum TransferFormatters {
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
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

    static func percent(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.1f%%", value)
    }
}
