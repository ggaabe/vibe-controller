import AppKit
import SwiftUI
import XCTest
@testable import VibeController

final class ControllerVibrationModelTests: XCTestCase {
    @MainActor
    func testFreshInstallUsesGabesSavedHapticPreferences() throws {
        let name = "test.haptics.fresh.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let haptics = ControllerHaptics(defaults: defaults)
        XCTAssertTrue(haptics.isEnabled)
        XCTAssertEqual(haptics.strength, 0.5)
        XCTAssertTrue(haptics.connectionFeedback)
    }

    @MainActor
    func testUpgradePreservesExplicitHapticPreferences() throws {
        let name = "test.haptics.existing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "haptics.enabled")
        defaults.set(0.8, forKey: "haptics.strength")
        defaults.set(false, forKey: "haptics.connectionFeedback")
        let haptics = ControllerHaptics(defaults: defaults)
        XCTAssertFalse(haptics.isEnabled)
        XCTAssertEqual(haptics.strength, 0.8)
        XCTAssertFalse(haptics.connectionFeedback)
    }

    func testLegacyAndUnknownPatternsDecodeWithoutChangingCommands() throws {
        for extra in ["", ",\"vibration\":\"futurePattern\""] {
            let json = "{\"actionType\":\"keyboardShortcut\",\"shortcut\":{\"keyCode\":53,\"modifiers\":[]},\"triggerMode\":\"tap\",\"repeatDelay\":0.35,\"repeatInterval\":0.08\(extra)}"
            let mapping = try JSONDecoder().decode(ControllerActionMapping.self, from: Data(json.utf8))
            XCTAssertEqual(mapping.vibration, .none)
            XCTAssertEqual(mapping.shortcut?.keyCode, 53)
        }
    }

    func testEveryPatternRoundTripsThroughProfiles() throws {
        for pattern in ControllerVibration.allCases {
            var profile = ControllerProfile.gabesDefaults
            profile.mappings[.share] = ControllerActionMapping(vibration: pattern)
            let decoded = try JSONDecoder().decode(ControllerProfile.self, from: JSONEncoder().encode(profile))
            XCTAssertEqual(decoded, profile)
        }
    }

    func testSuggestionsOnlyChangeVibrationAndLeaveEverydayControlsQuiet() throws {
        var profile = ControllerProfile.gabesDefaults
        profile.mappings[.buttonNorth]?.shortcut = ShortcutDescriptor(keyCode: 9, modifiers: [.control])
        let before = profile
        profile.applySuggestedVibrations()
        func withoutVibration(_ profile: ControllerProfile) throws -> NSDictionary {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile))
            func strip(_ value: Any) -> Any {
                if let dictionary = value as? [String: Any] {
                    return dictionary.filter { $0.key != "vibration" }.mapValues(strip)
                }
                if let array = value as? [Any] { return array.map(strip) }
                return value
            }
            return try XCTUnwrap(strip(object) as? NSDictionary)
        }
        XCTAssertEqual(try withoutVibration(before), try withoutVibration(profile))
        for control in [ControllerControlID.buttonSouth, .buttonNorth, .dpadUp, .dpadDown, .leftThumbstickButton, .rightThumbstickButton] {
            XCTAssertEqual(profile.mappings[control]?.vibration, ControllerVibration.none)
        }
        XCTAssertEqual(profile.mappings[.leftTrigger]?.vibration, .grabRelease)
        XCTAssertEqual(profile.mappings[.rightTrigger]?.vibration, .softTap)
        XCTAssertEqual(profile.mappings[.buttonEast]?.vibration, .softTap)
        XCTAssertEqual(profile.mappings[.buttonWest]?.vibration, .doubleTap)
        for modifier in [ControllerControlID.leftShoulder, .rightShoulder] {
            XCTAssertEqual(profile.mappings[modifier]?.vibration, .softTap)
            XCTAssertEqual(profile.effectiveMapping(for: .dpadLeft, modifierControl: modifier).vibration, .leftPulse)
            XCTAssertEqual(profile.effectiveMapping(for: .dpadRight, modifierControl: modifier).vibration, .rightPulse)
            XCTAssertEqual(profile.effectiveMapping(for: .dpadUp, modifierControl: modifier).vibration, .thump)
        }
    }

    func testAllPulsesAreFiniteShortAndBounded() {
        for pattern in ControllerVibration.allCases {
            for phase in [ControllerVibration.Phase.press, .release] {
                for pulse in pattern.pulses(for: phase) {
                    XCTAssertTrue(pulse.time.isFinite && pulse.duration.isFinite)
                    XCTAssertGreaterThan(pulse.duration, 0)
                    XCTAssertLessThan(pulse.time + pulse.duration, 0.3)
                    XCTAssertTrue((0...1).contains(pulse.intensity))
                }
            }
            if pattern != .grabRelease { XCTAssertTrue(pattern.pulses(for: .release).isEmpty) }
        }
    }
}

