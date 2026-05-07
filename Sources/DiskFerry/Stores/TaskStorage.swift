import Foundation

struct TaskStorage {
    private var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("DiskFerry", isDirectory: true)
    }

    private var recentTasksURL: URL {
        applicationSupportDirectory.appendingPathComponent("recent_tasks.json")
    }

    func loadRecentTasks() -> [TransferTask] {
        do {
            let data = try Data(contentsOf: recentTasksURL)
            return try JSONCoding.decoder.decode([TransferTask].self, from: data)
        } catch {
            return []
        }
    }

    func saveRecentTasks(_ tasks: [TransferTask]) {
        do {
            try FileManager.default.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
            let data = try JSONCoding.encoder.encode(Array(tasks.prefix(20)))
            try data.write(to: recentTasksURL, options: .atomic)
        } catch {
            // Recent tasks are a convenience cache; transfer logging still goes to the target disk.
        }
    }
}
