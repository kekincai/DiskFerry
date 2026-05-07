import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: TransferStore

    var body: some View {
        List {
            Section("任务") {
                Button {
                    store.loadRecentTask(.empty)
                } label: {
                    Label("新任务", systemImage: "plus")
                }

                ForEach(store.recentTasks) { task in
                    Button {
                        store.loadRecentTask(task)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "externaldrive")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.name)
                                    .lineLimit(1)
                                Text(URL(fileURLWithPath: task.targetPath).lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("安全边界") {
                Label("不生成缩略图", systemImage: "photo.badge.exclamationmark")
                Label("不读取 EXIF", systemImage: "doc.text.magnifyingglass")
                Label("日志写入目标盘", systemImage: "list.bullet.rectangle")
            }
            .foregroundStyle(.secondary)
        }
        .listStyle(.sidebar)
    }
}
