import Foundation

/// Checks rclone, source and destination before a run. Touches the (possibly remote)
/// filesystem, so it must run off the main thread.
struct PrecheckService {
    /// A dry run only reads: it never creates the destination folder or writes the
    /// probe file, because `rclone copy --dry-run` copes with a missing destination.
    func run(task: TransferTask, rclonePath: String?, dryRun: Bool = false) -> PrecheckResult {
        var result = PrecheckResult(items: [])

        if let resolvedRclone = RcloneLocator.locate(preferredPath: rclonePath) {
            result.rclonePath = resolvedRclone
            result.items.append(.init(title: "rclone", message: "已找到：\(resolvedRclone)", severity: .ok))
        } else {
            result.items.append(.init(
                title: "rclone",
                message: "没有找到 rclone。请确认已安装：brew install rclone",
                severity: .error
            ))
        }

        result.items.append(contentsOf: checkDirectory(
            title: "源目录",
            path: task.sourcePath,
            mustBeReadable: true,
            mustBeWritable: false,
            missingMessage: "源目录不存在，可能是外置磁盘已经断开。"
        ))

        result.items.append(contentsOf: checkDirectory(
            title: "目标目录",
            path: task.targetPath,
            mustBeReadable: false,
            mustBeWritable: !dryRun,
            missingMessage: "目标目录不存在，可能是 SMB 连接已经断开。"
        ))

        let resolvedTargetPath = task.resolvedTargetPath
        // Checked before DestinationPathPolicy.prepare, which creates folders.
        var hasPathConflict = false
        if !task.sourcePath.isEmpty, !resolvedTargetPath.isEmpty {
            let source = URL(fileURLWithPath: task.sourcePath).standardizedFileURL.path
            let target = URL(fileURLWithPath: resolvedTargetPath).standardizedFileURL.path
            if source == target {
                hasPathConflict = true
                result.items.append(.init(title: "路径检查", message: "源目录和目标目录不能相同。", severity: .error))
            } else if PathInspector.resolvedIsSameOrInside(target, source) {
                hasPathConflict = true
                result.items.append(.init(
                    title: "路径检查",
                    message: "目标就是源文件夹或位于其内部（可能经由符号链接或大小写不同的路径），复制会把自己复制进自己。请换一个目标。",
                    severity: .error
                ))
            }
        }

        guard !task.targetPath.isEmpty, !hasPathConflict else { return result }

        do {
            if dryRun {
                let destinationExists = try DestinationPathPolicy.inspect(task: task)
                if resolvedTargetPath != task.targetPath {
                    result.items.append(.init(
                        title: "实际写入位置",
                        message: destinationExists
                            ? "将复制到：\(resolvedTargetPath)"
                            : "将复制到：\(resolvedTargetPath)（正式复制时创建，预演不创建）",
                        severity: .ok
                    ))
                }
            } else {
                let destination = try DestinationPathPolicy.prepare(task: task)
                try DestinationPathPolicy.validate(destination)
                result.items.append(writeProbe(path: destination.selectedRoot.path))
                try DestinationPathPolicy.validate(destination)
                result.destination = destination
                if resolvedTargetPath != task.targetPath {
                    result.items.append(.init(
                        title: "实际写入位置",
                        message: "将复制到：\(resolvedTargetPath)",
                        severity: .ok
                    ))
                }
            }
            result.items.append(.init(
                title: "目标路径安全检查",
                message: "写入位置位于所选目录内，且不包含符号链接。",
                severity: .ok
            ))
        } catch {
            result.destination = nil
            result.items.append(.init(
                title: "目标路径安全检查",
                message: error.localizedDescription,
                severity: .error
            ))
        }

        return result
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

        if mustBeWritable, !fileManager.isWritableFile(atPath: path) {
            items.append(.init(title: title, message: "目录不可写。请检查 SMB 权限或 Windows 共享设置。", severity: .error))
        }

        return items
    }

    /// `isWritableFile` only looks at permission bits, which SMB shares often misreport.
    /// An empty file that is written and removed again is the reliable answer.
    private func writeProbe(path: String) -> PrecheckItem {
        let url = URL(fileURLWithPath: path).appendingPathComponent(".disk-ferry-write-test-\(UUID().uuidString)")
        do {
            try Data().write(to: url, options: .atomic)
            try FileManager.default.removeItem(at: url)
            return .init(title: "目标写入测试", message: "目标目录可写。", severity: .ok)
        } catch {
            return .init(title: "目标写入测试", message: "无法写入目标目录：\(error.localizedDescription)", severity: .error)
        }
    }
}
