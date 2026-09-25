import Foundation

/// Owns one rclone child process at a time. Everything rclone logs goes to `--log-file`
/// on the destination; live numbers come from its rc server (see `RcloneStatsClient`).
/// stdout/stderr are only kept as a small tail for startup errors such as a bad flag.
final class RcloneRunner {
    private var process: Process?
    private var outputTail: OutputTail?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start(
        rclonePath: String,
        task: TransferTask,
        logFile: String,
        dryRun: Bool,
        streamLocalCopies: Bool,
        remote: RcloneRemoteControl,
        onFinish: @escaping @MainActor (Int32, String) -> Void
    ) throws {
        try start(
            rclonePath: rclonePath,
            arguments: makeArguments(task: task, logFile: logFile, dryRun: dryRun, streamLocalCopies: streamLocalCopies)
                + remote.arguments,
            onFinish: onFinish
        )
    }

    func startCheck(
        rclonePath: String,
        task: TransferTask,
        logFile: String,
        remote: RcloneRemoteControl,
        onFinish: @escaping @MainActor (Int32, String) -> Void
    ) throws {
        try start(
            rclonePath: rclonePath,
            arguments: makeCheckArguments(task: task, logFile: logFile) + remote.arguments,
            onFinish: onFinish
        )
    }

    private func start(
        rclonePath: String,
        arguments: [String],
        onFinish: @escaping @MainActor (Int32, String) -> Void
    ) throws {
        let process = Process()
        let output = Pipe()
        let tail = OutputTail()

        process.executableURL = URL(fileURLWithPath: rclonePath)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            tail.append(data)
        }

        process.terminationHandler = { finishedProcess in
            output.fileHandleForReading.readabilityHandler = nil
            let status = finishedProcess.terminationStatus
            let text = tail.text
            Task { @MainActor in
                onFinish(status, text)
            }
        }

        self.process = process
        self.outputTail = tail
        try process.run()
    }

    func stop() {
        guard let process, process.isRunning else { return }
        process.terminate()
    }

    func makeArguments(task: TransferTask, logFile: String, dryRun: Bool, streamLocalCopies: Bool = false) -> [String] {
        var arguments = [
            "copy",
            task.sourcePath,
            task.resolvedTargetPath
        ]

        if dryRun {
            arguments.append("--dry-run")
        }

        if task.checkFirst {
            arguments.append("--check-first")
        }

        if streamLocalCopies {
            // Stream bytes through rclone instead of an OS-level file copy, so progress is
            // counted per byte (not per finished file) and no clone/copyfile cache is involved.
            arguments.append("--local-no-clone")
        }

        arguments.append(contentsOf: [
            // Periodic stats in the log file are for the record only; the UI polls rc.
            "--stats", "30s",
            "--stats-log-level", "NOTICE",
            "--transfers", "\(task.transfers)",
            "--checkers", "\(task.checkers)",
            "--retries", "\(task.retries)",
            "--low-level-retries", "\(task.lowLevelRetries)"
        ])

        for exclude in task.excludes {
            arguments.append(contentsOf: ["--exclude", exclude])
        }

        arguments.append(contentsOf: [
            "--log-file", logFile,
            "--log-level", "INFO"
        ])

        return arguments
    }

    func makeCheckArguments(task: TransferTask, logFile: String) -> [String] {
        var arguments = [
            "check",
            task.sourcePath,
            task.resolvedTargetPath,
            "--size-only",
            "--one-way",
            "--checkers", "\(task.checkers)"
        ]
        for exclude in task.excludes {
            arguments.append(contentsOf: ["--exclude", exclude])
        }
        arguments.append(contentsOf: [
            "--log-file", logFile,
            "--log-level", "INFO"
        ])
        return arguments
    }

    /// rclone exit codes, see https://rclone.org/docs/#exit-code
    static func describe(exitCode: Int32) -> String {
        switch exitCode {
        case 0: "成功"
        case 1: "参数或命令错误"
        case 2: "发生错误（详见日志）"
        case 3: "找不到目录"
        case 4: "找不到文件"
        case 5: "临时错误，可以重试（例如网络中断）"
        case 6: "部分文件出错，其余已完成"
        case 7: "致命错误（例如磁盘已满或权限不足）"
        case 8: "超出传输限制"
        case 9: "没有需要传输的文件"
        case 15: "已被中止"
        default: "退出码 \(exitCode)"
        }
    }
}

/// Keeps the last few KB of rclone's console output without ever touching the main thread.
private final class OutputTail: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let limit = 8 * 1_024

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        if buffer.count > limit {
            buffer.removeFirst(buffer.count - limit)
        }
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: buffer, as: UTF8.self)
    }
}
