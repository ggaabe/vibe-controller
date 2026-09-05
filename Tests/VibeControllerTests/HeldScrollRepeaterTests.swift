import Foundation
import XCTest
@testable import VibeController

@MainActor
final class HeldScrollRepeaterTests: XCTestCase {
    func testAllScrollDirectionsRepeatWhileTheMainThreadIsBusy() {
        let directions: [(ActionType, Int32, Int32)] = [
            (.scrollUp, -1, 0), (.scrollDown, 1, 0),
            (.scrollLeft, 0, -1), (.scrollRight, 0, 1),
        ]
        for (action, vertical, horizontal) in directions {
            let recorder = ScrollRecorder()
            let engine = makeEngine(recorder)
            let profile = profile(action: action, delay: 0.05, interval: 0.04)
            engine.process(snapshot: snapshot([.dpadUp]), profile: profile)
            // Deliberately block the UI executor, as a slow layout/menu can.
            // A DispatchSource on .main cannot deliver a single repeat here.
            Thread.sleep(forTimeInterval: 0.35)
            engine.cancelAll()

            let samples = recorder.samples
            XCTAssertGreaterThanOrEqual(samples.count, 6, "\(action) stalled behind the UI")
            XCTAssertLessThanOrEqual(samples.count, 10, "Repeated faster than configured")
            XCTAssertTrue(samples.allSatisfy { $0.vertical == vertical && $0.horizontal == horizontal })
        }
    }

    func testTapIsImmediateThenRepeatsAtTheSavedDelayAndInterval() {
        let recorder = ScrollRecorder()
        let engine = makeEngine(recorder)
        let profile = profile(action: .scrollDown, delay: 0.25, interval: 0.04)
        engine.process(snapshot: snapshot([.dpadUp]), profile: profile)
        XCTAssertEqual(recorder.samples.count, 1)
        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertEqual(recorder.samples.count, 1, "Tap must not prematurely become a hold")
        Thread.sleep(forTimeInterval: 0.4)
        engine.process(snapshot: snapshot([]), profile: profile)

        let samples = recorder.samples
        XCTAssertGreaterThanOrEqual(samples.count, 6)
        if samples.count > 1 {
            XCTAssertGreaterThanOrEqual(samples[1].time - samples[0].time, 0.23)
            let repeatGaps = zip(samples.dropFirst(), samples.dropFirst(2)).map { $1.time - $0.time }
            XCTAssertTrue(repeatGaps.allSatisfy { $0 < 0.15 }, "Expected continuous repeats, not one-second pulses")
        }
        Thread.sleep(forTimeInterval: 0.12)
        XCTAssertEqual(recorder.samples.count, samples.count, "Release must stop scrolling")
    }

    func testUnchangedHeldSnapshotsDoNotRestartTheInitialDelay() {
        let recorder = ScrollRecorder()
        let engine = makeEngine(recorder)
        let profile = profile(action: .scrollUp, delay: 0.05, interval: 0.04)
        for _ in 0..<15 {
            engine.process(snapshot: snapshot([.dpadUp]), profile: profile)
            Thread.sleep(forTimeInterval: 0.02)
        }
        engine.cancelAll()
        XCTAssertGreaterThanOrEqual(recorder.samples.count, 5)
        XCTAssertLessThan(recorder.samples.count, 12)
    }

    func testRealtimeReleaseAndDisconnectStopScrollingWithoutWaitingForTheUI() {
        for disconnected in [false, true] {
            let recorder = ScrollRecorder()
            let engine = makeEngine(recorder)
            let profile = profile(action: .scrollUp, delay: 0.02, interval: 0.02)
            engine.updateRealtimeInput(snapshot: snapshot([.dpadUp]))
            engine.process(snapshot: snapshot([.dpadUp]), profile: profile)
            Thread.sleep(forTimeInterval: 0.1)
            XCTAssertGreaterThan(recorder.samples.count, 2)

            engine.updateRealtimeInput(snapshot: disconnected ? .disconnected : snapshot([]))
            Thread.sleep(forTimeInterval: 0.04)
            let stoppedCount = recorder.samples.count
            Thread.sleep(forTimeInterval: 0.12)
            XCTAssertEqual(recorder.samples.count, stoppedCount)
            engine.cancelAll()
        }
    }

