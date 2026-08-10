@testable import VibeController
import Foundation
import XCTest

final class ControllerInputRelayTests: XCTestCase {
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
        timestamp: Date = Date()
    ) -> ControllerSnapshot {
        ControllerSnapshot(
            isConnected: true,
            controllerName: "Test Controller",
            connectionSummary: "USB",
            batteryLevel: nil,
            batteryStateDescription: nil,
            pressedControls: [],
            analogValues: [.leftThumbstick: abs(x)],
            leftStick: StickSnapshot(x: x, y: 0),
            rightStick: StickSnapshot(),
            lastUpdated: timestamp
        )
    }
}

private final class RelayRecorder: @unchecked Sendable {
    struct Snapshot {
        var realtimeCount: Int
        var realtimeUsedMainThread: Bool
        var telemetryCount: Int
        var latestTelemetryX: Double
        var actionConnections: [Bool]
    }

    private let lock = NSLock()
    private var realtimeCount = 0
    private var realtimeUsedMainThread = false
    private var telemetryCount = 0
    private var latestTelemetryX = 0.0
    private var actionConnections: [Bool] = []

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
            actionConnections: actionConnections
        )
    }
}
