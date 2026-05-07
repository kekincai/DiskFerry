import AppKit
import SwiftUI

@main
struct DiskFerryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TransferStore()

    var body: some Scene {
        WindowGroup("Disk Ferry", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 980, minHeight: 700)
                .preferredColorScheme(.light)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("预检查") {
                    store.precheck()
                }
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(!store.canStart)

                Button("预演 Dry Run") {
                    store.startDryRun()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!store.canStart)

                Button("开始复制") {
                    store.startCopy()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!store.canStart)

                Button("停止") {
                    store.stop()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!store.canStop)
            }

            CommandGroup(after: .appSettings) {
                Button("打开日志文件夹") {
                    store.openLogDirectory()
                }
                .disabled(store.task.targetPath.isEmpty)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
