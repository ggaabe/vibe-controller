import XCTest
@testable import VibeController

final class XboxShareButtonTests: XCTestCase {
    private func capturedReport(_ hex: String) throws -> [UInt8] {
        let digits = Array(hex)
        return try stride(from: 0, to: digits.count, by: 2).map { index in
            try XCTUnwrap(UInt8(String(digits[index...index + 1]), radix: 16))
        }
    }

    func testRealSeriesUSBShareAndAReportsFromExclusiveCapture() throws {
        // Physical 045e:0b12, bcdDevice 0509, captured 2026-09-09. Unlike
        // Apple's 19-byte HID reports, endpoint 0x82 delivers all 48 bytes.
        let down = try capturedReport("20008e2c000000000000820062fcf1fcc9fb000000000100000000000000000000000000000000000f0de3f9cd0fe3f9")
        let up = try capturedReport("20008f2c000000000000820062fcf1fcc9fb000000000000000000000000000000000000000000006220e5f95e23e5f9")
        let a = try capturedReport("20009a2c10000000000082003dfdf1fcc9fb00000000000000000000000000000000000000000000c2dc33fa80df33fa")
        let samples: [([UInt8], Set<ControllerControlID>)] = [(down, [.share]), (up, []), (a, [.buttonSouth])]
        for stripped in [false, true] {
            var state = XboxUSBInputState()
            for (bytes, expected) in samples {
                XCTAssertEqual(bytes.count, 48)
                state = try XCTUnwrap(XboxUSBReportParser.parse(reportID: 0x20,
                    bytes: stripped ? Array(bytes.dropFirst()) : bytes,
                    previous: state, supportsShareButton: true))
                XCTAssertEqual(state.pressedControls, expected)
                XCTAssertEqual(state.analogValues[.share], expected.contains(.share) ? 1 : 0)
                XCTAssertFalse(state.shareRequiresFullUSB)
            }
        }
    }

    func testApplesTruncatedReportCannotDistinguishPhysicalSharePress() throws {
        let down = try capturedReport("20008e2c000000000000820062fcf1fcc9fb000000000100000000000000000000000000000000000f0de3f9cd0fe3f9")
        let state = try XCTUnwrap(XboxUSBReportParser.parse(reportID: 0x20,
            bytes: Array(down.prefix(19)), supportsShareButton: true))
        XCTAssertFalse(state.pressedControls.contains(.share))
        XCTAssertEqual(state.analogValues[.share], 0)
        XCTAssertTrue(state.shareRequiresFullUSB)
    }

    func testShareRequirementTracksTruncatedReportsWithoutPromptingLegacyDevices() throws {
        for stripped in [false, true] {
            let full = report(shareByte: 0)
            let truncated = Array(full.prefix(19))
            let bytes = stripped ? Array(truncated.dropFirst()) : truncated
            let series = try XCTUnwrap(XboxUSBReportParser.parse(reportID: 0x20,
                bytes: bytes, supportsShareButton: true))
            XCTAssertTrue(series.shareRequiresFullUSB)
            let legacy = try XCTUnwrap(XboxUSBReportParser.parse(reportID: 0x20, bytes: bytes))
            XCTAssertFalse(legacy.shareRequiresFullUSB)
            let guide = try XCTUnwrap(XboxUSBReportParser.parse(reportID: 0x07,
                bytes: [0x07, 0x30, 0, 0, 1], previous: series, supportsShareButton: true))
            XCTAssertTrue(guide.shareRequiresFullUSB)
            let restored = try XCTUnwrap(XboxUSBReportParser.parse(reportID: 0x20,
                bytes: stripped ? Array(full.dropFirst()) : full, previous: guide, supportsShareButton: true))
            XCTAssertFalse(restored.shareRequiresFullUSB)
        }
    }

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
        var defaults = ControllerProfile.gabesDefaults
        // A legacy saved profile without Share stays unassigned; new installs
        // now intentionally receive Gabe's saved slash/Shift-2/Shift-4 mappings.
        defaults.mappings.removeValue(forKey: .share)
        for index in defaults.modifierLayers.indices {
            defaults.modifierLayers[index].mappings.removeValue(forKey: .share)
        }
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
