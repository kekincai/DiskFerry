import Foundation

/// Cleans up rclone's console output for display after a failed run.
enum RcloneOutput {
    /// Startup chatter that says nothing about the failure.
    private static let noise = [
        "Serving remote control on",
        "Config file \"",
        "using defaults"
    ]

    /// All meaningful lines, without timestamps.
    static func displayLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { stripTimestamp(String($0)) }
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
            return nil
        }
        let specific = errors.filter { !$0.hasPrefix("Attempt ") }
        var seen = Set<String>()
        let unique = (specific.isEmpty ? errors : specific).reversed().filter { seen.insert($0).inserted }
        return Array(unique.prefix(limit).reversed())
    }

    /// "2026/09/25 20:42:29 ERROR : x" → "ERROR : x"
    private static func stripTimestamp(_ line: String) -> String {
        let pattern = #"^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2} "#
        guard let range = line.range(of: pattern, options: .regularExpression) else { return line }
        return String(line[range.upperBound...])
    }
}
