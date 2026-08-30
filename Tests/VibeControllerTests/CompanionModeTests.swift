import XCTest
@testable import VibeController

final class CompanionModeTests: XCTestCase {
    func testFreshInstallsDefaultToNativeUniversalControl() {
        XCTAssertEqual(CompanionMode.defaultMode, .off)
        XCTAssertEqual(CompanionMode.resolvedMode(from: nil), .off)
        XCTAssertEqual(CompanionMode.defaultMode.displayName, "Native Universal Control")
    }

    func testUnknownLegacyPreferenceFallsBackToNativeUniversalControl() {
        XCTAssertEqual(CompanionMode.resolvedMode(from: "retired-mode"), .off)
    }

    func testExplicitNetworkFallbackPreferenceIsPreserved() {
        XCTAssertEqual(CompanionMode.resolvedMode(from: CompanionMode.controller.rawValue), .controller)
        XCTAssertEqual(CompanionMode.resolvedMode(from: CompanionMode.receiver.rawValue), .receiver)
    }
}
