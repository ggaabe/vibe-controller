import Foundation
import simd

enum StickZoomDirection: Equatable, Sendable {
    case zoomIn
    case zoomOut

    var displayName: String {
        switch self {
        case .zoomIn:
            return "Zoom In"
        case .zoomOut:
            return "Zoom Out"
        }
    }
}

struct StickZoomSample: Equatable, Sendable {
    var direction: StickZoomDirection
    var magnitude: Double
}

enum CursorMath {
    static let referenceFrameDuration = 1.0 / 120.0
    static let maximumCatchUpDuration = 0.1
    static let maximumFlickBoost = 2.0
    static let flickBoostDecayDuration = 2.0
    static let flickSweepStartMagnitude = 0.25
    static let flickFullThrowMagnitude = 0.92
    static let flickActivationDuration = 0.065
    static let flickFullBoostDuration = 0.04
    static let zoomGestureActivationThreshold = 0.55
    static let zoomGestureReleaseThreshold = 0.42

    static func adjustedVector(
        x: Double,
        y: Double,
        deadZone: Double,
        responseCurve: Double
    ) -> SIMD2<Double> {
        let raw = SIMD2<Double>(x, y)
        let magnitude = simd_length(raw)
        guard magnitude > 0 else {
            return .zero
        }

        guard magnitude > deadZone else {
            return .zero
        }

        let normalizedMagnitude = (magnitude - deadZone) / max(0.0001, 1 - deadZone)
        let curvedMagnitude = pow(min(max(normalizedMagnitude, 0), 1), responseCurve)
        let direction = raw / magnitude
        return direction * curvedMagnitude
    }

    static func clampMagnitude(_ vector: SIMD2<Double>, maxLength: Double) -> SIMD2<Double> {
        let magnitude = simd_length(vector)
        guard magnitude > maxLength, magnitude > 0 else {
            return vector
        }

        return (vector / magnitude) * maxLength
    }

    static func smoothingAlpha(for sliderValue: Double) -> Double {
        let clamped = min(max(sliderValue, 0), 1)
        return max(0.15, 1.0 - (clamped * 0.85))
    }

    static func elapsedDuration(from previousTime: Double, to currentTime: Double) -> Double {
        min(max(currentTime - previousTime, 0), maximumCatchUpDuration)
    }

    static func flickBoostMultiplier(
        sweepDuration: Double,
        activationDuration: Double = flickActivationDuration,
        fullBoostDuration: Double = flickFullBoostDuration,
        maximumMultiplier: Double = maximumFlickBoost
    ) -> Double {
        guard sweepDuration >= 0,
              activationDuration > fullBoostDuration,
              maximumMultiplier > 1 else {
            return 1
        }

        let normalizedSpeed = min(
            max((activationDuration - sweepDuration) / (activationDuration - fullBoostDuration), 0),
            1
        )
        return 1 + (normalizedSpeed * (maximumMultiplier - 1))
    }

    static func decayedFlickBoost(
        _ multiplier: Double,
        elapsedTime: Double,
        maximumMultiplier: Double = maximumFlickBoost,
        decayDuration: Double = flickBoostDecayDuration
    ) -> Double {
        guard multiplier > 1, elapsedTime > 0, decayDuration > 0 else {
            return max(1, min(multiplier, maximumMultiplier))
        }

        let decayPerSecond = (maximumMultiplier - 1) / decayDuration
        return max(1, min(multiplier, maximumMultiplier) - (decayPerSecond * elapsedTime))
    }

    static func blend(
        current: SIMD2<Double>,
        target: SIMD2<Double>,
        smoothing: Double,
        elapsedTime: Double = referenceFrameDuration
    ) -> SIMD2<Double> {
        let baseAlpha = smoothingAlpha(for: smoothing)
        let frameCount = max(0, elapsedTime / referenceFrameDuration)
        let alpha = 1.0 - pow(1.0 - baseAlpha, frameCount)
        return current + ((target - current) * alpha)
    }

