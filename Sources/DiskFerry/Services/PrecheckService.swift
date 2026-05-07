import Foundation

struct PrecheckService {
    func run(task: TransferTask, rclonePath: String?) -> PrecheckResult {
        let fileManager = FileManager.default
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
            missingMessage: "目标目录不存在，可能是 SMB 连接已经断开。"
        ))

        let resolvedTargetPath = task.resolvedTargetPath
        if !resolvedTargetPath.isEmpty, resolvedTargetPath != task.targetPath {
            do {
                try fileManager.createDirectory(atPath: resolvedTargetPath, withIntermediateDirectories: true)
                items.append(.init(
                    title: "实际写入位置",
                    message: "将复制到：\(resolvedTargetPath)",
                    severity: .ok
                ))
            } catch {
                items.append(.init(
                    title: "实际写入位置",
                    message: "无法创建目标子文件夹：\(error.localizedDescription)",
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

        let logDirectory = task.logDirectory.isEmpty
            ? URL(fileURLWithPath: resolvedTargetPath).appendingPathComponent("_transfer_logs").path
            : task.logDirectory

        if !task.targetPath.isEmpty {
            do {
                try fileManager.createDirectory(atPath: logDirectory, withIntermediateDirectories: true)
                items.append(.init(title: "日志目录", message: "可创建或已存在：\(logDirectory)", severity: .ok))
            } catch {
                items.append(.init(title: "日志目录", message: "无法创建日志目录：\(error.localizedDescription)", severity: .error))
            }
        }

        return PrecheckResult(items: items)
    }

    private func checkDirectory(
        title: String,
        path: String,
        mustBeReadable: Bool,
        mustBeWritable: Bool,
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
            } else {
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
