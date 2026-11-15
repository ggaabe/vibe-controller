@testable import VibeController
import Foundation
import XCTest

final class ControllerInputRelayTests: XCTestCase {
    func testWired360ReportsReachRealtimeMotionAndActionsAndDisconnectRestoresFallback() throws {
        let queue = DispatchQueue(label: "test.wired-360-relay")
        let relay = ControllerInputRelay(inputQueue: queue)
        let done = DispatchSemaphore(value: 0)
        // All collection and assertions below run on the serial input queue.
        let captured = Wired360RelayCapture()
        relay.setRealtimeHandler { captured.motion.append($0) }
        relay.setRealtimeActionHandler {
            captured.actions.append($0)
            return true
        }
        relay.receiveGameController(makeSnapshot(x: 0.1))
        var bytes: [UInt8] = [0, 20, 0, 0x22, 0, 255, 0xff, 0x7f] + Array(repeating: 0, count: 12)
        let pressed = try XCTUnwrap(Xbox360USBReportParser.parse(reportID: 0, bytes: bytes))
        relay.setRawUSBConnection(isConnected: true, name: "Xbox 360 Controller", family: .xbox)
        relay.receiveRawUSB(pressed)
        // GC may freeze or report neutral while UC owns the remote pointer.
        // It must not replace ongoing physical USB input.
        relay.receiveGameController(makeSnapshot(x: -0.75))
        bytes[3] = 0
        bytes[5] = 0
        bytes[6] = 0
        bytes[7] = 0
        relay.receiveRawUSB(try XCTUnwrap(Xbox360USBReportParser.parse(reportID: 0, bytes: bytes)))
        relay.setRawUSBConnection(isConnected: false, name: nil)
        queue.async {
            XCTAssertEqual(captured.motion.count, 4)
            guard captured.motion.count == 4 else { done.signal(); return }
            XCTAssertEqual(captured.motion[1].leftStick.x, 1)
            XCTAssertEqual(captured.motion[1].pressedControls, [.rightShoulder, .buttonEast, .rightTrigger])
            XCTAssertEqual(captured.motion[1].controllerName, "Xbox 360 Controller")
            XCTAssertEqual(captured.motion[1].controllerFamily, .xbox)
            XCTAssertEqual(captured.motion[1].connectionSummary, "USB • Direct HID")
            XCTAssertTrue(captured.motion[2].pressedControls.isEmpty)
            XCTAssertEqual(captured.motion.last?.leftStick.x, -0.75)
            XCTAssertEqual(captured.actions.count, 3)
            done.signal()
        }
        XCTAssertEqual(done.wait(timeout: .now() + 2), .success)
        // Keep the relay alive until the ordered assertions have run.
        withExtendedLifetime(relay) {}
    }

    @MainActor
    func testDeclinedNativeActionsAreDeliveredToCompanionHandlerOnce() async {
        let relay = ControllerInputRelay(inputQueue: DispatchQueue(label: "test.companion-routing"))
        let delivered = expectation(description: "companion action")
        var count = 0
        relay.setRealtimeActionHandler { _ in false }
        relay.setActionHandler { _ in
            XCTAssertTrue(Thread.isMainThread)
            count += 1
            delivered.fulfill()
        }
        relay.receiveGameController(makeSnapshot(x: 0, pressed: [.buttonEast]))
        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(count, 1)
    }

    func testSnapshotPayloadComparisonIgnoresTelemetryTimestamp() {
        let first = makeSnapshot(x: 0.25, timestamp: Date(timeIntervalSince1970: 1))
        let second = makeSnapshot(x: 0.25, timestamp: Date(timeIntervalSince1970: 2))

        XCTAssertTrue(first.hasSameInputPayload(as: second))
        XCTAssertFalse(first.hasSameInputPayload(as: makeSnapshot(x: 0.5)))
    }

