import CoreGraphics
import Foundation
import XCTest
@testable import VibeController

@MainActor
final class CursorMotionLoopTests: XCTestCase {
    func testSteadyStickKeepsProducingMotionWhileMainThreadIsBusy() {
        let output = MotionRecorder()
        let loop = makeLoop(output)
        defer { loop.stop() }
        loop.updateInput(snapshot: input(left: StickSnapshot(x: 0.7, y: 0.7)))
        // Hold one sample: neither fresh USB reports nor UI turns may be
        // necessary to sustain movement. Output goes only to our recorder.
        Thread.sleep(forTimeInterval: 0.4)
        let samples = output.samples
        XCTAssertGreaterThan(samples.count, 20)
        let duration = (samples.last?.time ?? 0) - (samples.first?.time ?? 0)
        XCTAssertGreaterThan(Double(samples.count - 1) / max(0.001, duration), 80)
        XCTAssertTrue(samples.allSatisfy { $0.delta.x > 0 && $0.delta.y < 0 })
        XCTAssertEqual(output.activityStarts, 1)
        XCTAssertEqual(output.activityEnds, 0)
        loop.updateInput(snapshot: input())
        Thread.sleep(forTimeInterval: 0.08)
        XCTAssertEqual(output.activityEnds, 1)
        let count = output.samples.count
        Thread.sleep(forTimeInterval: 0.06)
        XCTAssertEqual(output.samples.count, count)
    }

    func testPrecisionStickAlsoKeepsMotionResponsive() {
        let output = MotionRecorder()
        let loop = makeLoop(output)
        loop.updateInput(snapshot: input(right: StickSnapshot(x: -1)))
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(output.activityStarts, 1)
        XCTAssertTrue(output.samples.allSatisfy { $0.delta.x < 0 })
        XCTAssertGreaterThan(output.samples.count, 3)
        loop.stop()
        XCTAssertEqual(output.activityEnds, 1)
    }

    func testDeadZoneAndUnassignedSticksDoNotAcquireAnActivity() {
        let output = MotionRecorder()
        let loop = makeLoop(output)
        defer { loop.stop() }
        loop.updateInput(snapshot: input(left: StickSnapshot(x: 0.02, y: -0.02)))
        Thread.sleep(forTimeInterval: 0.04)
        var config = configuration()
        config.primaryStick = .off
        config.precisionStick = .off
        loop.updateConfiguration(config)
        loop.updateInput(snapshot: input(left: StickSnapshot(x: 1), right: StickSnapshot(y: 1)))
        Thread.sleep(forTimeInterval: 0.04)
        XCTAssertEqual(output.activityStarts, 0)
        XCTAssertTrue(output.samples.isEmpty)
    }

    func testDisablePermissionLossSuspendDisconnectAndReleaseEndActivity() {
        let stops: [(CursorMotionLoop) -> Void] = [
            { $0.setEnabled(false) },
            { $0.setAccessibilityTrusted(false) },
            { $0.setSuspended(true) },
            { $0.updateInput(snapshot: .disconnected) },
            { $0.releaseTransientState() },
            { $0.stop() },
        ]
        for stop in stops {
            let output = MotionRecorder()
            let loop = makeLoop(output)
            loop.updateInput(snapshot: input(left: StickSnapshot(x: 1)))
            Thread.sleep(forTimeInterval: 0.05)
            XCTAssertEqual(output.activityStarts, 1)
            stop(loop)
            Thread.sleep(forTimeInterval: 0.04)
            XCTAssertEqual(output.activityEnds, 1)
            let count = output.samples.count
            Thread.sleep(forTimeInterval: 0.04)
            XCTAssertEqual(output.samples.count, count)
            loop.stop()
            XCTAssertEqual(output.activityEnds, 1, "Activity must end exactly once")
        }
    }

    func testCrossEdgeAndDiagnosticMotionAcquireAndReleaseActivity() {
        for diagnostic in [false, true] {
            let output = MotionRecorder()
            let loop = makeLoop(output)
            if diagnostic { _ = loop.performDiagnosticNudge() }
            else { _ = loop.performCrossEdgeSweep(.right) }
            Thread.sleep(forTimeInterval: 0.05)
            XCTAssertEqual(output.activityStarts, 1)
            XCTAssertGreaterThan(output.samples.count, 0)
            loop.setEnabled(false)
            Thread.sleep(forTimeInterval: 0.05)
            let count = output.samples.count
            Thread.sleep(forTimeInterval: 0.05)
            XCTAssertEqual(output.samples.count, count)
            XCTAssertEqual(output.activityEnds, 1)
            loop.stop()
        }
    }

    func testStoppedLoopCannotReacquireActivityFromQueuedInput() {
        let output = MotionRecorder()
        let loop = makeLoop(output)
        loop.stop()
        loop.updateInput(snapshot: input(left: StickSnapshot(x: 1)))
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(output.activityStarts, 0)
        XCTAssertTrue(output.samples.isEmpty)
    }

    private func configuration() -> CursorConfiguration {
        var config = ControllerProfile.gabesDefaults.cursor
        config.smoothing = 0
        config.flickBoostEnabled = false
        config.zoomGestureEnabled = false
        return config
    }

    private func makeLoop(_ output: MotionRecorder) -> CursorMotionLoop {
        let activity = CursorMotionActivity(begin: {
            output.beganActivity()
            return NSObject()
        }, end: { _ in output.endedActivity() })
        let loop = CursorMotionLoop(inputBridge: output, motionActivity: activity)
        loop.updateConfiguration(configuration())
        loop.setAccessibilityTrusted(true)
        return loop
    }

    private func input(left: StickSnapshot = StickSnapshot(), right: StickSnapshot = StickSnapshot()) -> ControllerSnapshot {
        var snapshot = ControllerSnapshot.disconnected
        snapshot.isConnected = true
        snapshot.leftStick = left
        snapshot.rightStick = right
        return snapshot
    }
}

private final class MotionRecorder: CursorPointerOutput, @unchecked Sendable {
    struct Sample { var time: TimeInterval; var delta: SIMD2<Double> }
    private let lock = NSLock()
    private var recorded: [Sample] = []
    private var starts = 0
    private var ends = 0
    var isVirtualPointingReady: Bool { true }
    var samples: [Sample] { lock.withLock { recorded } }
    var activityStarts: Int { lock.withLock { starts } }
    var activityEnds: Int { lock.withLock { ends } }
    func beganActivity() { lock.withLock { starts += 1 } }
    func endedActivity() { lock.withLock { ends += 1 } }
    func postRelativePointer(delta: SIMD2<Double>) -> Bool {
        lock.withLock { recorded.append(Sample(time: ProcessInfo.processInfo.systemUptime, delta: delta)) }
        return true
    }
    func postVirtualRelativePointer(delta: SIMD2<Double>) -> Bool { postRelativePointer(delta: delta) }
    func postMouseButton(_ button: CGMouseButton, isDown: Bool, clickCount: Int) -> Bool { true }
}
