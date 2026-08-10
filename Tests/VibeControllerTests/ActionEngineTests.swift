import XCTest
@testable import VibeController

@MainActor
final class ActionEngineTests: XCTestCase {
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
}
