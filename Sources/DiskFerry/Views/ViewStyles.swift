import SwiftUI

extension View {
    func cardStyle(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6))
            }
    }
}

struct StatusDot: View {
    var color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

extension RunOutcome {
    var color: Color {
        switch self {
        case .completed, .verified: .green
        case .dryRun: .blue
        case .cancelled: .orange
        case .failed: .red
        }
    }

    var symbolName: String {
        switch self {
        case .completed, .verified: "checkmark.circle.fill"
        case .dryRun: "eye.circle.fill"
        case .cancelled: "pause.circle.fill"
        case .failed: "exclamationmark.octagon.fill"
        }
    }
}
