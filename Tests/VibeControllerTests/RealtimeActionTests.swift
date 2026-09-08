import Foundation
import XCTest
@testable import VibeController

@MainActor
final class RealtimeActionTests: XCTestCase {
    func testShareShortcutAndModifierOverrideExecuteOncePerPress() {
        let recorder = ShortcutRecorder()
        let finished = DispatchSemaphore(value: 0)
        let engine = ActionEngine(cursorEngine: CursorEngine(), shortcutOutput: { shortcut, down in
            recorder.record(shortcut, down: down)
            if !down { finished.signal() }
        })
        defer { engine.cancelAll() }
        engine.accessibilityTrusted = true
        var profile = ControllerProfile.gabesDefaults
        profile.mappings[.share] = ControllerActionMapping(
            actionType: .keyboardShortcut, shortcut: ShortcutDescriptor(keyCode: 8, modifiers: [.command]), triggerMode: .tap)
        let rb = profile.modifierLayers.firstIndex { $0.modifierControl == .rightShoulder }!
        profile.modifierLayers[rb].mappings[.share] = ControllerActionMapping(
            actionType: .keyboardShortcut, shortcut: ShortcutDescriptor(keyCode: 9, modifiers: [.control]), triggerMode: .tap)
        engine.configureRealtimeActions(profile: profile, applicationBundleIdentifier: nil, enabled: true)
        XCTAssertTrue(engine.receiveRealtimeActions(snapshot([.share])))
        XCTAssertTrue(engine.receiveRealtimeActions(snapshot([.share])))
        XCTAssertTrue(engine.receiveRealtimeActions(snapshot([])))
        XCTAssertEqual(finished.wait(timeout: .now() + 0.5), .success)
        XCTAssertTrue(engine.receiveRealtimeActions(snapshot([.rightShoulder, .share])))
        XCTAssertTrue(engine.receiveRealtimeActions(snapshot([])))
        XCTAssertEqual(finished.wait(timeout: .now() + 0.5), .success)
        XCTAssertEqual(recorder.samples.map(\.shortcut.keyCode), [8, 8, 9, 9])
        XCTAssertEqual(recorder.samples.map(\.down), [true, false, true, false])
        XCTAssertFalse(recorder.samples.contains(where: \.wasMainThread))
    }

    func testScreenshotAndDictationExecuteWhileMainThreadIsBlocked() {
        let recorder = ShortcutRecorder()
        let finished = DispatchSemaphore(value: 0)
        let engine = ActionEngine(cursorEngine: CursorEngine(), shortcutOutput: { shortcut, down in
            recorder.record(shortcut, down: down)
            if shortcut.keyCode == 63 && !down { finished.signal() }
        })
        engine.accessibilityTrusted = true
        engine.configureRealtimeActions(profile: .gabesDefaults, applicationBundleIdentifier: nil, enabled: true)
        let relay = ControllerInputRelay(inputQueue: DispatchQueue(label: "test.native-shortcut-input"))
        var mainActions = 0
        relay.setActionHandler { _ in mainActions += 1 }
        relay.setRealtimeActionHandler { engine.receiveRealtimeActions($0) }

        let started = ProcessInfo.processInfo.systemUptime
        relay.receiveGameController(snapshot([.buttonEast]))
        relay.receiveGameController(snapshot([]))
        relay.receiveGameController(snapshot([.rightTrigger]))
        relay.receiveGameController(snapshot([]))
        // No run-loop pumping: the old MainActor action path cannot pass this.
        XCTAssertEqual(finished.wait(timeout: .now() + 0.5), .success)
        let samples = recorder.samples
        XCTAssertEqual(samples.map(\.shortcut.keyCode), [21, 21, 63, 63])
        XCTAssertEqual(samples.map(\.down), [true, false, true, false])
        XCTAssertFalse(samples.contains(where: \.wasMainThread))
        XCTAssertLessThan((samples.last?.time ?? .infinity) - started, 0.5)
        print("Native screenshot + dictation sequence: \(((samples.last?.time ?? started) - started) * 1000) ms with main thread blocked")
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        XCTAssertEqual(mainActions, 0, "Native actions must not also replay on MainActor")
        engine.cancelAll()
    }

