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

        if !task.sourcePath.isEmpty,
           !task.targetPath.isEmpty,
           URL(fileURLWithPath: task.sourcePath).standardizedFileURL == URL(fileURLWithPath: task.targetPath).standardizedFileURL {
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
            ? URL(fileURLWithPath: task.targetPath).appendingPathComponent("_transfer_logs").path
            : task.logDirectory

        if !task.targetPath.isEmpty {
            do {
                try fileManager.createDirectory(atPath: logDirectory, withIntermediateDirectories: true)
                items.append(.init(title: "日志目录", message: "可创建或已存在：\(logDirectory)", severity: .ok))
            } catch {
                items.append(.init(title: "日志目录", message: "无法创建日志目录：\(error.localizedDescription)", severity: .error))
            }
        }

        if let homeFree = freeBytes(forPath: NSHomeDirectory()) {
            let gib = Double(homeFree) / 1024 / 1024 / 1024
            if gib < 10 {
                items.append(.init(
                    title: "Mac 本机空间",
                    message: String(format: "剩余 %.1f GB，过低。系统级缓存可能影响稳定性。", gib),
                    severity: .error
                ))
            } else if gib < 30 {
                items.append(.init(
                    title: "Mac 本机空间",
                    message: String(format: "剩余 %.1f GB，偏低。建议关闭 Finder 预览、Photos，并避免 Spotlight 索引相关磁盘。", gib),
                    severity: .warning
                ))
            } else {
                items.append(.init(title: "Mac 本机空间", message: String(format: "剩余 %.1f GB", gib), severity: .ok))
            }
        }

        if let sourceSize = directoryAllocatedSize(atPath: task.sourcePath),
           let targetFree = freeBytes(forPath: task.targetPath),
           sourceSize > targetFree {
            items.append(.init(
                title: "目标剩余空间",
                message: "目标剩余空间可能不足。此检查按源目录已分配大小粗略估算。",
                severity: .warning
            ))
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

    private func freeBytes(forPath path: String) -> Int64? {
        guard !path.isEmpty else { return nil }
        do {
            let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage
        } catch {
            return nil
        }
    }

    private func directoryAllocatedSize(atPath path: String) -> Int64? {
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        var total: Int64 = 0
        var visited = 0
        for case let fileURL as URL in enumerator {
            visited += 1
            if visited > 20_000 {
                return nil
            }
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
