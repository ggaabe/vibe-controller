import FullUSBServiceClient
import XCTest
@testable import VibeController

final class FullUSBAvailabilityTests: XCTestCase {
    func testOnlyTheExplicitDevelopmentIdentityEnablesFullUSB() {
        XCTAssertTrue(FullUSBAvailability.isAvailable(bundleIdentifier: "com.vibe-controller.app.dev"))
        for identifier: String? in [nil, "", "com.vibe-controller.app", "com.vibe-controller.app.beta",
                                    "com.vibe-controller.app.dev.copy"] {
            XCTAssertFalse(FullUSBAvailability.isAvailable(bundleIdentifier: identifier))
        }
    }

    func testNonDevelopmentXPCClientRejectsBeforeConnectingToAHelper() {
        XCTAssertFalse(FullUSBAvailability.isAvailable)
        var replied = false
        VibeUSBRequestSession("com.vibe-controller.app.usb-service") { fd, message in
            replied = true
            XCTAssertEqual(fd, -1)
            XCTAssertTrue(String(cString: message!).contains("Vibe Controller Dev"))
        }
        XCTAssertTrue(replied)
    }

    func testNonDevelopmentWorkerRejectsBeforeRequestingUSB() {
        XCTAssertFalse(FullUSBAvailability.isAvailable)
        let ended = expectation(description: "Development gate")
        let worker = FullUSBWorker()
        worker.onReady = { XCTFail("Must not open a USB session") }
        worker.onEnded = { message in
            XCTAssertEqual(message, FullUSBAvailability.unavailableMessage)
            ended.fulfill()
        }
        worker.start(serviceName: "com.vibe-controller.app.usb-service")
        wait(for: [ended], timeout: 2)
    }
}

@MainActor
final class FullUSBSessionAvailabilityTests: XCTestCase {
    func testUnavailableSessionNeverRequestsApprovalOrCapturesInput() async {
        let relay = ControllerInputRelay(inputQueue: DispatchQueue(label: "test.public-usb-gate"))
        let output = ControllerHapticOutput(usbTransportFactory: { _ in nil })
        let session = FullUSBSession(relay: relay, output: output)
        XCTAssertFalse(session.isAvailable)
        session.start()
        session.openHelperSettings() // Must be a no-op, not System Settings.
        await session.removeHelperApproval()
        XCTAssertFalse(session.isEnabled)
        XCTAssertFalse(session.isReady)
        XCTAssertFalse(session.hasAttemptedSession)
        XCTAssertEqual(session.helperStatus, .unavailable)
        XCTAssertEqual(session.message, FullUSBAvailability.unavailableMessage)
    }
}
