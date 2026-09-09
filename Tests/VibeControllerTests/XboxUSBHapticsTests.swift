import Foundation
@preconcurrency import GameController
import XCTest
@testable import VibeController

final class XboxUSBRumbleReportTests: XCTestCase {
    func testUsesAppleHIDEnvelopeWithNativeGIPCommandAndFiniteDuration() {
        // Apple's HID report ID is separate from the native command byte.
        XCTAssertEqual(XboxUSBRumbleReport.hidReportID, 1)
        XCTAssertEqual(XboxUSBRumbleReport.make(left: 0.8, right: 0.4, duration: 0.5, sequence: 7),
                       [0x09, 0, 7, 0x09, 0, 0x0f, 0, 0, 80, 40, 50, 0, 0])
    }

    func testClampsMagnitudeAndDurationAndNeverEnablesRepeat() {
        let packet = XboxUSBRumbleReport.make(left: 4, right: -1, duration: 20, sequence: 255)
        XCTAssertEqual(packet.count, 13)
        XCTAssertEqual(Array(packet[8...]), [100, 0, 100, 0, 0])
        XCTAssertEqual(XboxUSBRumbleReport.make(left: 0.55, right: 0, duration: 0.075, sequence: 1)[10], 8)
    }

    func testInvalidValuesAndZeroDurationStopBothMotors() {
        for duration in [Double.nan, .infinity, -.infinity, -1, 0] {
            let packet = XboxUSBRumbleReport.make(left: 1, right: 1, duration: duration, sequence: 3)
            XCTAssertEqual(Array(packet[8...]), [0, 0, 0, 0, 0])
        }
        for invalid in [Double.nan, .infinity, -.infinity] {
            let packet = XboxUSBRumbleReport.make(left: invalid, right: invalid, duration: 0.5, sequence: 3)
            XCTAssertEqual(Array(packet[8...]), [0, 0, 0, 0, 0])
        }
    }
}

final class XboxUSBHapticOutputTests: XCTestCase {
    private final class Transport: USBHapticsTransport, @unchecked Sendable {
        struct Pulse {
            let locality: ControllerVibration.Locality
            let strength: Float
        }
        private let lock = NSLock()
        private var recorded: [Pulse] = []
        private var stopCount = 0
        var pulses: [Pulse] { lock.withLock { recorded } }
        var stops: Int { lock.withLock { stopCount } }
        var didPlay: (@Sendable () -> Void)?
        var failWrites = false

        func play(_ pulse: ControllerVibration.Pulse, locality: ControllerVibration.Locality, strength: Float) throws {
            if failWrites { throw NSError(domain: "USBTest", code: 1) }
            lock.withLock { recorded.append(Pulse(locality: locality, strength: strength)) }
            didPlay?()
        }
        func stop() { lock.withLock { stopCount += 1 } }
    }

    private func attach(_ output: ControllerHapticOutput, enabled: Bool = true) async {
        let ready = expectation(description: "USB transport selected")
        output.onStatus = { if $0 == .availableUSB { ready.fulfill() } }
        output.configure(enabled: enabled, strength: 0.5, connectionFeedback: false)
        // Virtual controller + injected output: never touch real hardware in tests.
        output.attach(GCController.withExtendedGamepad())
        await fulfillment(of: [ready], timeout: 1)
        output.onStatus = nil
    }

    func testDoubleTapPlaysBothPulsesAndExplicitlyStops() async throws {
        let transport = Transport()
        let output = ControllerHapticOutput(usbTransportFactory: { _ in transport })
        await attach(output)
        let played = expectation(description: "Both pulses")
        played.expectedFulfillmentCount = 2
        transport.didPlay = { played.fulfill() }
        output.play(.doubleTap, phase: .press)
        await fulfillment(of: [played], timeout: 1)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(transport.pulses.count, 2)
        XCTAssertGreaterThanOrEqual(transport.stops, 2) // Replaces previous output and stops at end.
        XCTAssertEqual(transport.pulses.first?.strength, 0.5)
    }

