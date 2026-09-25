import Foundation

/// Reads rclone's console output (JSON log lines from `--use-json-log`, plus plain text
/// printed before logging starts, such as flag errors).
enum RcloneOutput {
    /// Startup chatter that says nothing about the failure.
    private static let noise = [
        "Serving remote control on",
        "Config file \"",
        "using defaults"
    ]

    /// The `stats` object rclone logs when it exits: the authoritative final numbers.
    static func finalStats(_ text: String) -> RcloneCoreStats? {
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            guard let object = jsonObject(line), let stats = object["stats"],
                  let data = try? JSONSerialization.data(withJSONObject: stats) else { continue }
            if let decoded = try? JSONDecoder().decode(RcloneCoreStats.self, from: data) {
                return decoded
            }
        }
        return nil
    }

    /// Human-readable lines such as "ERROR : photo.heic: Failed to copy: …".
    static func displayLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                guard let object = jsonObject(line) else {
                    return stripTimestamp(String(line))
                }
                // Periodic / final stats are shown by the progress view instead.
                guard object["stats"] == nil, let message = object["msg"] as? String else { return nil }
                let level = (object["level"] as? String ?? "notice").uppercased()
                let prefix = level.count < 6 ? level.padding(toLength: 6, withPad: " ", startingAt: 0) : level
                var body = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if let item = object["object"] as? String, !item.isEmpty {
                    body = "\(item): \(body)"
                }
                return "\(prefix): \(body)"
            }
            .filter { line in
                !line.trimmingCharacters(in: .whitespaces).isEmpty && !noise.contains { line.contains($0) }
            }
    }

    /// The distinct ERROR messages, reduced to "file: message", most recent last.
    /// rclone's "Attempt 3/10 failed…" retry summaries are dropped when the underlying
    /// per-file errors are present, since they only repeat them.
    static func errorLines(_ text: String, limit: Int = 5) -> [String] {
        let errors = displayLines(text).compactMap { line -> String? in
            for marker in ["ERROR : ", "CRITICAL: ", "Fatal error: "] {
                if let range = line.range(of: marker) {
                    return String(line[range.upperBound...])
                }
            }
            if line.hasPrefix("Error: ") {
                return String(line.dropFirst("Error: ".count))
            }
            return nil
        }
        let specific = errors.filter { !$0.hasPrefix("Attempt ") }
        var seen = Set<String>()
        let unique = (specific.isEmpty ? errors : specific).reversed().filter { seen.insert($0).inserted }
        return Array(unique.prefix(limit).reversed())
    }

    private static func jsonObject(_ line: Substring) -> [String: Any]? {
        guard line.first == "{", let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// "2026/09/25 20:42:29 ERROR : x" → "ERROR : x"
    private static func stripTimestamp(_ line: String) -> String {
        let pattern = #"^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2} "#
        guard let range = line.range(of: pattern, options: .regularExpression) else { return line }
        return String(line[range.upperBound...])
    }
}
