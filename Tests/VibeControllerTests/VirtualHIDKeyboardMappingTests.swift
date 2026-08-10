import CoreGraphics
import XCTest
@testable import VibeController

final class VirtualHIDKeyboardMappingTests: XCTestCase {
    func testGabesDefaultShortcutKeysMapToUSBHIDUsages() {
        XCTAssertEqual(UniversalControlInputBridge.hidUsageByMacKeyCode[53], 0x29) // Escape
        XCTAssertEqual(UniversalControlInputBridge.hidUsageByMacKeyCode[21], 0x21) // 4
        XCTAssertEqual(UniversalControlInputBridge.hidUsageByMacKeyCode[19], 0x1f) // 2
        XCTAssertEqual(UniversalControlInputBridge.hidUsageByMacKeyCode[9], 0x19) // V
        XCTAssertEqual(UniversalControlInputBridge.hidUsageByMacKeyCode[36], 0x28) // Return
        XCTAssertEqual(UniversalControlInputBridge.hidUsageByMacKeyCode[51], 0x2a) // Delete
    }

    func testMacModifierFlagsMapToHIDModifierBitmap() {
        let flags: CGEventFlags = [.maskControl, .maskShift, .maskCommand]
        XCTAssertEqual(UniversalControlInputBridge.hidModifiers(for: flags), 0x0b)
    }

    func testPhysicalModifierKeyCodesMapToTheCorrectSide() {
        XCTAssertEqual(UniversalControlInputBridge.modifierKeyBits[55], 0x08)
        XCTAssertEqual(UniversalControlInputBridge.modifierKeyBits[54], 0x80)
        XCTAssertEqual(UniversalControlInputBridge.modifierKeyBits[59], 0x01)
        XCTAssertEqual(UniversalControlInputBridge.modifierKeyBits[62], 0x10)
    }
}
