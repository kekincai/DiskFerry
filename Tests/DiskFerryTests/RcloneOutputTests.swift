import XCTest
@testable import DiskFerry

final class RcloneOutputTests: XCTestCase {
    private let sample = """
    2026/09/25 20:42:29 NOTICE: Serving remote control on http://127.0.0.1:55741/
    2026/09/25 20:42:29 NOTICE: Config file "/Users/me/.config/rclone/rclone.conf" not found - using defaults
    2026/09/25 20:42:29 ERROR : f3.bin: Failed to copy: open src/f3.bin: permission denied
    2026/09/25 20:42:29 ERROR : Attempt 1/1 failed with 1 errors and: permission denied
    2026/09/25 20:42:29 NOTICE: Failed to copy: permission denied
    """

    func testDisplayLinesDropNoiseAndTimestamps() {
        XCTAssertEqual(RcloneOutput.displayLines(sample), [
            "ERROR : f3.bin: Failed to copy: open src/f3.bin: permission denied",
            "ERROR : Attempt 1/1 failed with 1 errors and: permission denied",
            "NOTICE: Failed to copy: permission denied"
        ])
    }

    func testErrorLines() {
        let retried = sample + "\n" + sample
        XCTAssertEqual(RcloneOutput.errorLines(retried), [
            "f3.bin: Failed to copy: open src/f3.bin: permission denied"
        ])
    }
}