    static func zoomGestureSample(
        stick: StickSnapshot,
        threshold: Double = zoomGestureActivationThreshold
    ) -> StickZoomSample? {
        let verticalMagnitude = abs(stick.y)
        let horizontalMagnitude = abs(stick.x)
        guard verticalMagnitude >= threshold,
              verticalMagnitude >= horizontalMagnitude * 0.85 else {
            return nil
        }

        return StickZoomSample(
            direction: stick.y > 0 ? .zoomIn : .zoomOut,
            magnitude: min(max(verticalMagnitude, 0), 1)
        )
    }

    static func zoomRepeatInterval(for magnitude: Double) -> Double {
        let normalized = min(max(
            (magnitude - zoomGestureActivationThreshold)
                / (1 - zoomGestureActivationThreshold),
            0
        ), 1)
        return 0.28 - (normalized * 0.205)
    }
}

struct StickZoomRepeater: Sendable {
    private(set) var activeDirection: StickZoomDirection?
    private var nextStepTime = 0.0

    var isActive: Bool { activeDirection != nil }

    mutating func reset() {
        activeDirection = nil
        nextStepTime = 0
    }

    mutating func update(
        stick: StickSnapshot,
        modifierPressed: Bool,
        enabled: Bool,
        at currentTime: Double
    ) -> StickZoomDirection? {
        guard enabled, modifierPressed else {
            reset()
            return nil
        }

        let threshold = activeDirection == nil
            ? CursorMath.zoomGestureActivationThreshold
            : CursorMath.zoomGestureReleaseThreshold
        guard let sample = CursorMath.zoomGestureSample(stick: stick, threshold: threshold) else {
            reset()
            return nil
        }

        let interval = CursorMath.zoomRepeatInterval(for: sample.magnitude)
        if activeDirection != sample.direction {
            activeDirection = sample.direction
            nextStepTime = currentTime + interval
            return sample.direction
        }

        guard currentTime >= nextStepTime else { return nil }
        nextStepTime = currentTime + interval
        return sample.direction
    }
}

struct FlickBoostTracker: Sendable {
    private enum State: Sendable {
        case waitingForCenter
        case armed
        case tracking(startedAt: Double)
        case disarmed
    }

    private var state: State = .waitingForCenter

    mutating func reset() {
        state = .waitingForCenter
    }

    mutating func update(vector: SIMD2<Double>, at currentTime: Double) -> Double {
        let magnitude = simd_length(vector)
        if magnitude <= CursorMath.flickSweepStartMagnitude {
            state = .armed
            return 1
        }

        switch state {
        case .waitingForCenter, .disarmed:
            return 1
        case .armed:
            if magnitude >= CursorMath.flickFullThrowMagnitude {
                state = .disarmed
                return CursorMath.maximumFlickBoost
            }
            state = .tracking(startedAt: currentTime)
            return 1
        case let .tracking(startedAt):
            let sweepDuration = max(0, currentTime - startedAt)
            guard sweepDuration <= CursorMath.flickActivationDuration else {
                state = .disarmed
                return 1
            }
            guard magnitude >= CursorMath.flickFullThrowMagnitude else { return 1 }

            state = .disarmed
            return CursorMath.flickBoostMultiplier(sweepDuration: sweepDuration)
        }
    }
}

struct CrossEdgeSweep: Sendable {
    static let speed = 6_000.0
    static let targetDistance = 1_500.0
    static let duration = targetDistance / speed

    let direction: CrossEdgeDirection
    private(set) var remainingDuration: Double

    init(direction: CrossEdgeDirection) {
        self.direction = direction
        remainingDuration = Self.duration
    }

    var isComplete: Bool {
        remainingDuration <= 0
    }

    mutating func nextDelta(elapsedTime: Double) -> SIMD2<Double> {
        let appliedDuration = min(max(elapsedTime, 0), remainingDuration)
        remainingDuration -= appliedDuration
        return direction.motionVector * Self.speed * appliedDuration
    }
}
