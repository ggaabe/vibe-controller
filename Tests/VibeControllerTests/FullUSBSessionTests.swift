import Foundation
import XCTest
@testable import VibeController

final class FullUSBWireTests: XCTestCase {
    private func frame(_ kind: UInt8, _ payload: [UInt8] = []) -> [UInt8] {
        [kind, UInt8(payload.count), 0, 0, 0, 0, 0, 0] + payload + Array(repeating: 0, count: 64 - payload.count)
    }

    func testFragmentedAndCoalescedFramesAreLossless() throws {
        let input = frame(1) + frame(2, [0x20, 0, 1, 44]) + frame(5) + frame(4, Array("Released".utf8))
        for chunkSize in 1...input.count {
            var decoder = FullUSBWire.Decoder()
            var output: [FullUSBWire.Frame] = []
            for start in stride(from: 0, to: input.count, by: chunkSize) {
                output += try decoder.append(Array(input[start..<min(start + chunkSize, input.count)]))
            }
            XCTAssertEqual(output.map(\.kind), [1, 2, 5, 4])
            XCTAssertEqual(output[1].payload, [0x20, 0, 1, 44])
            XCTAssertEqual(output[3].payload, Array("Released".utf8))
        }
    }

    func testMalformedFramesFailClosed() {
        var malformed = [frame(0), frame(6), frame(2), frame(1, [1]), frame(5, [1])]
        var overlong = frame(2, [1]); overlong[1] = 65; malformed.append(overlong)
        var reserved = frame(2, [1]); reserved[2] = 1; malformed.append(reserved)
        var padding = frame(2, [1]); padding[71] = 1; malformed.append(padding)
        for bytes in malformed {
            var decoder = FullUSBWire.Decoder()
            XCTAssertThrowsError(try decoder.append(bytes))
        }
    }

    func testOversizedReadIsRejectedInsteadOfGrowingAnUnboundedQueue() {
        var decoder = FullUSBWire.Decoder()
        XCTAssertThrowsError(try decoder.append(Array(repeating: 0, count: 4097)))
    }

    func testRumbleProtocolContainsOnlyFiniteMotorValuesAndNoNativeOpcode() {
        XCTAssertEqual(FullUSBWire.rumble(left: 0.5, right: 0.25, duration: 0.1), [1, 50, 25, 10, 0, 0, 0, 0])
        XCTAssertEqual(FullUSBWire.rumble(left: 100, right: -1, duration: 100), [1, 100, 0, 100, 0, 0, 0, 0])
        XCTAssertEqual(FullUSBWire.rumble(left: .nan, right: .infinity, duration: 1), [1, 0, 0, 0, 0, 0, 0, 0])
    }
}

final class FullUSBInputPriorityTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        let lock = NSLock()
        var values: [ControllerSnapshot] = []
        func append(_ snapshot: ControllerSnapshot) { lock.withLock { values.append(snapshot) } }
        var snapshots: [ControllerSnapshot] { lock.withLock { values } }
    }

    func testShareRequirementReachesTheUIAndClearsWithFullReports() {
        let queue = DispatchQueue(label: "test.share-setup-transport")
        let relay = ControllerInputRelay(inputQueue: queue)
        let recorded = Recorder()
        relay.setRealtimeHandler { recorded.append($0) }
        relay.receiveRawUSB(XboxUSBInputState(shareRequiresFullUSB: true))
        queue.sync {}
        XCTAssertTrue(recorded.snapshots.last!.shareRequiresFullUSB)
        relay.receiveRawUSB(XboxUSBInputState()) // Same buttons, complete report.
        queue.sync {}
        XCTAssertFalse(recorded.snapshots.last!.shareRequiresFullUSB)
        XCTAssertEqual(recorded.snapshots.count, 2)
        relay.setFullUSBActive(true)
        relay.receiveFullUSB(XboxUSBInputState())
        queue.sync {}
        XCTAssertFalse(recorded.snapshots.last!.shareRequiresFullUSB)
    }

    func testLateAppleCallbacksCannotOverrideFullUSBShareOrHeldInputs() {
        let queue = DispatchQueue(label: "test.full-usb-priority")
        let relay = ControllerInputRelay(inputQueue: queue)
        let recorded = Recorder()
        relay.setRealtimeHandler { recorded.append($0) }
        relay.setFullUSBActive(true)
        var share = XboxUSBInputState()
        share.pressedControls = [.share]
        share.leftStick.x = 0.8
        relay.receiveFullUSB(share)
        relay.setRawUSBConnection(isConnected: false, name: nil)
        relay.receiveGameController(.disconnected)
        relay.receiveRawUSB(XboxUSBInputState())
        relay.setRawUSBConnection(isConnected: true, name: "Old Apple callback", family: .xbox)
        queue.sync {}
        XCTAssertEqual(recorded.snapshots.count, 2)
        XCTAssertEqual(recorded.snapshots.last?.pressedControls, [.share])
        XCTAssertEqual(recorded.snapshots.last?.leftStick.x, 0.8)
        XCTAssertEqual(recorded.snapshots.last?.connectionSummary, "USB • Full input")
    }

    func testExitReleasesControlsAndRequiresFreshFallbackInput() {
        let queue = DispatchQueue(label: "test.full-usb-release")
        let relay = ControllerInputRelay(inputQueue: queue)
        let recorded = Recorder()
        relay.setRealtimeHandler { recorded.append($0) }
        relay.setFullUSBActive(true)
        var held = XboxUSBInputState(); held.pressedControls = [.leftTrigger, .buttonSouth]
        relay.receiveFullUSB(held)
        relay.clearFullUSBInput()
        relay.setFullUSBActive(false)
        relay.receiveFullUSB(held) // Already queued/in-flight before close.
        queue.sync {}
        XCTAssertFalse(recorded.snapshots.last!.isConnected)
        XCTAssertTrue(recorded.snapshots.last!.pressedControls.isEmpty)
        relay.receiveRawUSB(XboxUSBInputState())
        queue.sync {}
        XCTAssertTrue(recorded.snapshots.last!.isConnected)
        XCTAssertEqual(recorded.snapshots.last?.connectionSummary, "USB • Direct HID")
        XCTAssertTrue(recorded.snapshots.last!.pressedControls.isEmpty)
    }
}
