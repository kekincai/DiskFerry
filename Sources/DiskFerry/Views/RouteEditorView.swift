import SwiftUI

/// Source → destination, plus a plain-language preview of where files will land.
struct RouteEditorView: View {
    @ObservedObject var store: TransferStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                LocationCard(store: store, role: .source)

                Button {
                    store.swapLocations()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor)))
                .help("交换源和目标")
                .disabled(!store.canEdit || (store.task.sourcePath.isEmpty && store.task.targetPath.isEmpty))

                LocationCard(store: store, role: .target)
            }
            .fixedSize(horizontal: false, vertical: true)

            if store.task.isReady {
                DestinationPreview(store: store)
            }
        }
    }
}

private struct DestinationPreview: View {
    @ObservedObject var store: TransferStore

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.secondary)
            Text("写入到")
                .foregroundStyle(.secondary)
            Text(PathInspector.abbreviated(store.task.resolvedTargetPath))
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(store.task.resolvedTargetPath)

            Spacer(minLength: 8)

            Picker("", selection: Binding(
                get: { store.task.targetLayout },
                set: { store.setLayout($0) }
            )) {
                Text("放进“\(store.task.sourceName)”文件夹").tag(TargetLayout.intoFolder)
                Text("直接合并到目标").tag(TargetLayout.merge)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .disabled(!store.canEdit)
            .help("放进同名文件夹：和 Finder 拖拽一样。\n直接合并：源文件夹里的内容直接写进目标文件夹。")
        }
        .font(.callout)

        if let issue = store.blockingIssue {
            Label(issue, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }
}

/// One side of the route. Accepts folders dragged from Finder, ⌘C-copied folders,
/// typed or pasted paths, `smb://server/share` and `\\server\share`.
struct LocationCard: View {
    @ObservedObject var store: TransferStore
    var role: LocationRole

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isDropTargeted = false
    @FocusState private var fieldFocused: Bool

    private var path: String { store.path(for: role) }
    private var status: LocationStatus { store.locationStatus(for: role) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(role.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                locationMenu
            }

            Group {
                if isEditing {
                    editor
                } else if path.isEmpty {
                    emptyState
                } else {
                    filledState
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if store.mountingRole == role {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("正在连接服务器，如需登录请在弹出的窗口中输入账号…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let error = store.inputErrors[role] {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if !isEditing {
                HStack(spacing: 8) {
                    Button("选择…") { store.choose(role) }
                    Button("粘贴") { store.pasteFromClipboard(into: role) }
                        .help("粘贴在 Finder 中 ⌘C 复制的文件夹，或 smb:// / \\\\服务器\\共享 地址")
                    Button("输入地址…") { beginEditing(prefill: path) }
                }
                .controlSize(.small)
                .disabled(!store.canEdit)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor).opacity(path.isEmpty ? 1 : 0.6),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: path.isEmpty && !isDropTargeted ? [5, 4] : [])
                )
        }
        .dropDestination(for: URL.self) { urls, _ in
            store.handleDrop(urls, on: role)
        } isTargeted: { targeted in
            isDropTargeted = targeted && store.canEdit
        }
    }

    // MARK: States

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: role == .source ? "folder.badge.plus" : "externaldrive.badge.plus")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 3) {
                Text(role.emptyTitle)
                    .font(.headline)
                Text("把文件夹拖到这里，或粘贴路径 / smb:// 地址")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var filledState: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.volume?.symbolName ?? "folder")
                .font(.system(size: 24))
                .foregroundStyle(status.exists ? Color.accentColor : Color.red)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(PathInspector.abbreviated(path))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(path)
                volumeLine
            }
        }
    }

    @ViewBuilder
    private var volumeLine: some View {
        if status.isChecking {
            Text("正在读取磁盘信息…")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else if !status.exists {
            Label("无法访问：磁盘或共享可能已断开", systemImage: "bolt.horizontal.circle")
                .font(.caption)
                .foregroundStyle(.red)
        } else if let volume = status.volume {
            let parts = [
                volume.networkLocation ?? volume.name,
                volume.availableBytes.map { "可用 \(TransferFormatters.byteCount($0))" }
            ].compactMap { $0 }
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("/Volumes/… · smb://服务器/共享/文件夹 · \\\\服务器\\共享", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($fieldFocused)
                .onSubmit(commitEditing)
                .onExitCommand { isEditing = false }
            HStack {
                Text("回车确认 · Esc 取消。未连接的共享会自动连接。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { isEditing = false }
                Button("确定", action: commitEditing)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .controlSize(.small)
        }
    }

    // MARK: Menu

    private var locationMenu: some View {
        Menu {
            let volumes = store.mountedVolumes.filter { $0.kind != .internalDisk || $0.mountPoint != "/" }
            if !volumes.isEmpty {
                Section("已连接的磁盘和共享") {
                    ForEach(volumes) { volume in
                        Button {
                            store.setPath(volume.mountPoint, for: role)
                        } label: {
                            Label(volumeMenuTitle(volume), systemImage: volume.symbolName)
                        }
                    }
                }
            }

            let recents = store.recentPaths(for: role)
            if !recents.isEmpty {
                Section("最近使用") {
                    ForEach(recents, id: \.self) { recent in
                        Button(PathInspector.abbreviated(recent)) {
                            store.setPath(recent, for: role)
                        }
                    }
                }
            }

            Section {
                Button("连接服务器…") { beginEditing(prefill: "smb://") }
                Button("刷新磁盘列表") { store.refreshMountedVolumes() }
            }

            if !path.isEmpty {
                Section {
                    Button("在 Finder 中打开") { store.revealInFinder(role) }
                    Button("拷贝路径") { store.copyPathToClipboard(path) }
                    Button("清除") { store.clearLocation(role) }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!store.canEdit)
        .help("常用位置、最近使用、连接服务器")
    }

    private func volumeMenuTitle(_ volume: VolumeDescriptor) -> String {
        var title = volume.name
        if let location = volume.networkLocation {
            title += "  (\(location))"
        }
        if let available = volume.availableBytes {
            title += "  · 可用 \(TransferFormatters.byteCount(available))"
        }
        return title
    }

    private func beginEditing(prefill: String) {
        draft = prefill
        isEditing = true
        DispatchQueue.main.async { fieldFocused = true }
    }

    private func commitEditing() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isEditing = false
        store.submitInput(value, for: role)
    }
}
