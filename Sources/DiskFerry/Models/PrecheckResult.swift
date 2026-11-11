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
    /// The rclone binary the check found, if any.
    var rclonePath: String?
    /// The prepared, validated destination for a real copy. Always nil for dry runs,
    /// which do not create anything.
    var destination: DestinationPathPolicy.Snapshot?

    var hasErrors: Bool {
        items.contains { $0.severity == .error }
    }
}