    @MainActor
    func testRealtimeStreamStaysOffMainAndTelemetryPublishesLatestAtFifteenHertz() async {
        let inputQueue = DispatchQueue(label: "test.controller-input", qos: .userInteractive)
        let relay = ControllerInputRelay(inputQueue: inputQueue)
        let recorder = RelayRecorder()
        let realtimeExpectation = expectation(description: "all realtime samples")
        realtimeExpectation.expectedFulfillmentCount = 60
        let latestTelemetryExpectation = expectation(description: "latest telemetry sample")

        relay.setRealtimeHandler { snapshot in
            recorder.recordRealtime(snapshot, wasMainThread: Thread.isMainThread)
            realtimeExpectation.fulfill()
        }
        relay.setTelemetryHandler { snapshot in
            recorder.recordTelemetry(snapshot)
            if snapshot.leftStick.x == 0.59 {
                latestTelemetryExpectation.fulfill()
            }
        }

        for index in 0..<60 {
            relay.receiveGameController(makeSnapshot(x: Double(index) / 100))
        }

        await fulfillment(of: [realtimeExpectation, latestTelemetryExpectation], timeout: 2)

        let result = recorder.snapshot()
        XCTAssertEqual(result.realtimeCount, 60)
        XCTAssertFalse(result.realtimeUsedMainThread)
        XCTAssertEqual(result.latestTelemetryX, 0.59, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(result.telemetryCount, 4)
    }

    @MainActor
    func testConnectionChangesReachActionStreamEvenWithoutPressedButtons() async {
        let inputQueue = DispatchQueue(label: "test.controller-actions", qos: .userInteractive)
        let relay = ControllerInputRelay(inputQueue: inputQueue)
        let recorder = RelayRecorder()
        let actionExpectation = expectation(description: "connection action transitions")
        actionExpectation.expectedFulfillmentCount = 2

        relay.setActionHandler { snapshot in
            recorder.recordAction(snapshot)
            actionExpectation.fulfill()
        }

        relay.receiveGameController(makeSnapshot(x: 0))
        relay.receiveGameController(.disconnected)

        await fulfillment(of: [actionExpectation], timeout: 2)
        XCTAssertEqual(recorder.snapshot().actionConnections, [true, false])
    }

    @MainActor
    func testZoomThresholdTransitionsReachActionStreamWithoutFloodingIt() async {
        let inputQueue = DispatchQueue(label: "test.controller-zoom-actions", qos: .userInteractive)
        let relay = ControllerInputRelay(inputQueue: inputQueue)
        let recorder = RelayRecorder()
        let actionExpectation = expectation(description: "zoom action transitions")
        actionExpectation.expectedFulfillmentCount = 2

        relay.setActionHandler { snapshot in
            recorder.recordAction(snapshot)
            actionExpectation.fulfill()
        }

        relay.receiveGameController(makeSnapshot(x: 0, y: 0, pressed: [.buttonSouth]))
        relay.receiveGameController(makeSnapshot(x: 0, y: 0.8, pressed: [.buttonSouth]))
        relay.receiveGameController(makeSnapshot(x: 0, y: 0.9, pressed: [.buttonSouth]))

        await fulfillment(of: [actionExpectation], timeout: 2)
        XCTAssertEqual(recorder.snapshot().actionCount, 2)
    }

    @MainActor
    func testMainThreadStallCoalescesTelemetryWithoutDelayingRealtimeInput() {
        let inputQueue = DispatchQueue(label: "test.controller-main-stall", qos: .userInteractive)
        let relay = ControllerInputRelay(inputQueue: inputQueue)
        let recorder = RelayRecorder()
        let realtimeFinished = DispatchSemaphore(value: 0)

        relay.setRealtimeHandler { snapshot in
            recorder.recordRealtime(snapshot, wasMainThread: Thread.isMainThread)
            if snapshot.leftStick.x == 0.99 {
                realtimeFinished.signal()
            }
        }
        relay.setTelemetryHandler { snapshot in
            recorder.recordTelemetry(snapshot)
        }

        for index in 0..<100 {
            relay.receiveGameController(makeSnapshot(x: Double(index) / 100))
        }

        XCTAssertEqual(realtimeFinished.wait(timeout: .now() + 1), .success)
        Thread.sleep(forTimeInterval: 0.12)
        XCTAssertEqual(recorder.snapshot().telemetryCount, 0)

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let result = recorder.snapshot()
        XCTAssertEqual(result.realtimeCount, 100)
        XCTAssertFalse(result.realtimeUsedMainThread)
        XCTAssertEqual(result.telemetryCount, 1)
        XCTAssertEqual(result.latestTelemetryX, 0.99, accuracy: 0.000_001)
    }

    private func makeSnapshot(
        x: Double,
        y: Double = 0,
        pressed: Set<ControllerControlID> = [],
        timestamp: Date = Date()
    ) -> ControllerSnapshot {
        ControllerSnapshot(
            isConnected: true,
            controllerName: "Test Controller",
            connectionSummary: "USB",
            batteryLevel: nil,
            batteryStateDescription: nil,
            pressedControls: pressed,
            analogValues: [.leftThumbstick: abs(x)],
            leftStick: StickSnapshot(x: x, y: y),
            rightStick: StickSnapshot(),
            lastUpdated: timestamp
        )
    }
}

/// Accessed only by a single test input queue.
private final class Wired360RelayCapture: @unchecked Sendable {
    var motion: [ControllerSnapshot] = []
    var actions: [ControllerSnapshot] = []
}

private final class RelayRecorder: @unchecked Sendable {
    struct Snapshot {
        var realtimeCount: Int
        var realtimeUsedMainThread: Bool
        var telemetryCount: Int
        var latestTelemetryX: Double
        var actionConnections: [Bool]
        var actionCount: Int
    }

    private let lock = NSLock()
    private var realtimeCount = 0
    private var realtimeUsedMainThread = false
    private var telemetryCount = 0
    private var latestTelemetryX = 0.0
    private var actionConnections: [Bool] = []
    private var actionCount = 0

    func recordRealtime(_ snapshot: ControllerSnapshot, wasMainThread: Bool) {
        lock.lock()
        realtimeCount += 1
        realtimeUsedMainThread = realtimeUsedMainThread || wasMainThread
        lock.unlock()
    }

    func recordTelemetry(_ snapshot: ControllerSnapshot) {
        lock.lock()
        telemetryCount += 1
        latestTelemetryX = snapshot.leftStick.x
        lock.unlock()
    }

    func recordAction(_ snapshot: ControllerSnapshot) {
        lock.lock()
        actionConnections.append(snapshot.isConnected)
        actionCount += 1
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            realtimeCount: realtimeCount,
            realtimeUsedMainThread: realtimeUsedMainThread,
            telemetryCount: telemetryCount,
            latestTelemetryX: latestTelemetryX,
            actionConnections: actionConnections,
            actionCount: actionCount
        )
    }
}
