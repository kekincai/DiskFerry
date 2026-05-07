import SwiftUI

struct ActionBarView: View {
    @ObservedObject var store: TransferStore

    var body: some View {
        HStack(spacing: 10) {
            Button {
                store.precheck()
            } label: {
                Label("预检查", systemImage: "checklist")
            }
            .disabled(!store.canStart)

            Button {
                store.startDryRun()
            } label: {
                Label("预演 Dry Run", systemImage: "play.circle")
            }
            .disabled(!store.canStart)

            Button {
                store.startCopy()
            } label: {
                Label("开始复制", systemImage: "arrow.right.doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canStart)

            Button(role: .destructive) {
                store.stop()
            } label: {
                Label("停止", systemImage: "stop.circle")
            }
            .disabled(!store.canStop)

            Divider()
                .frame(height: 22)

            Button {
                store.rerunLastTask()
            } label: {
                Label("再次运行", systemImage: "arrow.clockwise")
            }
            .disabled(!store.canStart || store.task.sourcePath.isEmpty || store.task.targetPath.isEmpty)

            Button {
                store.openLogDirectory()
            } label: {
                Label("打开日志文件夹", systemImage: "folder")
            }
            .disabled(store.task.targetPath.isEmpty)

            Spacer()
        }
    }
}
