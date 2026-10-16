import Foundation
import XCTest
@testable import VibeController

final class CursorMotionActivityTests: XCTestCase {
    func testActivityIsBalancedAndDoesNotPreventSleep() {
        var begins = 0
        var ends = 0
        var activity: CursorMotionActivity? = CursorMotionActivity(begin: {
            begins += 1
            return NSObject()
        }, end: { _ in ends += 1 })
        activity?.setActive(false)
        XCTAssertEqual(begins, 0)
        activity?.setActive(true)
        activity?.setActive(true)
        XCTAssertEqual(begins, 1)
        activity?.setActive(false)
        activity?.setActive(false)
        XCTAssertEqual(ends, 1)
        activity?.setActive(true)
        activity = nil
        XCTAssertEqual(begins, 2)
        XCTAssertEqual(ends, 2)
        XCTAssertTrue(CursorMotionActivity.options.contains(.latencyCritical))
        XCTAssertTrue(CursorMotionActivity.options.contains(.userInitiatedAllowingIdleSystemSleep))
        XCTAssertFalse(CursorMotionActivity.options.contains(.idleSystemSleepDisabled))
        XCTAssertFalse(CursorMotionActivity.options.contains(.idleDisplaySleepDisabled))
    }

    func testCadenceMeasuresOutputAndExcludesIdleTime() throws {
        var cadence = CursorOutputCadence()
        var report: CursorOutputCadence.Report?
        for index in 0...240 { report = cadence.record(at: Double(index) / 120) ?? report }
        let normal = try XCTUnwrap(report)
        XCTAssertEqual(normal.frequency, 120, accuracy: 0.001)
        XCTAssertEqual(normal.longestGap, 1.0 / 120, accuracy: 0.001)
        XCTAssertEqual(normal.lateIntervals, 0)
        cadence.reset()
        XCTAssertNil(cadence.record(at: 200), "Idle time is not a dropped frame")
        let delayed = try XCTUnwrap(cadence.record(at: 202))
        XCTAssertEqual(delayed.longestGap, 2)
        XCTAssertEqual(delayed.lateIntervals, 1)
    }
}
