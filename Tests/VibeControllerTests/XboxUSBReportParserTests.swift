@testable import VibeController
import XCTest

final class XboxUSBReportParserTests: XCTestCase {
    func testParsesFullXboxOneUSBInputReport() throws {
        let report: [UInt8] = [
            0x20, 0x00, 0x01, 0x00,
            0x54, 0x61,
            0xff, 0x03,
            0x00, 0x02,
            0xff, 0x7f,
            0x00, 0x80,
            0x00, 0x40,
            0x00, 0xc0,
            0x00,
        ]

        let state = try XCTUnwrap(XboxUSBReportParser.parse(reportID: 0x20, bytes: report))

        XCTAssertTrue(state.pressedControls.isSuperset(of: [
            .menu, .buttonSouth, .buttonWest, .dpadUp, .rightShoulder, .leftThumbstickButton,
        ]))
        XCTAssertEqual(state.analogValues[.leftTrigger] ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(state.analogValues[.rightTrigger] ?? -1, 512.0 / 1_023.0, accuracy: 0.0001)
        XCTAssertEqual(state.leftStick.x, 1, accuracy: 0.0001)
        XCTAssertEqual(state.leftStick.y, -1, accuracy: 0.0001)
        XCTAssertEqual(state.rightStick.x, 16_384.0 / 32_767.0, accuracy: 0.0001)
        XCTAssertEqual(state.rightStick.y, -16_384.0 / 32_768.0, accuracy: 0.0001)
    }

    func testParsesReportWhenIOKitStripsReportIDByte() throws {
        let fullReport: [UInt8] = [
            0x20, 0x00, 0x01, 0x00,
            0x20, 0x08,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00,
            0x00,
        ]

        let state = try XCTUnwrap(
            XboxUSBReportParser.parse(reportID: 0x20, bytes: Array(fullReport.dropFirst()))
        )

        XCTAssertTrue(state.pressedControls.contains(.buttonEast))
        XCTAssertTrue(state.pressedControls.contains(.dpadRight))
    }

    func testGuideReportPreservesStickState() throws {
        var previous = XboxUSBInputState()
        previous.leftStick.x = 0.75

        let pressed = try XCTUnwrap(
            XboxUSBReportParser.parse(
                reportID: 0x07,
                bytes: [0x07, 0x30, 0x00, 0x00, 0x01, 0x00, 0x00],
                previous: previous
            )
        )
        XCTAssertTrue(pressed.pressedControls.contains(.home))
        XCTAssertEqual(pressed.leftStick.x, 0.75)

        let released = try XCTUnwrap(
            XboxUSBReportParser.parse(
                reportID: 0x07,
                bytes: [0x07, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00],
                previous: pressed
            )
        )
        XCTAssertFalse(released.pressedControls.contains(.home))
    }
}