    func testModifierAndApplicationOverridesUseTheSameNativeResolver() {
        let recorder = ShortcutRecorder()
        let finished = DispatchSemaphore(value: 0)
        let engine = ActionEngine(cursorEngine: CursorEngine(), shortcutOutput: { shortcut, down in
            recorder.record(shortcut, down: down)
            if !down { finished.signal() }
        })
        engine.accessibilityTrusted = true
        engine.configureRealtimeActions(
            profile: .gabesDefaults,
            applicationBundleIdentifier: ApplicationMappingOverrides.codexBundleIdentifier,
            enabled: true
        )
        XCTAssertTrue(engine.receiveRealtimeActions(snapshot([.leftShoulder, .options])))
        XCTAssertEqual(finished.wait(timeout: .now() + 0.5), .success)
        XCTAssertEqual(recorder.samples.map(\.shortcut), Array(repeating: CodexKeybindingProvisioner.forkShortcut, count: 2))
        engine.cancelAll()
    }

    func testDisconnectReleasesHeldDictationWithoutMainThread() {
        let recorder = ShortcutRecorder()
        let finished = DispatchSemaphore(value: 0)
        let engine = ActionEngine(cursorEngine: CursorEngine(), shortcutOutput: { shortcut, down in
            recorder.record(shortcut, down: down)
            if !down { finished.signal() }
        })
        engine.accessibilityTrusted = true
        engine.configureRealtimeActions(profile: .gabesDefaults, applicationBundleIdentifier: nil, enabled: true)
        XCTAssertTrue(engine.receiveRealtimeActions(snapshot([.rightTrigger])))
        XCTAssertTrue(engine.receiveRealtimeActions(.disconnected))
        XCTAssertEqual(finished.wait(timeout: .now() + 0.5), .success)
        XCTAssertEqual(recorder.samples.map(\.down), [true, false])
        XCTAssertFalse(recorder.samples.contains(where: \.wasMainThread))
    }

    func testUnchangedConfigurationDoesNotInterruptHeldKey() {
        let downPosted = DispatchSemaphore(value: 0)
        let recorder = ShortcutRecorder()
        let engine = ActionEngine(cursorEngine: CursorEngine(), shortcutOutput: { shortcut, down in
            recorder.record(shortcut, down: down)
            if down { downPosted.signal() }
        })
        engine.accessibilityTrusted = true
        engine.configureRealtimeActions(profile: .gabesDefaults, applicationBundleIdentifier: nil, enabled: true)
        XCTAssertTrue(engine.receiveRealtimeActions(snapshot([.rightTrigger])))
        XCTAssertEqual(downPosted.wait(timeout: .now() + 0.5), .success)
        engine.configureRealtimeActions(profile: .gabesDefaults, applicationBundleIdentifier: nil, enabled: true)
        XCTAssertEqual(recorder.samples.map(\.down), [true])
        engine.accessibilityTrusted = false
        XCTAssertEqual(recorder.samples.map(\.down), [true, false])
    }

    func testCompanionRoutingDeclinesNativeOwnership() {
        let engine = ActionEngine(cursorEngine: CursorEngine())
        engine.configureRealtimeActions(profile: .gabesDefaults, applicationBundleIdentifier: nil, enabled: false)
        XCTAssertFalse(engine.receiveRealtimeActions(snapshot([.buttonEast])))
    }

    func testQueuedOldInputIsDiscardedOnProfileChangeDisableAndSuspend() {
        for change in 0..<3 {
            let queue = DispatchQueue(label: "test.paused-action-queue")
            queue.suspend()
            let recorder = ShortcutRecorder()
            let engine = ActionEngine(cursorEngine: CursorEngine(), shortcutOutput: { recorder.record($0, down: $1) }, actionQueue: queue)
            engine.accessibilityTrusted = true
            engine.configureRealtimeActions(profile: .gabesDefaults, applicationBundleIdentifier: nil, enabled: true)
            XCTAssertTrue(engine.receiveRealtimeActions(snapshot([.buttonEast])))
            switch change {
            case 0:
                engine.configureRealtimeActions(profile: .gabesDefaults, applicationBundleIdentifier: "another.app", enabled: true)
            case 1:
                engine.isEnabled = false
            default:
                engine.suspendActionExecution = true
            }
            let drained = DispatchSemaphore(value: 0)
            queue.async { drained.signal() }
            queue.resume()
            XCTAssertEqual(drained.wait(timeout: .now() + 0.5), .success)
            XCTAssertTrue(recorder.samples.isEmpty)
        }
    }

