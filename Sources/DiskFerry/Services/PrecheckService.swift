import Foundation

struct PrecheckService {
    func run(task: TransferTask, rclonePath: String?) -> PrecheckResult {
        var items: [PrecheckItem] = []

        if let resolvedRclone = RcloneLocator.locate(preferredPath: rclonePath) {
            items.append(.init(title: "rclone", message: "已找到：\(resolvedRclone)", severity: .ok))
        } else {
            items.append(.init(
                title: "rclone",
                message: "没有找到 rclone。请确认已安装：brew install rclone",
                severity: .error
            ))
        }

        items.append(contentsOf: checkDirectory(
            title: "源目录",
            path: task.sourcePath,
            mustBeReadable: true,
            mustBeWritable: false,
            missingMessage: "源目录不存在，可能是外置磁盘已经断开。"
        ))

        items.append(contentsOf: checkDirectory(
            title: "目标目录",
            path: task.targetPath,
            mustBeReadable: false,
            mustBeWritable: true,
            performWriteProbe: false,
            missingMessage: "目标目录不存在，可能是 SMB 连接已经断开。"
        ))

        let resolvedTargetPath = task.resolvedTargetPath
        var safeLogDirectory: String?
        if !task.targetPath.isEmpty {
            do {
                let destination = try DestinationPathPolicy.prepare(task: task)
                safeLogDirectory = destination.logDirectory.path
                try DestinationPathPolicy.validate(destination)
                items.append(contentsOf: writeProbe(path: destination.selectedRoot.path))
                try DestinationPathPolicy.validate(destination)
                if resolvedTargetPath != task.targetPath {
                    items.append(.init(
                        title: "实际写入位置",
                        message: "将复制到：\(resolvedTargetPath)",
                        severity: .ok
                    ))
                }
                items.append(.init(
                    title: "目标路径安全检查",
                    message: "目标和日志目录位于所选目录内，且不包含符号链接。",
                    severity: .ok
                ))
            } catch {
                items.append(.init(
                    title: "目标路径安全检查",
                    message: error.localizedDescription,
                    severity: .error
                ))
            }
        }

        if !task.sourcePath.isEmpty,
           !resolvedTargetPath.isEmpty,
           URL(fileURLWithPath: task.sourcePath).standardizedFileURL == URL(fileURLWithPath: resolvedTargetPath).standardizedFileURL {
            items.append(.init(title: "路径检查", message: "源目录和目标目录不能相同。", severity: .error))
        }

        if !task.targetPath.isEmpty, task.targetPath.hasPrefix("/Volumes/") {
            items.append(.init(
                title: "SMB / 外置盘提醒",
                message: "目标位于 /Volumes/。如果复制中断，请先确认挂载没有断开。",
                severity: .warning
            ))
        }

        if let safeLogDirectory {
            items.append(.init(title: "日志目录", message: "可创建或已存在：\(safeLogDirectory)", severity: .ok))
        }

        return PrecheckResult(items: items)
    }

    private func checkDirectory(
        title: String,
        path: String,
        mustBeReadable: Bool,
        mustBeWritable: Bool,
        performWriteProbe: Bool = true,
        missingMessage: String
    ) -> [PrecheckItem] {
        let fileManager = FileManager.default
        guard !path.isEmpty else {
            return [.init(title: title, message: "尚未选择。", severity: .error)]
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return [.init(title: title, message: missingMessage, severity: .error)]
        }

        var items = [PrecheckItem(title: title, message: "存在：\(path)", severity: .ok)]

        if mustBeReadable, !fileManager.isReadableFile(atPath: path) {
            items.append(.init(title: title, message: "目录不可读。请检查权限。", severity: .error))
        }

        if mustBeWritable {
            if !fileManager.isWritableFile(atPath: path) {
                items.append(.init(title: title, message: "目录不可写。请检查 SMB 权限或 Windows 共享设置。", severity: .error))
            } else if performWriteProbe {
                items.append(contentsOf: writeProbe(path: path))
            }
        }

        return items
    }

    private func writeProbe(path: String) -> [PrecheckItem] {
        let url = URL(fileURLWithPath: path).appendingPathComponent(".disk-ferry-write-test-\(UUID().uuidString)")
        do {
            try Data().write(to: url, options: .atomic)
            try FileManager.default.removeItem(at: url)
            return [.init(title: "目标写入测试", message: "目标目录可写。", severity: .ok)]
        } catch {
            return [.init(title: "目标写入测试", message: "无法写入目标目录：\(error.localizedDescription)", severity: .error)]
        }
    }

}
