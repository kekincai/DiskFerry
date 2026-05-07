import SwiftUI

struct ContentView: View {
    @ObservedObject var store: TransferStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            VStack(spacing: 0) {
                HeaderView(store: store)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HeatmapView(items: store.heatmapItems)
                        PathsView(store: store)
                        SettingsPanelView(store: store)
                        ActionBarView(store: store)
                        StatusPanelView(store: store)
                        PrecheckPanelView(items: store.precheckItems)
                        OutputLogView(text: store.outputText)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