    func testRapidReconnectDoesNotLoseTheFirstNewPress() {
        let queue = DispatchQueue(label: "test.reconnect-action-queue")
        queue.suspend()
        let recorder = ShortcutRecorder()
        let engine = ActionEngine(cursorEngine: CursorEngine(), shortcutOutput: { recorder.record($0, down: $1) }, actionQueue: queue)
        engine.accessibilityTrusted = true
        engine.configureRealtimeActions(profile: .gabesDefaults, applicationBundleIdentifier: nil, enabled: true)
        XCTAssertTrue(engine.receiveRealtimeActions(snapshot([.rightTrigger])))
        XCTAssertTrue(engine.receiveRealtimeActions(.disconnected))
        XCTAssertTrue(engine.receiveRealtimeActions(snapshot([.buttonEast])))
        let drained = DispatchSemaphore(value: 0)
        queue.async { drained.signal() }
        queue.resume()
        XCTAssertEqual(drained.wait(timeout: .now() + 0.5), .success)
        XCTAssertEqual(recorder.samples.map(\.shortcut.keyCode), [63, 63, 21, 21])
        XCTAssertEqual(recorder.samples.map(\.down), [true, false, true, false])
    }

    func testKeyboardRepeatsContinueWithoutMainAndStopWhenDisabled() {
        let recorder = ShortcutRecorder()
        let repeated = DispatchSemaphore(value: 0)
        let engine = ActionEngine(cursorEngine: CursorEngine(), shortcutOutput: { shortcut, down in
            recorder.record(shortcut, down: down)
            if recorder.samples.count >= 6 { repeated.signal() }
        })
        engine.accessibilityTrusted = true
        var profile = ControllerProfile.gabesDefaults
        profile.mappings[.buttonEast] = ControllerActionMapping(
            actionType: .keyboardShortcut,
            shortcut: ShortcutDescriptor(keyCode: 21, modifiers: [.control, .shift, .command]),
            triggerMode: .repeatWhileHeld,
            repeatDelay: 0.02, repeatInterval: 0.02
        )
        engine.configureRealtimeActions(profile: profile, applicationBundleIdentifier: nil, enabled: true)
        XCTAssertTrue(engine.receiveRealtimeActions(snapshot([.buttonEast])))
        XCTAssertEqual(repeated.wait(timeout: .now() + 0.5), .success)
        engine.isEnabled = false
        let stoppedCount = recorder.samples.count
        Thread.sleep(forTimeInterval: 0.08)
        XCTAssertEqual(recorder.samples.count, stoppedCount)
        XCTAssertFalse(recorder.samples.contains(where: \.wasMainThread))
    }

    private func snapshot(_ pressed: Set<ControllerControlID>) -> ControllerSnapshot {
        var value = ControllerSnapshot.disconnected
        value.isConnected = true
        value.pressedControls = pressed
        return value
    }
}

private final class ShortcutRecorder: @unchecked Sendable {
    struct Sample {
        let shortcut: ShortcutDescriptor
        let down: Bool
        let wasMainThread: Bool
        let time: TimeInterval
    }
    private let lock = NSLock()
    private var storage: [Sample] = []
    var samples: [Sample] { lock.withLock { storage } }
    func record(_ shortcut: ShortcutDescriptor, down: Bool) {
        lock.withLock {
            storage.append(Sample(shortcut: shortcut, down: down, wasMainThread: Thread.isMainThread,
                                  time: ProcessInfo.processInfo.systemUptime))
        }
    }
}
