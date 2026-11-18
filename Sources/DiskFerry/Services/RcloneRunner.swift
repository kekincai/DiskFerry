import Foundation

/// Owns one rclone child process at a time. Nothing is written to disk besides the copied
/// files: live numbers come from rclone's rc server (see `RcloneStatsClient`), and its
/// console output (NOTICE and above) is kept in memory to explain a failed run.
final class RcloneRunner {
    private var process: Process?
    private var outputTail: OutputTail?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start(
        rclonePath: String,
        task: TransferTask,
        dryRun: Bool,
        streamLocalCopies: Bool,
        destinationFileSystem: String?,
        remote: RcloneRemoteControl,
        onFinish: @escaping @MainActor (Int32, String) -> Void
    ) throws {
        try start(
            rclonePath: rclonePath,
            arguments: makeArguments(
                task: task,
                dryRun: dryRun,
                streamLocalCopies: streamLocalCopies,
                destinationFileSystem: destinationFileSystem
            ) + remote.arguments,
            environment: remote.environment,
            onFinish: onFinish
        )
    }

    func startCheck(
        rclonePath: String,
        task: TransferTask,
        remote: RcloneRemoteControl,
        onFinish: @escaping @MainActor (Int32, String) -> Void
    ) throws {
        try start(
            rclonePath: rclonePath,
            arguments: makeCheckArguments(task: task) + remote.arguments,
            environment: remote.environment,
            onFinish: onFinish
        )
    }

    /// Runs any executable with the same output capture; `internal` for tests.
    func start(
        rclonePath: String,
        arguments: [String],
        environment: [String: String] = [:],
        onFinish: @escaping @MainActor (Int32, String) -> Void
    ) throws {
        let process = Process()
        let output = Pipe()
        let tail = OutputTail()

        process.executableURL = URL(fileURLWithPath: rclonePath)
        process.arguments = arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
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
            let reader = output.fileHandleForReading
            reader.readabilityHandler = nil
            // The readability handler runs asynchronously and may not have seen the last
            // bytes written just before exit (often the actual error). Process closed our
            // copy of the write end at launch, so this reads to EOF without blocking.
            if let rest = try? reader.readToEnd(), !rest.isEmpty {
                tail.append(rest)
            }
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

    /// `destinationFileSystem` is the destination volume's `f_fstypename`, read off the
    /// main thread beforehand; nil when unknown.
    func makeArguments(
        task: TransferTask,
        dryRun: Bool,
        streamLocalCopies: Bool = false,
        destinationFileSystem: String? = nil
    ) -> [String] {
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

        if let window = Self.modifyWindow(forFileSystem: destinationFileSystem) {
            arguments.append(contentsOf: ["--modify-window", window])
        }

        arguments.append(contentsOf: [
            "--transfers", "\(task.transfers)",
            "--checkers", "\(task.checkers)",
            "--retries", "\(task.retries)",
            "--low-level-retries", "\(task.lowLevelRetries)"
        ])

        arguments.append(contentsOf: filterArguments(task: task))
        arguments.append(contentsOf: quietConsole)
        return arguments
    }

    func makeCheckArguments(task: TransferTask) -> [String] {
        var arguments = [
            "check",
            task.sourcePath,
            task.resolvedTargetPath,
            "--size-only",
            "--one-way",
            "--checkers", "\(task.checkers)"
        ]
        arguments.append(contentsOf: filterArguments(task: task))
        arguments.append(contentsOf: quietConsole)
        return arguments
    }

    /// A single folder only needs the excludes. Several folders are copied in one run from
    /// their shared parent, so the filter keeps only those folders. Everything is written as
    /// `--filter` there, because rclone applies `--filter` rules in command-line order but
    /// groups `--exclude` rules separately.
    private func filterArguments(task: TransferTask) -> [String] {
        guard task.hasMultipleSources else {
            return task.excludes.flatMap { ["--exclude", $0] }
        }
        var rules = task.excludes.map { "- \($0)" }
        rules += task.sourceItems.map { "+ /\(Self.escapeGlob($0))/**" }
        rules.append("- **")
        return rules.flatMap { ["--filter", $0] }
    }

    /// Folder names are matched literally, not as glob patterns.
    static func escapeGlob(_ name: String) -> String {
        var escaped = ""
        for character in name {
            if "\\*?[]{}".contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    /// Errors and notices only, as JSON lines. The UI polls rc for live numbers; the
    /// long stats interval exists so rclone still emits one final `stats` object at exit,
    /// which captures runs that finish before the first poll.
    private var quietConsole: [String] {
        [
            "--log-level", "NOTICE",
            "--use-json-log",
            "--stats", "1h",
            "--stats-log-level", "NOTICE",
            "--stats-one-line"
        ]
    }

    /// exFAT keeps modification times to 10 ms and FAT to 2 s, against nanoseconds on APFS.
    /// Without a window rclone sees every file already on such a disk as changed: it hashes
    /// both sides and rewrites the time, which also makes macOS write a fresh `._` sidecar.
    /// 2 s covers FAT. Only `copy` gets it; the verification is `--size-only` anyway.
    static func modifyWindow(forFileSystem fileSystem: String?) -> String? {
        guard let fileSystem else { return nil }
        return ["exfat", "msdos"].contains(fileSystem.lowercased()) ? "2s" : nil
    }

    /// rclone exit codes, see https://rclone.org/docs/#exit-code
    static func describe(exitCode: Int32) -> String {
        switch exitCode {
        case 0: "成功"
        case 1: "部分文件复制失败"
        case 2: "参数或命令错误"
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
    private let limit = 64 * 1_024

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
