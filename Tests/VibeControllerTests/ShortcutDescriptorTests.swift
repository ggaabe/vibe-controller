@testable import VibeController
import XCTest

final class ShortcutDescriptorTests: XCTestCase {
    func testDisplayStringUsesMacModifierSymbols() {
        let shortcut = ShortcutDescriptor(keyCode: 19, modifiers: [.command, .shift])
        XCTAssertEqual(shortcut.displayString, "⇧⌘2")
    }

    func testModifierOnlyShortcutIsRejected() {
        let shortcut = ShortcutDescriptor(keyCode: 55, modifiers: [.command])
        XCTAssertTrue(shortcut.isModifierOnly)
    }

    func testFunctionKeyShortcutIsAllowed() {
        let shortcut = ShortcutDescriptor(keyCode: 63, modifiers: [])
        XCTAssertFalse(shortcut.isModifierOnly)
        XCTAssertEqual(shortcut.displayString, "fn")
    }

    func testFunctionKeyCodesHaveExpectedDisplayNames() throws {
        for number in 1...12 {
            let keyCode = try XCTUnwrap(ShortcutDescriptor.functionKeyCodes[number])
            XCTAssertEqual(
                ShortcutDescriptor(keyCode: keyCode, modifiers: []).displayString,
                "F\(number)"
            )
        }
    }

    func testMissionControlMediaKeyCapturesAsF3OnlyOnKeyDown() {
        let missionControlDown = Int64(2 << 16 | 0x0A << 8)
        let missionControlUp = Int64(2 << 16 | 0x0B << 8)
        let brightnessDown = Int64(3 << 16 | 0x0A << 8)

        XCTAssertEqual(
            ShortcutCaptureEventInterpreter.functionKeyCode(systemDefinedData1: missionControlDown),
            ShortcutDescriptor.functionKeyCodes[3]
        )
        XCTAssertNil(ShortcutCaptureEventInterpreter.functionKeyCode(systemDefinedData1: missionControlUp))
        XCTAssertNil(ShortcutCaptureEventInterpreter.functionKeyCode(systemDefinedData1: brightnessDown))
    }

    func testDeleteKeysAreAssignable() {
        XCTAssertFalse(ShortcutDescriptor(keyCode: 51, modifiers: []).isModifierOnly)
        XCTAssertEqual(ShortcutDescriptor(keyCode: 51, modifiers: []).displayString, "⌫")
        XCTAssertEqual(ShortcutDescriptor(keyCode: 117, modifiers: []).displayString, "⌦")
    }

    func testSystemConflictWarningForCommandSpace() {
        let shortcut = ShortcutDescriptor(keyCode: 49, modifiers: [.command])
        XCTAssertEqual(shortcut.knownSystemConflictWarning, "⌘Space is commonly reserved by Spotlight.")
    }
}
