import SwiftUI

struct HeaderView: View {
    @ObservedObject var store: TransferStore

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "ferry")
                .font(.system(size: 34))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text("Disk Ferry")
                    .font(.title2.weight(.semibold))
                Text("低缓存、大规模、安全迁移控制器")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusBadge(status: store.status)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct StatusBadge: View {
    var status: TransferStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.color)
                .frame(width: 9, height: 9)
            Text(status.label)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
    }
}
