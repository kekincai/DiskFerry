import Foundation

/// Written next to the rclone log as `<stamp>.summary.json`.
struct TransferSummary: Codable {
    var taskName: String
    var source: String
    var target: String
    var startedAt: Date
    var finishedAt: Date
    var status: String
    var engine: String
    var transfers: Int
    var checkers: Int
    var logFile: String
    var bytesTransferred: Int64
    var filesTransferred: Int
    var filesSkipped: Int
    var errors: Int
}
