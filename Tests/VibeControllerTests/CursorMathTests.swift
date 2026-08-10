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

    func testElapsedDurationPreservesShortSchedulingStalls() {
        XCTAssertEqual(CursorMath.elapsedDuration(from: 10, to: 10.05), 0.05, accuracy: 0.000_001)
    }

    func testElapsedDurationCapsLongSuspensions() {
        XCTAssertEqual(
            CursorMath.elapsedDuration(from: 10, to: 11),
            CursorMath.maximumCatchUpDuration,
            accuracy: 0.000_001
        )
    }

    func testSmoothingIsStableAcrossOutputCadences() {
        let target = SIMD2<Double>(1_000, -500)
        var at120Hz = SIMD2<Double>.zero
        var at60Hz = SIMD2<Double>.zero

        for _ in 0..<120 {
            at120Hz = CursorMath.blend(
                current: at120Hz,
                target: target,
                smoothing: 0.9,
                elapsedTime: 1.0 / 120.0
            )
        }
        for _ in 0..<60 {
            at60Hz = CursorMath.blend(
                current: at60Hz,
                target: target,
                smoothing: 0.9,
                elapsedTime: 1.0 / 60.0
            )
        }

        XCTAssertEqual(at120Hz.x, at60Hz.x, accuracy: 0.000_001)
        XCTAssertEqual(at120Hz.y, at60Hz.y, accuracy: 0.000_001)
    }

    func testFastOutwardStickFlickReachesMaximumBoost() {
        let boost = CursorMath.flickBoostMultiplier(
            previous: .zero,
            current: SIMD2<Double>(1, 0),
            elapsedTime: 0.08
        )

        XCTAssertEqual(boost, 2, accuracy: 0.000_001)
    }

    func testQuickOutwardStickFlickAddsPartialBoost() {
        let boost = CursorMath.flickBoostMultiplier(
            previous: .zero,
            current: SIMD2<Double>(1, 0),
            elapsedTime: 0.15
        )

        XCTAssertGreaterThan(boost, 1.4)
        XCTAssertLessThan(boost, 1.6)
    }

    func testSlowOrInwardStickMovementDoesNotBoost() {
        XCTAssertEqual(
            CursorMath.flickBoostMultiplier(
                previous: .zero,
                current: SIMD2<Double>(1, 0),
                elapsedTime: 0.5
            ),
            1
        )
        XCTAssertEqual(
            CursorMath.flickBoostMultiplier(
                previous: SIMD2<Double>(1, 0),
                current: SIMD2<Double>(0.75, 0),
                elapsedTime: 0.02
            ),
            1
        )
    }

    func testFlickBoostRequiresStickNearEdge() {
        let boost = CursorMath.flickBoostMultiplier(
            previous: .zero,
            current: SIMD2<Double>(0.5, 0),
            elapsedTime: 0.02
        )

        XCTAssertEqual(boost, 1)
    }

    func testFlickBoostDecaysBackToNormalSpeed() {
        XCTAssertEqual(CursorMath.decayedFlickBoost(2, elapsedTime: 0.225), 1.5, accuracy: 0.000_001)
        XCTAssertEqual(CursorMath.decayedFlickBoost(2, elapsedTime: 0.45), 1, accuracy: 0.000_001)
    }
}
