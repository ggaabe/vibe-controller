import Foundation
import simd

enum CursorMath {
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

    static func blend(current: SIMD2<Double>, target: SIMD2<Double>, smoothing: Double) -> SIMD2<Double> {
        let alpha = smoothingAlpha(for: smoothing)
        return current + ((target - current) * alpha)
    }
}
