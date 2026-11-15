@testable import VibeController
import XCTest

final class Xbox360ControllerTests: XCTestCase {
    func testGenuineWired360SelectsItsOwnProtocol() {
        XCTAssertEqual(DirectUSBControllerKind.matching(vendorID: 0x045e, productID: 0x028e), .xbox360)
        XCTAssertEqual(DirectUSBControllerKind.xbox360.standardReportID, 0)
        XCTAssertEqual(DirectUSBControllerKind.xbox360.family, .xbox)
        XCTAssertEqual(DirectUSBControllerKind.matching(vendorID: 0x045e, productID: 0x0b12),
                       .xbox(supportsShareButton: true))
        XCTAssertEqual(DirectUSBControllerKind.matching(vendorID: 0x045e, productID: 0x02ea),
                       .xbox(supportsShareButton: false))
        XCTAssertEqual(DirectUSBControllerKind.matching(vendorID: 0x054c, productID: 0x0ce6),
                       .playStation(.dualSense))
        XCTAssertEqual(DirectUSBControllerKind.matching(vendorID: 0x054c, productID: 0x09cc),
                       .playStation(.dualShock4))
    }

    func testChargingCablesAndWirelessReceiversAreNotClaimedAsWiredControllers() {
        for productID in [0x028f, 0x0291, 0x0719] {
            XCTAssertNil(DirectUSBControllerKind.matching(vendorID: 0x045e, productID: productID))
        }
        XCTAssertNil(DirectUSBControllerKind.matching(vendorID: 0x1234, productID: 0x028e))
    }

    func testNeutralPacketHasNoPhantomButtonsOrAxisDrift() throws {
        let state = try parse(neutral())
        XCTAssertEqual(state.controllerFamily, .xbox)
        XCTAssertTrue(state.pressedControls.isEmpty)
        XCTAssertEqual(state.leftStick, StickSnapshot())
        XCTAssertEqual(state.rightStick, StickSnapshot())
        XCTAssertEqual(state.analogValues[.leftTrigger], 0)
        XCTAssertEqual(state.analogValues[.rightTrigger], 0)
        XCTAssertFalse(state.shareRequiresFullUSB)
        XCTAssertNil(state.analogValues[.share])
    }

    func testEveryDigitalButtonMapsIndependently() throws {
        let buttons: [(ControllerControlID, Int, UInt8)] = [
            (.dpadUp, 2, 0x01), (.dpadDown, 2, 0x02),
            (.dpadLeft, 2, 0x04), (.dpadRight, 2, 0x08),
            (.menu, 2, 0x10), (.options, 2, 0x20),
            (.leftThumbstickButton, 2, 0x40), (.rightThumbstickButton, 2, 0x80),
            (.leftShoulder, 3, 0x01), (.rightShoulder, 3, 0x02), (.home, 3, 0x04),
            (.buttonSouth, 3, 0x10), (.buttonEast, 3, 0x20),
            (.buttonWest, 3, 0x40), (.buttonNorth, 3, 0x80),
        ]
        for (control, offset, mask) in buttons {
            var report = neutral()
            report[offset] = mask
            let state = try parse(report)
            XCTAssertEqual(state.pressedControls, [control], "\(control)")
            XCTAssertEqual(state.analogValues[control], 1)
            XCTAssertEqual(state.leftStick.pressed, control == .leftThumbstickButton)
            XCTAssertEqual(state.rightStick.pressed, control == .rightThumbstickButton)
        }
    }

    func testBothTriggersHaveIndependentEightBitRangesAndExistingPressThreshold() throws {
        for (value, isPressed) in [(UInt8(0), false), (45, false), (46, true), (128, true), (255, true)] {
            for (control, offset, other) in [
                (ControllerControlID.leftTrigger, 4, ControllerControlID.rightTrigger),
                (.rightTrigger, 5, .leftTrigger),
            ] {
                var report = neutral()
                report[offset] = value
                let state = try parse(report)
                XCTAssertEqual(state.analogValues[control] ?? -1, Double(value) / 255, accuracy: 0.000_001)
                XCTAssertEqual(state.pressedControls.contains(control), isPressed)
                XCTAssertEqual(state.analogValues[other], 0)
                XCTAssertFalse(state.pressedControls.contains(other))
            }
        }
    }

