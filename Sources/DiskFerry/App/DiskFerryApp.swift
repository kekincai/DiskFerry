import AppKit
import SwiftUI

@main
struct DiskFerryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TransferStore()

    var body: some Scene {
        Window("Disk Ferry", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 660)
                .onAppear { appDelegate.store = store }
        }
        .defaultSize(width: 1080, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建路线") { store.newRoute() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!store.canEdit)
            }

            CommandMenu("传输") {
                Button("选择源文件夹…") { store.choose(.source) }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(!store.canEdit)
                Button("选择目标位置…") { store.choose(.target) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(!store.canEdit)
                Button("交换源和目标") { store.swapLocations() }
                    .disabled(!store.canEdit)

                Divider()

                Button("开始复制") { store.startCopy() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!store.canStart)
                Button("预演（不写入）") { store.startDryRun() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!store.canStart)
                Button("停止") { store.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!store.canStop)

                Divider()

                Button("打开日志文件夹") { store.openLogDirectory() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(store.task.targetPath.isEmpty)
            }
        }

        Settings {
            SettingsView(store: store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: TransferStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.canStop else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "正在复制，确定要退出吗？"
        alert.informativeText = "退出会停止 rclone。已经复制完的文件会保留，下次运行同一路线会自动跳过它们。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "停止并退出")
        alert.addButton(withTitle: "继续复制")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }

        store.stopForTermination()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the window mid-copy must not kill the transfer.
        store?.canStop != true
    }
}
