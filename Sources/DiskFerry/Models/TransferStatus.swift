import SwiftUI

enum TransferStatus: String {
    case idle
    case prechecking
    case dryRunning
    case running
    case stopping
    case cancelled
    case completed
    case failed

    var label: String {
        switch self {
        case .idle: "等待中"
        case .prechecking: "预检查中"
        case .dryRunning: "预演中"
        case .running: "复制中"
        case .stopping: "正在停止"
        case .cancelled: "已取消"
        case .completed: "已完成"
        case .failed: "失败"
        }
    }

    var color: Color {
        switch self {
        case .idle: .secondary
        case .prechecking, .dryRunning: .blue
        case .running: .green
        case .stopping: .orange
        case .cancelled: .orange
        case .completed: .green
        case .failed: .red
        }
    }
}
