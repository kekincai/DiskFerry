import Foundation

struct TransferSnapshot: Equatable {
    var progress: TransferProgress
    var logText: String

    static let empty = TransferSnapshot(progress: .empty, logText: "")
}
