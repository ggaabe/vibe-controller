@testable import VibeController
import XCTest

final class PlayStationControllerTests: XCTestCase {
    func testDualShock4USBReportMapsPlayStationButtonsAndTouchpad() throws {
        let report: [UInt8] = [
            0x01,
            0xff, 0x00, 0x80, 0x7f,
            0x31, 0x59, 0x03,
            0x80, 0xff,
        ]

        let state = try XCTUnwrap(
            PlayStationUSBReportParser.parse(
                kind: .dualShock4,
                reportID: 0x01,
                bytes: report
            )
        )

        XCTAssertEqual(state.controllerFamily, .playStation)
        XCTAssertTrue(state.pressedControls.isSuperset(of: [
            .buttonWest, .buttonSouth, .dpadUp, .dpadRight,
            .leftShoulder, .options, .leftThumbstickButton,
            .home, .touchpadButton, .leftTrigger, .rightTrigger,
        ]))
        XCTAssertEqual(state.leftStick.x, 1, accuracy: 0.0001)
        XCTAssertEqual(state.leftStick.y, 1, accuracy: 0.0001)
        XCTAssertEqual(state.analogValues[.leftTrigger] ?? -1, 128.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(state.analogValues[.rightTrigger] ?? -1, 1, accuracy: 0.0001)
    }

    func testDualSenseUSBReportParsesWhenIOKitStripsReportID() throws {
        let reportWithoutID: [UInt8] = [
            0x00, 0xff, 0x7f, 0x80,
            0x00, 0x40, 0x2a,
            0xc5, 0xa2, 0x02,
        ]

        let state = try XCTUnwrap(
            PlayStationUSBReportParser.parse(
                kind: .dualSense,
                reportID: 0x01,
                bytes: reportWithoutID
            )
        )

        XCTAssertTrue(state.pressedControls.isSuperset(of: [
            .buttonEast, .buttonNorth, .dpadDown, .dpadLeft,
            .rightShoulder, .menu, .rightThumbstickButton, .touchpadButton,
        ]))
        XCTAssertFalse(state.pressedControls.contains(.home))
        XCTAssertEqual(state.rightTriggerValue, 64.0 / 255.0, accuracy: 0.0001)
    }

    func testPlayStationFamilyInferenceAndNativeLabels() {
        XCTAssertEqual(ControllerFamily.inferred(from: "Sony DualSense Wireless Controller"), .playStation)
        XCTAssertEqual(ControllerFamily.inferred(from: "DUALSHOCK 4"), .playStation)
        XCTAssertEqual(ControllerFamily.inferred(from: "Xbox Wireless Controller"), .xbox)

        XCTAssertEqual(ControllerControlID.buttonSouth.displayName(for: .playStation), "Cross")
        XCTAssertEqual(ControllerControlID.leftShoulder.displayName(for: .playStation), "L1")
        XCTAssertEqual(ControllerControlID.options.displayName(for: .playStation), "Create")
        XCTAssertEqual(ControllerControlID.touchpadButton.displayName(for: .playStation), "Touchpad")
    }
}

private extension XboxUSBInputState {
    var rightTriggerValue: Double {
        analogValues[.rightTrigger] ?? -1
    }
}
