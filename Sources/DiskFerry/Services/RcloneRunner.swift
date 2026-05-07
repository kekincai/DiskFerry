import Foundation

final class RcloneRunner {
    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start(
        rclonePath: String,
        task: TransferTask,
        logFile: String,
        dryRun: Bool,
        onOutput: @escaping @MainActor (String) -> Void,
        onFinish: @escaping @MainActor (Int32) -> Void
    ) throws {
        let arguments = makeArguments(task: task, logFile: logFile, dryRun: dryRun)
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: rclonePath)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        func attach(_ handle: FileHandle) {
            handle.readabilityHandler = { pipe in
                let data = pipe.availableData
                guard !data.isEmpty else { return }
                let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                Task { @MainActor in
                    onOutput(text)
                }
            }
        }

        attach(stdout.fileHandleForReading)
        attach(stderr.fileHandleForReading)

        process.terminationHandler = { [weak self] finishedProcess in
            self?.stdoutHandle?.readabilityHandler = nil
            self?.stderrHandle?.readabilityHandler = nil
            Task { @MainActor in
                onFinish(finishedProcess.terminationStatus)
            }
        }

        self.process = process
        self.stdoutHandle = stdout.fileHandleForReading
        self.stderrHandle = stderr.fileHandleForReading

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
            "--stats", "5s",
            "--stats-one-line",
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
}
