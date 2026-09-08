import XCTest
@testable import VibeController

final class XboxShareButtonTests: XCTestCase {
    private func report(shareByte: UInt8) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 23)
        bytes[0] = 0x20
        bytes[3] = 19
        bytes[22] = shareByte
        return bytes
    }

    func testUSBSharePressAndReleaseWithAndWithoutReportID() throws {
        for stripped in [false, true] {
            func payload(_ byte: UInt8) -> [UInt8] {
                let bytes = report(shareByte: byte)
                return stripped ? Array(bytes.dropFirst()) : bytes
            }
            let down = try XCTUnwrap(XboxUSBReportParser.parse(
                reportID: 0x20, bytes: payload(1), supportsShareButton: true))
            XCTAssertEqual(down.pressedControls, [.share])
            XCTAssertEqual(down.analogValues[.share], 1)
            let up = try XCTUnwrap(XboxUSBReportParser.parse(
                reportID: 0x20, bytes: payload(0), previous: down, supportsShareButton: true))
            XCTAssertTrue(up.pressedControls.isEmpty)
            XCTAssertEqual(up.analogValues[.share], 0)
        }
    }

    func testExtraBitsAndLegacyOrElitePacketsDoNotGenerateShare() throws {
        let otherBits = try XCTUnwrap(XboxUSBReportParser.parse(
            reportID: 0x20, bytes: report(shareByte: 0xfe), supportsShareButton: true))
        XCTAssertFalse(otherBits.pressedControls.contains(.share))
        let elite = try XCTUnwrap(XboxUSBReportParser.parse(
            reportID: 0x20, bytes: report(shareByte: 1)))
        XCTAssertFalse(elite.pressedControls.contains(.share))
        XCTAssertNil(elite.analogValues[.share])
        let shortReport = try XCTUnwrap(XboxUSBReportParser.parse(
            reportID: 0x20, bytes: Array(report(shareByte: 1).prefix(18)), supportsShareButton: true))
        XCTAssertFalse(shortReport.pressedControls.contains(.share))
    }

    func testShareCoexistsWithOtherButtonsSticksTriggersAndGuide() throws {
        var bytes = report(shareByte: 1)
        bytes[4] = 0x20 // B
        bytes[5] = 0x20 // RB
        bytes[6] = 0xff
        bytes[7] = 0x03 // LT fully held
        bytes[10] = 0xff
        bytes[11] = 0x7f // left stick fully right
        let state = try XCTUnwrap(XboxUSBReportParser.parse(
            reportID: 0x20, bytes: bytes, supportsShareButton: true))
        XCTAssertEqual(state.pressedControls, [.share, .buttonEast, .rightShoulder, .leftTrigger])
        XCTAssertEqual(state.leftStick.x, 1)
        XCTAssertEqual(state.analogValues[.leftTrigger], 1)
        let guide = try XCTUnwrap(XboxUSBReportParser.parse(
            reportID: 0x07, bytes: [0x07, 0x30, 0, 0, 1], previous: state, supportsShareButton: true))
        XCTAssertTrue(guide.pressedControls.isSuperset(of: [.home, .share, .rightShoulder]))
        XCTAssertEqual(guide.leftStick.x, 1)
        let feedback = ControllerLiveFeedback(
            pressedControls: guide.pressedControls, analogValues: guide.analogValues,
            leftStick: guide.leftStick, rightStick: guide.rightStick)
        XCTAssertTrue(feedback.isActive(.share))
    }

    func testShareIsDistinctFromPlayStationCreateAndAvailableForXboxMappings() {
        XCTAssertEqual(ControllerControlID.share.displayName, "Share")
        XCTAssertTrue(ControllerControlID.mappingControls(for: .xbox).contains(.share))
        XCTAssertFalse(ControllerControlID.mappingControls(for: .playStation).contains(.share))
        XCTAssertTrue(ControllerControlID.mappingControls(for: .playStation).contains(.options))
        XCTAssertEqual(ControllerControlID.options.displayName(for: .playStation), "Create")
    }

    func testExistingProfilesRemainUnassignedAndShareMappingsRoundTrip() throws {
        let defaults = ControllerProfile.gabesDefaults
        XCTAssertEqual(defaults.effectiveMapping(for: .share, modifierControl: nil).actionType, .none)
        let oldProfile = try JSONDecoder().decode(ControllerProfile.self, from: JSONEncoder().encode(defaults))
        XCTAssertEqual(oldProfile, defaults)
        var profile = oldProfile
        let copy = ControllerActionMapping(
            actionType: .keyboardShortcut, shortcut: ShortcutDescriptor(keyCode: 8, modifiers: [.command]))
        profile.mappings[.share] = copy
        profile.modifierLayers.append(ControllerModifierLayer(modifierControl: .share, mappings: [.buttonSouth: copy]))
        let restored = try JSONDecoder().decode(ControllerProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(restored, profile)
        XCTAssertEqual(restored.effectiveMapping(for: .share, modifierControl: nil), copy)
        XCTAssertEqual(restored.effectiveMapping(for: .buttonSouth, modifierControl: .share), copy)
    }
}