    func testAllAxesAreSignedLittleEndianAndPositiveYMeansUp() throws {
        for offset in [6, 8, 10, 12] {
            for value in [Int16.min, -16_384, -1, 0, 1, 16_384, Int16.max] {
                var report = neutral()
                setAxis(value, offset: offset, in: &report)
                let state = try parse(report)
                let axes = [state.leftStick.x, state.leftStick.y, state.rightStick.x, state.rightStick.y]
                for (index, actual) in axes.enumerated() {
                    let expected = 6 + index * 2 == offset
                        ? Double(value) / (value >= 0 ? 32_767 : 32_768) : 0
                    XCTAssertEqual(actual, expected, accuracy: 0.000_001)
                }
            }
        }
    }

    func testDiagonalMagnitudesAreClampedWithoutClippingAxes() throws {
        var report = neutral()
        for offset in [6, 8, 10, 12] { setAxis(.max, offset: offset, in: &report) }
        let state = try parse(report)
        XCTAssertEqual(state.leftStick.x, 1)
        XCTAssertEqual(state.leftStick.y, 1)
        XCTAssertEqual(state.analogValues[.leftThumbstick], 1)
        XCTAssertEqual(state.analogValues[.rightThumbstick], 1)
    }

    func testReportIDStrippedFormMatchesFullPacketIncludingNeutralAndHome() throws {
        var pressed = neutral()
        pressed[2] = 0xff
        pressed[3] = 0xf7
        pressed[4] = 0xff
        setAxis(.min, offset: 8, in: &pressed)
        for report in [neutral(), pressed] {
            XCTAssertEqual(try parse(report), try parse(Array(report.dropFirst())))
        }
    }

    func testMalformedTruncatedStatusAndWrongProtocolReportsAreRejected() {
        for length in 0..<20 {
            XCTAssertNil(Xbox360USBReportParser.parse(reportID: 0, bytes: Array(neutral().prefix(length))))
        }
        var wrongLength = neutral()
        wrongLength[1] = 19
        var status = neutral()
        status[0] = 1
        for report in [wrongLength, status, neutral() + [0], Array(repeating: UInt8(0), count: 19)] {
            XCTAssertNil(Xbox360USBReportParser.parse(reportID: 0, bytes: report))
        }
        for reportID in [-1, 1, 7, 0x20, 256] {
            XCTAssertNil(Xbox360USBReportParser.parse(reportID: reportID, bytes: neutral()))
        }
        XCTAssertNil(XboxUSBReportParser.parse(reportID: 0, bytes: neutral()))
    }

    func testUSBSessionDoesNotTakeOverUntilACompleteInputPacketArrives() throws {
        var session = DirectUSBInputSession<String>()
        XCTAssertNil(session.receive(deviceID: "360", kind: .xbox360, reportID: 0, bytes: [0, 20]))
        XCTAssertNil(session.activeDeviceID)
        // A newer controller's Guide packet also must not block the GC fallback.
        XCTAssertNil(session.receive(deviceID: "series", kind: .xbox(supportsShareButton: true),
                                     reportID: 7, bytes: [7, 0x30, 0, 0, 1, 0, 0]))
        XCTAssertNil(session.activeDeviceID)
        XCTAssertNotNil(session.receive(deviceID: "360", kind: .xbox360, reportID: 0, bytes: neutral()))
        XCTAssertEqual(session.activeDeviceID, "360")
    }