    func testMuteAndDisconnectCancelSecondPulse() async throws {
        for disconnect in [false, true] {
            let transport = Transport()
            let output = ControllerHapticOutput(usbTransportFactory: { _ in transport })
            await attach(output)
            let played = expectation(description: "First pulse")
            transport.didPlay = { played.fulfill() }
            output.play(.doubleTap, phase: .press)
            await fulfillment(of: [played], timeout: 1)
            if disconnect { output.attach(nil) }
            else { output.configure(enabled: false, strength: 0.5, connectionFeedback: false) }
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(transport.pulses.count, 1)
            XCTAssertGreaterThanOrEqual(transport.stops, 2)
        }
    }

    func testMutedOutputDoesNotPlayAndDirectionIsPreservedWhenEnabled() async throws {
        let transport = Transport()
        let output = ControllerHapticOutput(usbTransportFactory: { _ in transport })
        await attach(output, enabled: false)
        output.play(.thump, phase: .press)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(transport.pulses.isEmpty)
        let played = expectation(description: "Left handle")
        transport.didPlay = { played.fulfill() }
        output.configure(enabled: true, strength: 0.8, connectionFeedback: false)
        output.play(.leftPulse, phase: .press)
        await fulfillment(of: [played], timeout: 1)
        XCTAssertEqual(transport.pulses.first?.locality, .left)
        XCTAssertEqual(transport.pulses.first?.strength, 0.8)
        output.stop()
    }

    func testWriteFailureIsReportedAndDoesNotScheduleMorePulses() async throws {
        let transport = Transport()
        transport.failWrites = true
        let output = ControllerHapticOutput(usbTransportFactory: { _ in transport })
        await attach(output)
        let failed = expectation(description: "Write failure surfaced")
        output.onStatus = { if case .failed = $0 { failed.fulfill() } }
        output.play(.doubleTap, phase: .press)
        await fulfillment(of: [failed], timeout: 1)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(transport.pulses.isEmpty)
        XCTAssertGreaterThanOrEqual(transport.stops, 2)
    }

    func testFullUSBPlaysWithoutGameControllerAndIgnoresAppleDisconnect() async throws {
        let transport = Transport()
        let output = ControllerHapticOutput(usbTransportFactory: { _ in XCTFail("Must not open Apple's transport during capture"); return nil })
        output.configure(enabled: true, strength: 0.5, connectionFeedback: false)
        let prepared = expectation(description: "Apple transport closed")
        output.beginFullUSB { prepared.fulfill() }
        await fulfillment(of: [prepared], timeout: 1)
        output.installFullUSBTransport(transport)
        output.attach(GCController.withExtendedGamepad())
        output.attach(nil)
        let pulses = expectation(description: "Full USB two pulses")
        pulses.expectedFulfillmentCount = 2
        transport.didPlay = { pulses.fulfill() }
        output.play(.doubleTap, phase: .press)
        await fulfillment(of: [pulses], timeout: 1)
        XCTAssertEqual(transport.pulses.count, 2)
        output.endFullUSB()
    }

    func testFullUSBExitCancelsDelayedRumbleAndCanRestoreAppleOutput() async throws {
        let captured = Transport(), apple = Transport()
        let output = ControllerHapticOutput(usbTransportFactory: { _ in apple })
        output.configure(enabled: true, strength: 0.5, connectionFeedback: false)
        let prepared = expectation(description: "Capture prepared")
        output.beginFullUSB { prepared.fulfill() }
        await fulfillment(of: [prepared], timeout: 1)
        output.installFullUSBTransport(captured)
        let first = expectation(description: "First captured pulse")
        captured.didPlay = { first.fulfill() }
        output.play(.doubleTap, phase: .press)
        await fulfillment(of: [first], timeout: 1)
        output.endFullUSB()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(captured.pulses.count, 1)
        XCTAssertGreaterThan(captured.stops, 0)
        await attach(output)
        let restored = expectation(description: "Fresh Apple transport")
        apple.didPlay = { restored.fulfill() }
        output.play(.softTap, phase: .press)
        await fulfillment(of: [restored], timeout: 1)
        output.stop()
    }
}
