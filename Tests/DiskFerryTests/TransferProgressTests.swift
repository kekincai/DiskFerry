import Foundation
import XCTest
@testable import DiskFerry

final class TransferProgressTests: XCTestCase {
    func testDecodesRcloneCoreStats() throws {
        let json = """
        {"bytes": 62111744, "checks": 3, "elapsedTime": 1.96, "errors": 1, "eta": null,
         "fatalError": false, "lastError": "boom", "listed": 8, "speed": 31636635.3,
         "totalBytes": 150000000, "totalChecks": 3, "totalTransfers": 5, "transfers": 1,
         "transferring": [{"bytes": 15396864, "name": "f1.bin", "percentage": 51,
                           "size": 30000000, "speedAvg": 7827286.4}]}
        """
        let stats = try JSONDecoder().decode(RcloneCoreStats.self, from: Data(json.utf8))
        XCTAssertEqual(stats.bytes, 62_111_744)
        XCTAssertEqual(stats.totalTransfers, 5)
        XCTAssertNil(stats.eta)
        XCTAssertEqual(stats.lastError, "boom")
        XCTAssertEqual(stats.transferring.first?.name, "f1.bin")
    }

    func testComparingPhaseIsIndeterminate() {
        let stats = RcloneCoreStats(checks: 120, totalChecks: 400, listed: 500)
        let progress = TransferProgress(stats: stats, verifying: false, checkFirst: true, currentSpeed: 0)
        XCTAssertEqual(progress.phase, .comparing)
        XCTAssertNil(progress.fraction)
        XCTAssertEqual(progress.skippedFiles, 120)
    }

    func testTransferringFractionUsesBytes() {
        let stats = RcloneCoreStats(bytes: 25, totalBytes: 100, transfers: 1, totalTransfers: 10, eta: 30)
        let progress = TransferProgress(stats: stats, verifying: false, checkFirst: true, currentSpeed: 5)
        XCTAssertEqual(progress.phase, .transferring)
        XCTAssertEqual(progress.fraction ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertTrue(progress.totalsAreFinal)
        XCTAssertEqual(progress.remainingFiles, 9)
        XCTAssertEqual(progress.eta, 30)
    }

    func testTotalsNotFinalWithoutCheckFirst() {
        let stats = RcloneCoreStats(bytes: 25, totalBytes: 100)
        let progress = TransferProgress(stats: stats, verifying: false, checkFirst: false, currentSpeed: 0)
        XCTAssertFalse(progress.totalsAreFinal)
    }

    func testVerifyingUsesChecks() {
        let stats = RcloneCoreStats(checks: 30, totalChecks: 120)
        let progress = TransferProgress(stats: stats, verifying: true, checkFirst: true, currentSpeed: 0)
        XCTAssertEqual(progress.phase, .verifying)
        XCTAssertEqual(progress.fraction ?? -1, 0.25, accuracy: 0.0001)
    }

    func testMarkSucceededCompletesTotals() {
        var progress = TransferProgress(
            stats: RcloneCoreStats(bytes: 90, totalBytes: 100, transfers: 9, totalTransfers: 10,
                                   transferring: [.init(name: "a", size: 10, bytes: 5, percentage: 50, speedAvg: 1)]),
            verifying: false,
            checkFirst: false,
            currentSpeed: 10
        )
        progress.markSucceeded()
        XCTAssertEqual(progress.phase, .finished)
        XCTAssertEqual(progress.bytes, 100)
        XCTAssertEqual(progress.transfers, 10)
        XCTAssertTrue(progress.active.isEmpty)
        XCTAssertEqual(progress.fraction, 1)
    }

    func testPercentNeverRoundsUpToHundred() {
        XCTAssertEqual(TransferFormatters.percent(0.9996), "99.9%")
        XCTAssertEqual(TransferFormatters.percent(1), "100.0%")
    }

    func testSpeedMeterUsesRecentWindow() {
        var meter = SpeedMeter(window: 5)
        XCTAssertEqual(meter.add(bytes: 0, at: 0), 0)
        XCTAssertEqual(meter.add(bytes: 100, at: 1), 100, accuracy: 0.001)
        _ = meter.add(bytes: 200, at: 2)
        // Stall: bytes stop growing, so current speed must fall towards zero.
        _ = meter.add(bytes: 200, at: 8)
        let stalled = meter.add(bytes: 200, at: 9)
        XCTAssertLessThan(stalled, 30)
        // A new run (bytes reset) starts over.
        XCTAssertEqual(meter.add(bytes: 0, at: 10), 0)
    }
}
