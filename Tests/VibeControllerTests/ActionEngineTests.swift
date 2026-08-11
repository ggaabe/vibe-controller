import XCTest
@testable import VibeController

@MainActor
final class ActionEngineTests: XCTestCase {
    func testModifierTapRunsItsDefaultActionOnlyAfterRelease() {
        let recorder = ActionEventRecorder()
        let actionEngine = makeActionEngine(recorder: recorder)
        let profile = profileWithLeftShoulderLayer()

        actionEngine.process(
            snapshot: snapshot(pressed: [.leftShoulder]),
            profile: profile
        )
        XCTAssertTrue(recorder.events.isEmpty)

        actionEngine.process(snapshot: snapshot(pressed: []), profile: profile)

        XCTAssertEqual(recorder.events.count, 1)
        assertShortcut(
            recorder.events[0],
            equals: ShortcutDescriptor(keyCode: 53, modifiers: []),
            phase: .tap
        )
    }

    func testModifierOverrideWinsWhenBothButtonsArriveTogether() {
        let recorder = ActionEventRecorder()
        let actionEngine = makeActionEngine(recorder: recorder)
        let alternateShortcut = ShortcutDescriptor(keyCode: 0, modifiers: [.command])
        let profile = profileWithLeftShoulderLayer(overrides: [
            .dpadRight: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: alternateShortcut,
                triggerMode: .tap
            ),
        ])

        actionEngine.process(
            snapshot: snapshot(pressed: [.leftShoulder, .dpadRight]),
            profile: profile
        )
        actionEngine.process(snapshot: snapshot(pressed: []), profile: profile)