@MainActor
final class ControllerVibrationActionTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []
        var values: [String] { lock.withLock { events } }
        func append(_ value: String) { lock.withLock { events.append(value) } }
    }
    private func engine(_ recorder: Recorder) -> ActionEngine {
        let engine = ActionEngine(cursorEngine: CursorEngine(),
            vibrationOutput: { pattern, phase in recorder.append("\(pattern.rawValue):\(phase)") },
            stopVibrationOutput: { recorder.append("stop") })
        engine.accessibilityTrusted = true
        engine.companionDispatch = { _ in true } // Never send real shortcuts in unit tests.
        return engine
    }
    private func input(_ controls: Set<ControllerControlID>) -> ControllerSnapshot {
        var snapshot = ControllerSnapshot.disconnected
        snapshot.isConnected = true
        snapshot.pressedControls = controls
        return snapshot
    }
    func testModifierAndCapturePlayOnceAndNotOnModifierTapRelease() {
        let recorder = Recorder()
        let subject = self.engine(recorder)
        let profile = ControllerProfile.gabesDefaults
        subject.process(snapshot: input([.leftShoulder]), profile: profile)
        subject.process(snapshot: input([.leftShoulder, .buttonEast]), profile: profile)
        subject.process(snapshot: input([.leftShoulder, .buttonEast]), profile: profile)
        subject.process(snapshot: input([]), profile: profile)
        XCTAssertEqual(recorder.values, ["softTap:press", "softTap:press"])
        subject.process(snapshot: input([.rightShoulder]), profile: profile)
        subject.process(snapshot: input([]), profile: profile)
        XCTAssertEqual(recorder.values.last, "softTap:press")
        XCTAssertEqual(recorder.values.count, 3)
    }
    func testGrabReleaseAndCancellation() {
        let recorder = Recorder()
        let engine = self.engine(recorder)
        let profile = ControllerProfile.gabesDefaults
        engine.process(snapshot: input([.leftTrigger]), profile: profile)
        engine.process(snapshot: input([]), profile: profile)
        XCTAssertEqual(recorder.values, ["grabRelease:press", "grabRelease:release"])
        engine.process(snapshot: input([.leftTrigger]), profile: profile)
        engine.cancelAll()
        XCTAssertEqual(recorder.values.suffix(2), ["grabRelease:press", "stop"])
    }
    func testToggleDragUsesReleasePatternWhenToggledOff() {
        let recorder = Recorder()
        let subject = self.engine(recorder)
        var profile = ControllerProfile.gabesDefaults
        profile.mappings[.leftTrigger]?.triggerMode = .toggle
        subject.process(snapshot: input([.leftTrigger]), profile: profile)
        subject.process(snapshot: input([]), profile: profile)
        subject.process(snapshot: input([.leftTrigger]), profile: profile)
        XCTAssertEqual(recorder.values, ["grabRelease:press", "grabRelease:release"])
    }
    func testAppOverrideAndExplicitNoneOverrideFeedback() {
        let recorder = Recorder()
        let engine = self.engine(recorder)
        var profile = ControllerProfile.gabesDefaults
        profile.applicationMappings = [ApplicationMappingOverrides(
            bundleIdentifier: "test.app", displayName: "Test", mappings: [
                .buttonWest: ControllerActionMapping(actionType: .none),
                .buttonEast: ControllerActionMapping(actionType: .none, vibration: .thump),
            ])]
        engine.process(snapshot: input([.buttonWest]), profile: profile, applicationBundleIdentifier: "test.app")
        engine.process(snapshot: input([.buttonEast]), profile: profile, applicationBundleIdentifier: "test.app")
        XCTAssertEqual(recorder.values, ["thump:press"])
        engine.process(snapshot: input([.rightTrigger]), profile: profile, applicationBundleIdentifier: "test.app")
        XCTAssertEqual(recorder.values.last, "softTap:press")
    }
    func testRepeatingActionOnlyVibratesAtInitialPress() async throws {
        let recorder = Recorder()
        let engine = self.engine(recorder)
        engine.allowsBackgroundScrollRepeats = false
        var profile = ControllerProfile.gabesDefaults
        profile.mappings[.dpadUp]?.vibration = .softTap
        profile.mappings[.dpadUp]?.repeatDelay = 0.02
        profile.mappings[.dpadUp]?.repeatInterval = 0.02
        engine.process(snapshot: input([.dpadUp]), profile: profile)
        try await Task.sleep(for: .milliseconds(100))
        engine.process(snapshot: input([]), profile: profile)
        XCTAssertEqual(recorder.values, ["softTap:press"])
    }
    func testDisabledAndSuspendedActionsNeverVibrate() {
        let recorder = Recorder()
        let subject = self.engine(recorder)
        subject.isEnabled = false
        subject.process(snapshot: input([.buttonEast]), profile: .gabesDefaults)
        subject.isEnabled = true
        subject.suspendActionExecution = true
        subject.process(snapshot: input([.buttonWest]), profile: .gabesDefaults)
        XCTAssertTrue(recorder.values.allSatisfy { $0 == "stop" })
    }
}

@MainActor
final class ControllerVibrationUITests: XCTestCase {
    func testPreferencesDefaultToGabesSetupAndPersistIndependentlyOfProfiles() {
        let suite = "VibeHapticsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let haptics = ControllerHaptics(defaults: defaults)
        XCTAssertTrue(haptics.isEnabled)
        haptics.isEnabled = false
        haptics.strength = 0.3
        haptics.connectionFeedback = false
        let restored = ControllerHaptics(defaults: defaults)
        XCTAssertFalse(restored.isEnabled)
        XCTAssertEqual(restored.strength, 0.3)
        XCTAssertFalse(restored.connectionFeedback)
    }
    func testSettingsAndEditorRenderWithinTheirAvailableWidths() throws {
        let suite = "HapticRender-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let haptics = ControllerHaptics(defaults: defaults)
        for enabled in [false, true] {
            haptics.isEnabled = enabled
            let renderer = ImageRenderer(content: ControllerVibrationSettingsView(
                haptics: haptics, applySuggestions: {}).frame(width: 210).padding(20))
            XCTAssertNotNil(renderer.cgImage)
            let editor = NSHostingController(rootView: Form {
                MappingVibrationEditor(pattern: .constant(.grabRelease), haptics: haptics)
            }.formStyle(.grouped).frame(width: 552, height: 370))
            XCTAssertLessThanOrEqual(editor.sizeThatFits(in: CGSize(width: 552, height: 370)).width, 552)
        }
    }
}
