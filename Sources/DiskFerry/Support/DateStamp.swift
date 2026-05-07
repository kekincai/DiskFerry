import Foundation

enum DateStamp {
    static func makeLogStamp(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    static func makeID(suffix: String, date: Date = Date()) -> String {
        "\(makeLogStamp(date: date))-\(suffix)"
    }
}
