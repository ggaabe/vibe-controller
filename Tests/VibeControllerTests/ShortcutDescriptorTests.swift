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