    func testUSBSessionKeepsDevicesIsolatedAndResetsOnActiveDisconnect() throws {
        var session = DirectUSBInputSession<String>()
        var held = neutral()
        held[3] = 0x24 // Guide + B
        setAxis(.max, offset: 6, in: &held)
        let state = try XCTUnwrap(session.receive(deviceID: "one", kind: .xbox360, reportID: 0, bytes: held))
        XCTAssertEqual(state.pressedControls, [.home, .buttonEast])
        XCTAssertNil(session.receive(deviceID: "two", kind: .xbox360, reportID: 0, bytes: neutral()))
        XCTAssertFalse(session.remove(deviceID: "two"))
        XCTAssertEqual(session.state, state)
        XCTAssertTrue(session.remove(deviceID: "one"))
        XCTAssertNil(session.activeDeviceID)
        XCTAssertTrue(session.state.pressedControls.isEmpty)
        XCTAssertEqual(session.state.leftStick, StickSnapshot())
        XCTAssertNotNil(session.receive(deviceID: "two", kind: .xbox360, reportID: 0, bytes: neutral()))
    }

    func test360HomeAndAllOtherButtonsReleaseWithTheNextPacket() throws {
        var session = DirectUSBInputSession<Int>()
        var held = neutral()
        held[2] = 0xff
        held[3] = 0xf7
        held[4] = 0xff
        held[5] = 0xff
        XCTAssertNotNil(session.receive(deviceID: 1, kind: .xbox360, reportID: 0, bytes: held))
        XCTAssertTrue(session.state.pressedControls.contains(.home))
        let released = try XCTUnwrap(session.receive(deviceID: 1, kind: .xbox360, reportID: 0, bytes: neutral()))
        XCTAssertTrue(released.pressedControls.isEmpty)
        XCTAssertEqual(released.analogValues[.home], 0)
        XCTAssertEqual(released.analogValues[.leftTrigger], 0)
        XCTAssertEqual(released.analogValues[.rightTrigger], 0)
    }

    func testNewerXboxSessionStillUsesSeparateGuideAndPreservesMotionUntilRelease() throws {
        var session = DirectUSBInputSession<Int>()
        let kind = DirectUSBControllerKind.xbox(supportsShareButton: true)
        let standard: [UInt8] = [
            0x20, 0, 1, 0, 0x20, 0, 0, 0, 0, 0, 0xff, 0x7f, 0, 0, 0, 0, 0, 0,
        ]
        XCTAssertNotNil(session.receive(deviceID: 1, kind: kind, reportID: 0x20, bytes: standard))
        let guide = try XCTUnwrap(session.receive(
            deviceID: 1, kind: kind, reportID: 7, bytes: [7, 0x30, 0, 0, 1, 0, 0]))
        XCTAssertEqual(guide.pressedControls, [.buttonEast, .home])
        XCTAssertEqual(guide.leftStick.x, 1)
        let next = try XCTUnwrap(session.receive(deviceID: 1, kind: kind, reportID: 0x20, bytes: standard))
        XCTAssertTrue(next.pressedControls.contains(.home))
        let failsafe = try XCTUnwrap(session.releaseHome())
        XCTAssertEqual(failsafe.pressedControls, [.buttonEast])
        XCTAssertEqual(failsafe.leftStick.x, 1)
        XCTAssertNil(session.releaseHome())
    }

    func testPlayStationSessionStillActivatesFromItsOwnReportFormat() throws {
        var session = DirectUSBInputSession<Int>()
        var report = Array(repeating: UInt8(0), count: 64)
        report[0] = 1
        report[1] = 128
        report[2] = 128
        report[3] = 128
        report[4] = 128
        report[8] = 0x28 // Cross, D-pad neutral
        let state = try XCTUnwrap(session.receive(
            deviceID: 1, kind: .playStation(.dualSense), reportID: 1, bytes: report))
        XCTAssertEqual(state.controllerFamily, .playStation)
        XCTAssertEqual(state.pressedControls, [.buttonSouth])
        XCTAssertEqual(session.activeDeviceID, 1)
    }

    private func neutral() -> [UInt8] { [0, 20] + Array(repeating: 0, count: 18) }

    private func parse(_ report: [UInt8]) throws -> XboxUSBInputState {
        try XCTUnwrap(Xbox360USBReportParser.parse(reportID: 0, bytes: report))
    }

    private func setAxis(_ value: Int16, offset: Int, in report: inout [UInt8]) {
        let bits = UInt16(bitPattern: value)
        report[offset] = UInt8(truncatingIfNeeded: bits)
        report[offset + 1] = UInt8(truncatingIfNeeded: bits >> 8)
    }
}
