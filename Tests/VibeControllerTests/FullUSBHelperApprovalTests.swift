import ServiceManagement
import XCTest
@testable import VibeController

final class FullUSBHelperApprovalTests: XCTestCase {
    func testApprovalIsDistinctFromSessionState() {
        XCTAssertEqual(FullUSBHelperStatus.resolve(.enabled, isPackaged: true), .enabled)
        XCTAssertEqual(FullUSBHelperStatus.resolve(.requiresApproval, isPackaged: true), .requiresApproval)
        XCTAssertEqual(FullUSBHelperStatus.resolve(.notRegistered, isPackaged: true), .notRegistered)
        XCTAssertEqual(FullUSBHelperStatus.resolve(.notFound, isPackaged: true), .notRegistered)
        for status in [SMAppService.Status.enabled, .requiresApproval, .notRegistered, .notFound] {
            XCTAssertEqual(FullUSBHelperStatus.resolve(status, isPackaged: false), .unavailable)
        }
    }

    func testSetupActionsDoNotMislabelPendingApprovalAsActiveUSB() {
        XCTAssertEqual(FullUSBHelperStatus.notRegistered.buttonTitle, "Set up Full USB")
        XCTAssertEqual(FullUSBHelperStatus.requiresApproval.buttonTitle, "Open Approval Settings")
        XCTAssertEqual(FullUSBHelperStatus.enabled.buttonTitle, "Enable full USB")
        XCTAssertTrue(FullUSBHelperStatus.notRegistered.detail.contains("once"))
        XCTAssertTrue(FullUSBHelperStatus.enabled.detail.contains("revoke"))
    }

    func testCleanupCannotHideTheOriginalStartupFailure() {
        var outcome = FullUSBSessionOutcome()
        outcome.receive(kind: 3, message: "USB claim failed: LIBUSB_ERROR_BUSY (-6)")
        outcome.receive(kind: 4, message: "USB released.")
        XCTAssertEqual(outcome.ending(with: "Connection closed"),
            "USB claim failed: LIBUSB_ERROR_BUSY (-6) USB released.")
    }

    func testCleanupErrorsKeepTheOriginalFailureAndNewAttemptsStartClean() {
        var outcome = FullUSBSessionOutcome()
        outcome.receive(kind: 3, message: "Capture failed")
        outcome.receive(kind: 3, message: "Reconnect to restore the driver")
        XCTAssertEqual(outcome.message, "Capture failed Reconnect to restore the driver")
        XCTAssertEqual(FullUSBSessionOutcome().ending(with: "Stopped"), "Stopped")
    }
}
