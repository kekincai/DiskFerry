import SwiftUI

struct RoutesSidebar: View {
    @ObservedObject var store: TransferStore
    @State private var renaming: TransferTask?
    @State private var renameText = ""

    var body: some View {
        List(selection: selection) {
            if !store.pinnedRoutes.isEmpty {
                Section("收藏路线") {
                    ForEach(store.pinnedRoutes) { route in
                        row(route)
                    }
                }
            }

            Section("最近") {
                if store.recentRoutes.isEmpty {
                    Text("复制过的路线会出现在这里。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(store.recentRoutes) { route in
                    row(route)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button {
                store.newRoute()
            } label: {
                Label("新建路线", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .disabled(!store.canEdit)
            .keyboardShortcut("n", modifiers: .command)
        }
        .alert("重命名路线", isPresented: isRenaming) {
            TextField("名称", text: $renameText)
            Button("保存") {
                if let renaming { store.rename(renaming, to: renameText) }
                renaming = nil
            }
            Button("取消", role: .cancel) { renaming = nil }
        } message: {
            Text("留空则自动使用“源 → 目标”作为名称。")
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { store.routes.first(where: { store.isCurrent($0) })?.id },
            set: { id in
                guard let id, let route = store.routes.first(where: { $0.id == id }) else { return }
                if !store.isCurrent(route) { store.loadRoute(route) }
            }
        )
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func row(_ route: TransferTask) -> some View {
        RouteRow(route: route)
            .tag(route.id)
            .contextMenu {
                Button("开始复制") { store.runRoute(route) }
                    .disabled(!store.canEdit)
                Divider()
                Button(route.isPinned ? "取消收藏" : "收藏") { store.togglePin(route) }
                Button("重命名…") {
                    renameText = route.name
                    renaming = route
                }
                Button("在 Finder 中显示目标") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: route.resolvedTargetPath, isDirectory: true))
                }
                Divider()
                Button("从列表中移除", role: .destructive) { store.delete(route) }
            }
    }
}

private struct RouteRow: View {
    var route: TransferTask

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if route.isPinned {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Text(route.displayName)
                    .lineLimit(1)
            }

            Text(PathInspector.abbreviated(route.resolvedTargetPath))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)

            if let run = route.lastRun {
                HStack(spacing: 5) {
                    StatusDot(color: run.outcome.color, size: 6)
                    Text(lastRunText(run))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
        .help("\(route.sourcePath)\n→ \(route.resolvedTargetPath)")
    }

    private func lastRunText(_ run: RunRecord) -> String {
        var parts = [TransferFormatters.relativeDate(run.finishedAt), run.outcome.label]
        if run.bytes > 0 {
            parts.append(TransferFormatters.byteCount(run.bytes))
        }
        return parts.joined(separator: " · ")
    }
}
