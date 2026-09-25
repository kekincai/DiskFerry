import SwiftUI

enum TransferStatus: String {
    case idle
    case prechecking
    case dryRunning
    case running
    case verifying
    case stopping
    case cancelled
    case completed
    case failed

    var label: String {
        switch self {
        case .idle: "就绪"
        case .prechecking: "检查中"
        case .dryRunning: "预演中"
        case .running: "复制中"
        case .verifying: "校验中"
        case .stopping: "正在停止"
        case .cancelled: "已中断"
        case .completed: "已完成"
        case .failed: "失败"
        }
    }

    var color: Color {
        switch self {
        case .idle: .secondary
        case .prechecking, .dryRunning, .verifying: .blue
        case .running: .accentColor
        case .stopping, .cancelled: .orange
        case .completed: .green
        case .failed: .red
        }
    }

    var isBusy: Bool {
        [.prechecking, .dryRunning, .running, .verifying, .stopping].contains(self)
    }

    var isRunningProcess: Bool {
        [.dryRunning, .running, .verifying].contains(self)
    }
}