    func testRealtimeModifierReleaseStopsItsScrollOverride() {
        let recorder = ScrollRecorder()
        let engine = makeEngine(recorder)
        var profile = ControllerProfile.gabesDefaults
        profile.modifierLayers = [ControllerModifierLayer(
            modifierControl: .leftShoulder,
            mappings: [.dpadUp: ControllerActionMapping(
                actionType: .scrollUp, triggerMode: .repeatWhileHeld,
                repeatDelay: 0.02, repeatInterval: 0.02
            )]
        )]
        engine.updateRealtimeInput(snapshot: snapshot([.leftShoulder, .dpadUp]))
        engine.process(snapshot: snapshot([.leftShoulder, .dpadUp]), profile: profile)
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertGreaterThan(recorder.samples.count, 2)
        engine.updateRealtimeInput(snapshot: snapshot([.dpadUp]))
        Thread.sleep(forTimeInterval: 0.04)
        let stoppedCount = recorder.samples.count
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(recorder.samples.count, stoppedCount)
        engine.cancelAll()
    }

    func testQueuedOldPressDoesNotRestartScrollingAfterRealtimeRelease() {
        let recorder = ScrollRecorder()
        let engine = makeEngine(recorder)
        engine.updateRealtimeInput(snapshot: snapshot([]))
        engine.process(snapshot: snapshot([.dpadUp]), profile: profile(action: .scrollUp))
        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertEqual(recorder.samples.count, 1, "Only the original discrete tap is owed")
        engine.cancelAll()
    }

    func testDisablingPermissionLossRecordingAndRoutingChangesCancelRepeats() {
        let stopActions: [(ActionEngine) -> Void] = [
            { $0.isEnabled = false },
            { $0.accessibilityTrusted = false },
            { $0.suspendActionExecution = true },
            { $0.allowsBackgroundScrollRepeats = false },
            { $0.cancelAll() },
        ]
        for stop in stopActions {
            let recorder = ScrollRecorder()
            let engine = makeEngine(recorder)
            engine.process(snapshot: snapshot([.dpadUp]), profile: profile(action: .scrollUp))
            Thread.sleep(forTimeInterval: 0.08)
            stop(engine)
            let count = recorder.samples.count
            Thread.sleep(forTimeInterval: 0.08)
            XCTAssertEqual(recorder.samples.count, count)
        }
    }

    func testCompanionRepeatsKeepUsingDynamicRoutingAndDoNotDoubleFire() async throws {
        let recorder = ScrollRecorder()
        let engine = makeEngine(recorder)
        engine.allowsBackgroundScrollRepeats = false
        var forwarded = 0
        engine.companionDispatch = { event in
            guard case .scroll = event.payload else { return false }
            forwarded += 1
            return true
        }
        let profile = profile(action: .scrollDown, delay: 0.05, interval: 0.04)
        engine.process(snapshot: snapshot([.dpadUp]), profile: profile)
        XCTAssertEqual(forwarded, 1)
        try await Task.sleep(for: .milliseconds(250))
        engine.process(snapshot: snapshot([]), profile: profile)
        XCTAssertGreaterThanOrEqual(forwarded, 4)
        XCTAssertTrue(recorder.samples.isEmpty, "Companion reports must not also scroll locally")
        let stoppedCount = forwarded
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(forwarded, stoppedCount)
    }

    private func makeEngine(_ recorder: ScrollRecorder) -> ActionEngine {
        let engine = ActionEngine(cursorEngine: CursorEngine(), scrollOutput: { recorder.record($0, $1) })
        engine.accessibilityTrusted = true
        return engine
    }

    private func profile(action: ActionType, delay: Double = 0.02, interval: Double = 0.02) -> ControllerProfile {
        var profile = ControllerProfile.gabesDefaults
        profile.mappings[.dpadUp] = ControllerActionMapping(
            actionType: action, triggerMode: .repeatWhileHeld,
            repeatDelay: delay, repeatInterval: interval
        )
        return profile
    }

    private func snapshot(_ controls: Set<ControllerControlID>) -> ControllerSnapshot {
        var snapshot = ControllerSnapshot.disconnected
        snapshot.isConnected = true
        snapshot.pressedControls = controls
        return snapshot
    }
}

private final class ScrollRecorder: @unchecked Sendable {
    struct Sample {
        var time: TimeInterval
        var vertical: Int32
        var horizontal: Int32
    }
    private let lock = NSLock()
    private var storage: [Sample] = []
    var samples: [Sample] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
    func record(_ vertical: Int32, _ horizontal: Int32) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(Sample(time: ProcessInfo.processInfo.systemUptime, vertical: vertical, horizontal: horizontal))
    }
}
