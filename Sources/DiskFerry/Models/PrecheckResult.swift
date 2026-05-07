import Foundation

enum CheckSeverity {
    case ok
    case warning
    case error
}

struct PrecheckItem: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var severity: CheckSeverity
}

struct PrecheckResult {
    var items: [PrecheckItem]

    var hasErrors: Bool {
        items.contains { $0.severity == .error }
    }

    var summaryText: String {
        if hasErrors {
            return "预检查未通过"
        }
        if items.contains(where: { $0.severity == .warning }) {
            return "预检查通过，有提醒"
        }
        return "预检查通过"
    }
}
