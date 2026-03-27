@testable import VibeController
import XCTest
import simd

final class CursorMathTests: XCTestCase {
    func testDeadZoneZeroesSmallInput() {
        let vector = CursorMath.adjustedVector(x: 0.04, y: 0.02, deadZone: 0.12, responseCurve: 1.8)
        XCTAssertEqual(vector, .zero)
    }

    func testClampMagnitudeHonorsMaximum() {
        let vector = SIMD2<Double>(9, 0)
        let clamped = CursorMath.clampMagnitude(vector, maxLength: 3)
        XCTAssertEqual(simd_length(clamped), 3, accuracy: 0.0001)
    }

    func testSmoothingAlphaShrinksAsSliderIncreases() {
        XCTAssertGreaterThan(CursorMath.smoothingAlpha(for: 0.1), CursorMath.smoothingAlpha(for: 0.9))
    }
}
