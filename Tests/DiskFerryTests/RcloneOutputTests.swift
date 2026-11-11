import Foundation
import XCTest
@testable import DiskFerry

final class RcloneOutputTests: XCTestCase {
    // Captured from rclone 1.75 with --use-json-log --stats-one-line.
    private let jsonSample = """
    {"time":"2026-09-25T21:05:38.047616+09:00","level":"notice","msg":"Serving remote control on http://127.0.0.1:55799/","source":"rcserver/rcserver.go:151"}
    {"time":"2026-09-25T21:05:38.051639+09:00","level":"notice","msg":"Config file \\"/Users/me/.config/rclone/rclone.conf\\" not found - using defaults","source":"config/config.go:374"}
    {"time":"2026-09-25T21:05:38.063259+09:00","level":"error","msg":"Failed to copy: permission denied","object":"b.txt","objectType":"*local.Object","source":"operations/copy.go:347"}
    {"time":"2026-09-25T21:05:38.063738+09:00","level":"error","msg":"Attempt 1/1 failed with 1 errors and: permission denied","source":"cmd/cmd.go:283"}
    {"time":"2026-09-25T21:05:38.064042+09:00","level":"notice","msg":"          3 B / 6 B, 50%, 0 B/s, ETA -\\n","stats":{"bytes":3,"checks":0,"elapsedTime":0.0087,"errors":1,"eta":null,"fatalError":false,"lastError":"permission denied","listed":2,"speed":0,"totalBytes":6,"totalChecks":0,"totalTransfers":2,"transfers":1},"source":"accounting/stats.go:549"}
    {"time":"2026-09-25T21:05:38.064812+09:00","level":"notice","msg":"Failed to copy: permission denied","source":"cmd/cmd.go:334"}
    """

    func testDisplayLinesFromJSONLog() {
        XCTAssertEqual(RcloneOutput.displayLines(jsonSample), [
            "ERROR : b.txt: Failed to copy: permission denied",
            "ERROR : Attempt 1/1 failed with 1 errors and: permission denied",
            "NOTICE: Failed to copy: permission denied"
        ])
    }

    func testErrorLinesDropRetrySummaries() {
        XCTAssertEqual(RcloneOutput.errorLines(jsonSample + "\n" + jsonSample), [
            "b.txt: Failed to copy: permission denied"
        ])
    }

    func testFinalStatsFromExitLine() throws {
        let stats = try XCTUnwrap(RcloneOutput.finalStats(jsonSample))
        XCTAssertEqual(stats.bytes, 3)
        XCTAssertEqual(stats.totalTransfers, 2)
        XCTAssertEqual(stats.errors, 1)
    }

    func testPlainTextBeforeLoggingStarts() {
        let text = "Error: unknown flag: --bogus\nUsage:\n  rclone copy source:path dest:path [flags]\n"
        XCTAssertEqual(RcloneOutput.errorLines(text), ["unknown flag: --bogus"])
        XCTAssertNil(RcloneOutput.finalStats(text))
    }

    func testCheckDifferencesAreRecognized() {
        // Captured from rclone 1.76 `check --size-only --one-way` with a missing file.
        let differences = """
        {"time":"2026-11-11T09:20:03.405118+09:00","level":"error","msg":"file not in Local file system at /tmp/b","object":"x","objectType":"*local.Object","source":"operations/check.go:108"}
        {"time":"2026-11-11T09:20:03.406878+09:00","level":"notice","msg":"1 files missing","object":"Local file system at /tmp/b","objectType":"*local.Fs","source":"operations/check.go:242"}
        {"time":"2026-11-11T09:20:03.407149+09:00","level":"notice","msg":"1 differences found","object":"Local file system at /tmp/b","objectType":"*local.Fs","source":"operations/check.go:252"}
        {"time":"2026-11-11T09:20:03.407458+09:00","level":"notice","msg":"Failed to check: 1 differences found","source":"cmd/cmd.go:334"}
        """
        XCTAssertTrue(RcloneOutput.reportsDifferences(differences))
        XCTAssertFalse(RcloneOutput.reportsDifferences(jsonSample))
        XCTAssertFalse(RcloneOutput.reportsDifferences(#"{"level":"notice","msg":"0 differences found"}"#))
        XCTAssertFalse(RcloneOutput.reportsDifferences("Error: directory not found\n"))
    }

    func testTruncatedLeadingLineIsIgnored() {
        let text = "ted\",\"level\":\"error\"}\n" + jsonSample
        XCTAssertEqual(RcloneOutput.finalStats(text)?.totalBytes, 6)
    }
}