        XCTAssertEqual(recorder.events.count, 1)
        assertShortcut(recorder.events[0], equals: alternateShortcut, phase: .tap)
    }

    func testUnconfiguredModifierCombinationFallsBackToDefaultAction() {
        let recorder = ActionEventRecorder()
        let actionEngine = makeActionEngine(recorder: recorder)
        let profile = profileWithLeftShoulderLayer()

        actionEngine.process(
            snapshot: snapshot(pressed: [.leftShoulder]),
            profile: profile
        )
        actionEngine.process(
            snapshot: snapshot(pressed: [.leftShoulder, .buttonSouth]),
            profile: profile
        )
        actionEngine.process(snapshot: snapshot(pressed: []), profile: profile)

        XCTAssertEqual(recorder.events.count, 1)
        guard case .mouse(.left, .click) = recorder.events[0].payload else {
            return XCTFail("Expected the inherited left-click action")
        }
    }

    func testExplicitNoneOverrideSuppressesDefaultAndModifierTapActions() {
        let recorder = ActionEventRecorder()
        let actionEngine = makeActionEngine(recorder: recorder)
        let profile = profileWithLeftShoulderLayer(overrides: [
            .dpadRight: ControllerActionMapping(actionType: .none),
        ])

        actionEngine.process(
            snapshot: snapshot(pressed: [.leftShoulder, .dpadRight]),
            profile: profile
        )
        actionEngine.process(snapshot: snapshot(pressed: []), profile: profile)

        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testReleasingModifierEndsHeldOverrideWithoutAStuckKey() {
        let recorder = ActionEventRecorder()
        let actionEngine = makeActionEngine(recorder: recorder)
        let alternateShortcut = ShortcutDescriptor(keyCode: 3, modifiers: [.shift, .command])
        let profile = profileWithLeftShoulderLayer(overrides: [
            .dpadRight: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: alternateShortcut,
                triggerMode: .holdWhilePressed
            ),
        ])

        actionEngine.process(
            snapshot: snapshot(pressed: [.leftShoulder]),
            profile: profile
        )
        actionEngine.process(
            snapshot: snapshot(pressed: [.leftShoulder, .dpadRight]),
            profile: profile
        )
        actionEngine.process(
            snapshot: snapshot(pressed: [.dpadRight]),
            profile: profile
        )
        actionEngine.process(snapshot: snapshot(pressed: []), profile: profile)

        XCTAssertEqual(recorder.events.count, 2)
        assertShortcut(recorder.events[0], equals: alternateShortcut, phase: .down)
        assertShortcut(recorder.events[1], equals: alternateShortcut, phase: .up)
    }

    func testCancelAllDoesNotFireAnUnusedModifierTap() {
        let recorder = ActionEventRecorder()
        let actionEngine = makeActionEngine(recorder: recorder)
        let profile = profileWithLeftShoulderLayer()

        actionEngine.process(
            snapshot: snapshot(pressed: [.leftShoulder]),
            profile: profile
        )
        actionEngine.cancelAll()

        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testRepeatScrollUpFiresImmediatelyInTheExpectedDirection() {
        assertImmediateScroll(
            control: .dpadUp,
            actionType: .scrollUp,
            expectedVertical: -1
        )
    }

    func testRepeatScrollDownFiresImmediatelyInTheExpectedDirection() {
        assertImmediateScroll(
            control: .dpadDown,
            actionType: .scrollDown,
            expectedVertical: 1
        )
    }

    func testCrossEdgeRightActionRoutesToCursorSweep() {
        let actionEngine = makeActionEngine(recorder: ActionEventRecorder())
        var receivedDirection: CrossEdgeDirection?
        actionEngine.onCrossEdgeSweep = { receivedDirection = $0 }
        var profile = ControllerProfile.gabesDefaults
        profile.mappings[.dpadRight] = ControllerActionMapping(actionType: .crossEdgeRight)

        actionEngine.process(
            snapshot: snapshot(pressed: [.dpadRight]),
            profile: profile
        )

        XCTAssertEqual(receivedDirection, .right)
    }

    func testCrossEdgeUpActionRoutesToCursorSweep() {
        let actionEngine = makeActionEngine(recorder: ActionEventRecorder())
        var receivedDirection: CrossEdgeDirection?
        actionEngine.onCrossEdgeSweep = { receivedDirection = $0 }
        var profile = ControllerProfile.gabesDefaults
        profile.mappings[.dpadUp] = ControllerActionMapping(actionType: .crossEdgeUp)

        actionEngine.process(
            snapshot: snapshot(pressed: [.dpadUp]),
            profile: profile
        )

        XCTAssertEqual(receivedDirection, .up)
    }

    func testModifierCrossEdgeLeftActionConsumesModifierTap() {
        let recorder = ActionEventRecorder()
        let actionEngine = makeActionEngine(recorder: recorder)
        var receivedDirections: [CrossEdgeDirection] = []
        actionEngine.onCrossEdgeSweep = { receivedDirections.append($0) }
        let profile = profileWithLeftShoulderLayer(overrides: [
            .dpadLeft: ControllerActionMapping(actionType: .crossEdgeLeft),
        ])

        actionEngine.process(
            snapshot: snapshot(pressed: [.leftShoulder, .dpadLeft]),
            profile: profile
        )
        actionEngine.process(snapshot: snapshot(pressed: []), profile: profile)

        XCTAssertEqual(receivedDirections, [.left])
        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testModifierCrossEdgeDownActionConsumesModifierTap() {
        let recorder = ActionEventRecorder()
        let actionEngine = makeActionEngine(recorder: recorder)
        var receivedDirections: [CrossEdgeDirection] = []
        actionEngine.onCrossEdgeSweep = { receivedDirections.append($0) }
        let profile = profileWithLeftShoulderLayer(overrides: [
            .dpadDown: ControllerActionMapping(actionType: .crossEdgeDown),
        ])

        actionEngine.process(
            snapshot: snapshot(pressed: [.leftShoulder, .dpadDown]),
            profile: profile
        )
        actionEngine.process(snapshot: snapshot(pressed: []), profile: profile)

        XCTAssertEqual(receivedDirections, [.down])
        XCTAssertTrue(recorder.events.isEmpty)
    }

    private func assertImmediateScroll(
        control: ControllerControlID,
        actionType: ActionType,
        expectedVertical: Int32
    ) {
        let cursorEngine = CursorEngine()
        let actionEngine = ActionEngine(cursorEngine: cursorEngine)
        actionEngine.accessibilityTrusted = true

        var dispatchedEvents: [CompanionControlEvent] = []
        actionEngine.companionDispatch = { event in
            dispatchedEvents.append(event)
            return true
        }

        var profile = ControllerProfile.gabesDefaults
        profile.mappings[control] = ControllerActionMapping(
            actionType: actionType,
            triggerMode: .repeatWhileHeld,
            repeatDelay: 10,
            repeatInterval: 10
        )

        var pressedSnapshot = ControllerSnapshot.disconnected
        pressedSnapshot.isConnected = true
        pressedSnapshot.pressedControls = [control]
        actionEngine.process(snapshot: pressedSnapshot, profile: profile)

        XCTAssertEqual(dispatchedEvents.count, 1)
        guard case .scroll(let vertical, let horizontal) = dispatchedEvents[0].payload else {
            return XCTFail("Expected an immediate scroll event")
        }
        XCTAssertEqual(vertical, expectedVertical)
        XCTAssertEqual(horizontal, 0)

        var releasedSnapshot = pressedSnapshot
        releasedSnapshot.pressedControls = []
        actionEngine.process(snapshot: releasedSnapshot, profile: profile)
        actionEngine.cancelAll()
    }

    private func makeActionEngine(recorder: ActionEventRecorder) -> ActionEngine {
        let actionEngine = ActionEngine(cursorEngine: CursorEngine())
        actionEngine.accessibilityTrusted = true
        actionEngine.companionDispatch = { event in
            recorder.events.append(event)
            return true
        }
        return actionEngine
    }

    private func profileWithLeftShoulderLayer(
        overrides: [ControllerControlID: ControllerActionMapping] = [:]
    ) -> ControllerProfile {
        var profile = ControllerProfile.gabesDefaults
        profile.modifierLayers = [
            ControllerModifierLayer(
                modifierControl: .leftShoulder,
                mappings: overrides
            ),
        ]
        return profile
    }

    private func snapshot(
        pressed controls: Set<ControllerControlID>
    ) -> ControllerSnapshot {
        var snapshot = ControllerSnapshot.disconnected
        snapshot.isConnected = true
        snapshot.pressedControls = controls
        return snapshot
    }

    private func assertShortcut(
        _ event: CompanionControlEvent,
        equals expectedShortcut: ShortcutDescriptor,
        phase expectedPhase: CompanionShortcutPhase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .shortcut(let shortcut, let phase) = event.payload else {
            return XCTFail("Expected a shortcut event", file: file, line: line)
        }
        XCTAssertEqual(shortcut, expectedShortcut, file: file, line: line)
        switch (phase, expectedPhase) {
        case (.tap, .tap), (.down, .down), (.up, .up):
            break
        default:
            XCTFail("Unexpected shortcut phase", file: file, line: line)
        }
    }
}

private final class ActionEventRecorder {
    var events: [CompanionControlEvent] = []
}
