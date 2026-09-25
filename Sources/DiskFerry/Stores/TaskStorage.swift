import Foundation

/// Saved routes live in Application Support. Only small metadata is stored here;
/// transfer logs always go to the destination.
struct TaskStorage {
    static let recentLimit = 20

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
            let data = try JSONCoding.encoder.encode(Self.trimmed(tasks))
            try data.write(to: recentTasksURL, options: .atomic)
        } catch {
            // Saved routes are a convenience; transfer logging still goes to the target disk.
        }
    }

    /// Pinned routes are kept forever; unpinned history is capped.
    static func trimmed(_ tasks: [TransferTask]) -> [TransferTask] {
        var unpinnedCount = 0
        return tasks.filter { task in
            if task.isPinned { return true }
            unpinnedCount += 1
            return unpinnedCount <= recentLimit
        }
    }
}
