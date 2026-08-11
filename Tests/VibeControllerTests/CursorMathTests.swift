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

    func testVeryFastSweepReachesMaximumBoost() {
        XCTAssertEqual(
            CursorMath.flickBoostMultiplier(sweepDuration: 0.04),
            2,
            accuracy: 0.000_001
        )
    }

    func testBorderlineSweepAddsOnlyPartialBoost() {
        let boost = CursorMath.flickBoostMultiplier(sweepDuration: 0.055)
        XCTAssertGreaterThan(boost, 1.3)
        XCTAssertLessThan(boost, 1.5)
    }

    func testSlowSweepDoesNotBoost() {
        XCTAssertEqual(CursorMath.flickBoostMultiplier(sweepDuration: 0.08), 1)
    }

    func testTrackerRequiresCenterBeforeFlick() {
        var tracker = FlickBoostTracker()
        XCTAssertEqual(tracker.update(vector: SIMD2<Double>(1, 0), at: 0), 1)

        XCTAssertEqual(tracker.update(vector: .zero, at: 1), 1)
        XCTAssertEqual(tracker.update(vector: SIMD2<Double>(0.4, 0), at: 1.01), 1)
        XCTAssertEqual(tracker.update(vector: SIMD2<Double>(1, 0), at: 1.04), 2)
    }

    func testTrackerTreatsCardinalAndDiagonalSweepsEqually() {
        var cardinalTracker = FlickBoostTracker()
        XCTAssertEqual(cardinalTracker.update(vector: .zero, at: 0), 1)
        XCTAssertEqual(cardinalTracker.update(vector: SIMD2<Double>(0.4, 0), at: 0.01), 1)
        let cardinalBoost = cardinalTracker.update(vector: SIMD2<Double>(0.93, 0), at: 0.06)

        var diagonalTracker = FlickBoostTracker()
        XCTAssertEqual(diagonalTracker.update(vector: .zero, at: 0), 1)
        XCTAssertEqual(diagonalTracker.update(vector: SIMD2<Double>(0.3, 0.3), at: 0.01), 1)
        let diagonalBoost = diagonalTracker.update(vector: SIMD2<Double>(0.66, 0.66), at: 0.06)

        XCTAssertEqual(cardinalBoost, diagonalBoost, accuracy: 0.000_001)
        XCTAssertGreaterThan(cardinalBoost, 1)
    }

    func testTrackerDoesNotRetriggerFromOuterRingJitter() {
        var tracker = FlickBoostTracker()
        XCTAssertEqual(tracker.update(vector: .zero, at: 0), 1)
        XCTAssertEqual(tracker.update(vector: SIMD2<Double>(0.4, 0), at: 0.01), 1)
        XCTAssertGreaterThan(tracker.update(vector: SIMD2<Double>(1, 0), at: 0.05), 1)

        XCTAssertEqual(tracker.update(vector: SIMD2<Double>(0.65, 0.65), at: 0.06), 1)
        XCTAssertEqual(tracker.update(vector: SIMD2<Double>(0.7, 0.7), at: 0.07), 1)
        XCTAssertEqual(tracker.update(vector: SIMD2<Double>(0, 1), at: 0.08), 1)
    }

    func testTrackerDisarmsAContinuousSlowSweep() {
        var tracker = FlickBoostTracker()
        XCTAssertEqual(tracker.update(vector: .zero, at: 0), 1)
        XCTAssertEqual(tracker.update(vector: SIMD2<Double>(0.4, 0), at: 0.01), 1)
        XCTAssertEqual(tracker.update(vector: SIMD2<Double>(0.7, 0), at: 0.08), 1)
        XCTAssertEqual(tracker.update(vector: SIMD2<Double>(1, 0), at: 0.09), 1)
    }

    func testFlickBoostDecaysBackToNormalSpeed() {
        XCTAssertEqual(CursorMath.decayedFlickBoost(2, elapsedTime: 1), 1.5, accuracy: 0.000_001)
        XCTAssertEqual(CursorMath.decayedFlickBoost(2, elapsedTime: 2), 1, accuracy: 0.000_001)
    }

    func testCrossEdgeSweepsMirrorEachOtherWithoutVerticalMovement() {
        var leftSweep = CrossEdgeSweep(direction: .left)
        var rightSweep = CrossEdgeSweep(direction: .right)

        let leftDelta = leftSweep.nextDelta(elapsedTime: 1.0 / 120.0)
        let rightDelta = rightSweep.nextDelta(elapsedTime: 1.0 / 120.0)

        XCTAssertEqual(leftDelta.x, -rightDelta.x, accuracy: 0.000_001)
        XCTAssertEqual(leftDelta.y, 0)
        XCTAssertEqual(rightDelta.y, 0)
    }

    func testVerticalCrossEdgeSweepsMirrorEachOtherWithoutHorizontalMovement() {
        var upSweep = CrossEdgeSweep(direction: .up)
        var downSweep = CrossEdgeSweep(direction: .down)

        let upDelta = upSweep.nextDelta(elapsedTime: 1.0 / 120.0)
        let downDelta = downSweep.nextDelta(elapsedTime: 1.0 / 120.0)

        XCTAssertEqual(upDelta.y, -downDelta.y, accuracy: 0.000_001)
        XCTAssertEqual(upDelta.x, 0)
        XCTAssertEqual(downDelta.x, 0)
    }

    func testCrossEdgeSweepDistanceIsBoundedAndCadenceIndependent() {
        let expectedDistance = CrossEdgeSweep.speed * CrossEdgeSweep.duration
        XCTAssertEqual(expectedDistance, CrossEdgeSweep.targetDistance, accuracy: 0.000_001)
        XCTAssertEqual(
            consumedCrossEdgeDistance(frameDuration: 1.0 / 120.0),
            expectedDistance,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            consumedCrossEdgeDistance(frameDuration: 1.0 / 60.0),
            expectedDistance,
            accuracy: 0.000_001
        )
    }

    func testCrossEdgeSweepIgnoresNegativeElapsedTime() {
        var sweep = CrossEdgeSweep(direction: .right)
        let initialRemainingDuration = sweep.remainingDuration

        XCTAssertEqual(sweep.nextDelta(elapsedTime: -1), .zero)
        XCTAssertEqual(sweep.remainingDuration, initialRemainingDuration)
    }

    private func consumedCrossEdgeDistance(frameDuration: Double) -> Double {
        var sweep = CrossEdgeSweep(direction: .right)
        var distance = 0.0
        while !sweep.isComplete {
            distance += sweep.nextDelta(elapsedTime: frameDuration).x
        }
        return distance
    }
}
