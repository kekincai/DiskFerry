import SwiftUI

struct ContentView: View {
    @ObservedObject var store: TransferStore

    var body: some View {
        NavigationSplitView {
            RoutesSidebar(store: store)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            VStack(alignment: .leading, spacing: 14) {
                RouteEditorView(store: store)
                OptionsBar(store: store)
                RunPanelView(store: store, monitor: store.monitor)
                DetailTabsView(store: store, monitor: store.monitor)
                    .frame(maxHeight: .infinity)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(store.task.displayName)
            .navigationSubtitle(store.status == .idle ? "" : store.status.label)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    let isPinned = store.isCurrentRoutePinned
                    Button {
                        if isPinned, let route = store.currentRoute {
                            store.togglePin(route)
                        } else {
                            store.pinCurrentRoute()
                        }
                    } label: {
                        Label(isPinned ? "取消收藏" : "收藏路线", systemImage: isPinned ? "star.fill" : "star")
                    }
                    .help(isPinned ? "从收藏中移除" : "收藏这条路线，下次一键复制")
                    .disabled(!store.task.isReady)
                }
            }
        }
    }
}
