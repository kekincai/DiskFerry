import Foundation

final class RcloneRunner {
    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var outputCoalescer: OutputCoalescer?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start(
        rclonePath: String,
        task: TransferTask,
        logFile: String,
        dryRun: Bool,
        onOutput: @escaping @Sendable (String) -> Void,
        onFinish: @escaping @MainActor (Int32) -> Void
    ) throws {
        let arguments = makeArguments(task: task, logFile: logFile, dryRun: dryRun)
        try start(
            rclonePath: rclonePath,
            arguments: arguments,
            onOutput: onOutput,
            onFinish: onFinish
        )
    }

    func startCheck(
        rclonePath: String,
        task: TransferTask,
        logFile: String,
        onOutput: @escaping @Sendable (String) -> Void,
        onFinish: @escaping @MainActor (Int32) -> Void
    ) throws {
        try start(
            rclonePath: rclonePath,
            arguments: makeCheckArguments(task: task, logFile: logFile),
            onOutput: onOutput,
            onFinish: onFinish
        )
    }

    private func start(
        rclonePath: String,
        arguments: [String],
        onOutput: @escaping @Sendable (String) -> Void,
        onFinish: @escaping @MainActor (Int32) -> Void
    ) throws {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let outputCoalescer = OutputCoalescer(interval: 2.0, onOutput: onOutput)

        process.executableURL = URL(fileURLWithPath: rclonePath)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        func attach(_ handle: FileHandle) {
            handle.readabilityHandler = { [weak outputCoalescer] pipe in
                let data = pipe.availableData
                guard !data.isEmpty else { return }
                let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                outputCoalescer?.append(text)
            }
        }

        attach(stdout.fileHandleForReading)
        attach(stderr.fileHandleForReading)

        process.terminationHandler = { [weak self] finishedProcess in
            self?.stdoutHandle?.readabilityHandler = nil
            self?.stderrHandle?.readabilityHandler = nil
            self?.outputCoalescer?.flush()
            Task { @MainActor in
                onFinish(finishedProcess.terminationStatus)
            }
        }

        self.process = process
        self.stdoutHandle = stdout.fileHandleForReading
        self.stderrHandle = stderr.fileHandleForReading
        self.outputCoalescer = outputCoalescer

        try process.run()
    }

    func stop() {
        guard let process, process.isRunning else { return }
        process.terminate()
    }

    func makeArguments(task: TransferTask, logFile: String, dryRun: Bool) -> [String] {
        var arguments = [
            "copy",
            task.sourcePath,
            task.resolvedTargetPath
        ]

        if dryRun {
            arguments.append("--dry-run")
        }

        arguments.append(contentsOf: [
            "--stats", "2s",
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
        [
            "check",
            task.sourcePath,
            task.resolvedTargetPath,
            "--size-only",
            "--one-way",
            "--log-file", logFile,
            "--log-level", "INFO"
        ]
    }
}

private final class OutputCoalescer {
    private let lock = NSLock()
    private let interval: TimeInterval
    private let maxPendingCharacters = 40_000
    private var pending = ""
    private var flushScheduled = false
    private let onOutput: @Sendable (String) -> Void

    init(interval: TimeInterval, onOutput: @escaping @Sendable (String) -> Void) {
        self.interval = interval
        self.onOutput = onOutput
    }

    func append(_ text: String) {
        lock.lock()
        pending.append(text)
        if pending.count > maxPendingCharacters {
            pending.removeFirst(pending.count - maxPendingCharacters)
        }
        let shouldSchedule = !flushScheduled
        if shouldSchedule {
            flushScheduled = true
        }
        lock.unlock()

        guard shouldSchedule else { return }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.flush()
        }
    }

    func flush() {
        lock.lock()
        let text = pending
        pending = ""
        flushScheduled = false
        lock.unlock()

        guard !text.isEmpty else { return }

        onOutput(text)
    }
}
