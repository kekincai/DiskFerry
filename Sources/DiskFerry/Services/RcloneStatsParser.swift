import Foundation

enum RcloneStatsParser {
    static func apply(_ text: String, to progress: inout TransferProgress) {
        let before = progress
        let normalized = text.replacingOccurrences(of: "\r", with: "\n")
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            parseLine(String(line), into: &progress)
        }
        if progress != before {
            progress.progressSource = .rcloneOutput
        }
    }

    private static func parseLine(_ line: String, into progress: inout TransferProgress) {
        parseByteStats(line, into: &progress)
        parseFileStats(line, into: &progress)

        if let etaRange = line.range(of: #"ETA\s+([^,\s]+)"#, options: .regularExpression) {
            let eta = line[etaRange].replacingOccurrences(of: "ETA", with: "").trimmingCharacters(in: .whitespaces)
            if !eta.isEmpty {
                progress.etaText = eta
            }
        }
    }

    private static func parseByteStats(_ line: String, into progress: inout TransferProgress) {
        guard let range = line.range(
            of: #"(?:Transferred:\s*)?([0-9.]+)\s*([KMGTPE]?i?B|B)\s*/\s*([0-9.]+)\s*([KMGTPE]?i?B|B)(?:,\s*([0-9.]+)%)?(?:,\s*([^,]+/s))?"#,
            options: .regularExpression
        ) else {
            return
        }

        let match = String(line[range])
        let parts = regexCapture(
            pattern: #"(?:Transferred:\s*)?([0-9.]+)\s*([KMGTPE]?i?B|B)\s*/\s*([0-9.]+)\s*([KMGTPE]?i?B|B)(?:,\s*([0-9.]+)%)?(?:,\s*([^,]+/s))?"#,
            text: match
        )

        guard parts.count >= 4 else { return }
        progress.transferredBytes = bytes(value: parts[0], unit: parts[1])
        progress.totalBytes = bytes(value: parts[2], unit: parts[3])

        if parts.count >= 5, let percent = Double(parts[4]) {
            progress.percent = percent
        } else if let transferred = progress.transferredBytes,
                  let total = progress.totalBytes,
                  total > 0 {
            progress.percent = Double(transferred) / Double(total) * 100
        }

        if parts.count >= 6, !parts[5].isEmpty {
            progress.speedText = parts[5].trimmingCharacters(in: .whitespaces)
        }
    }

    private static func parseFileStats(_ line: String, into progress: inout TransferProgress) {
        let matches = regexCaptureAll(pattern: #"Transferred:\s*([0-9]+)\s*/\s*([0-9]+)"#, text: line)
        guard let last = matches.last, last.count >= 2 else { return }
        progress.transferredFiles = Int(last[0])
        if progress.totalFiles == nil {
            progress.totalFiles = Int(last[1])
        }
    }

    private static func regexCapture(pattern: String, text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return [] }
        return (1..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }

    private static func regexCaptureAll(pattern: String, text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).map { index in
                guard let range = Range(match.range(at: index), in: text) else { return "" }
                return String(text[range])
            }
        }
    }

    private static func bytes(value: String, unit: String) -> Int64? {
        guard let number = Double(value) else { return nil }
        let multiplier: Double
        switch unit {
        case "B": multiplier = 1
        case "KB": multiplier = 1_000
        case "MB": multiplier = 1_000_000
        case "GB": multiplier = 1_000_000_000
        case "TB": multiplier = 1_000_000_000_000
        case "KiB": multiplier = 1_024
        case "MiB": multiplier = 1_048_576
        case "GiB": multiplier = 1_073_741_824
        case "TiB": multiplier = 1_099_511_627_776
        default: multiplier = 1
        }
        return Int64(number * multiplier)
    }
}
