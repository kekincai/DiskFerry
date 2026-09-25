import Foundation

/// Reads only the end of a (possibly huge, possibly remote) rclone log file.
enum LogTail {
    static func read(path: String, maxBytes: Int = 64 * 1_024) -> String? {
        guard !path.isEmpty, let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        do {
            let size = try handle.seekToEnd()
            let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
            try handle.seek(toOffset: start)
            let data = try handle.readToEnd() ?? Data()
            var text = String(decoding: data, as: UTF8.self)
            if start > 0, let newline = text.firstIndex(of: "\n") {
                // Drop the partial first line.
                text = String(text[text.index(after: newline)...])
            }
            return text
        } catch {
            return nil
        }
    }

    /// The most recent ERROR lines, used to explain a failed run.
    static func recentErrors(path: String, limit: Int = 5) -> [String] {
        guard let text = read(path: path, maxBytes: 32 * 1_024) else { return [] }
        let lines = text.split(separator: "\n").filter { $0.contains("ERROR") || $0.contains("CRITICAL") }
        return lines.suffix(limit).map { line in
            // "2026/09/25 20:24:16 ERROR : file: message" → "file: message"
            if let range = line.range(of: "ERROR : ") ?? line.range(of: "CRITICAL: ") {
                return String(line[range.upperBound...])
            }
            return String(line)
        }
    }
}
