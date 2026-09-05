import SwiftUI

/// Presentation-only input normalization. This never changes action thresholds or cursor output.
struct ControllerLiveFeedback {
    let pressedControls: Set<ControllerControlID>
    let analogValues: [ControllerControlID: Double]
    let leftStick: StickSnapshot
    let rightStick: StickSnapshot

    func amount(for control: ControllerControlID) -> Double {
        if control == .leftTrigger || control == .rightTrigger {
            return Self.unit(analogValues[control] ?? (pressedControls.contains(control) ? 1 : 0))
        }
        if control == .leftThumbstickButton, leftStick.pressed { return 1 }
        if control == .rightThumbstickButton, rightStick.pressed { return 1 }
        return pressedControls.contains(control) ? 1 : 0
    }

    func isActive(_ control: ControllerControlID) -> Bool { amount(for: control) > 0.02 }

    static func unit(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }

    static func stickVector(_ stick: StickSnapshot) -> CGVector {
        let x = stick.x.isFinite ? min(1, max(-1, stick.x)) : 0
        let y = stick.y.isFinite ? min(1, max(-1, stick.y)) : 0
        let magnitude = hypot(x, y)
        let divisor = max(1, magnitude)
        return CGVector(dx: x / divisor, dy: -y / divisor)
    }
}

struct LiveThumbstickView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let stick: StickSnapshot
    let isPressed: Bool
    let scale: CGFloat

    var body: some View {
        let vector = ControllerLiveFeedback.stickVector(stick)
        let active = hypot(vector.dx, vector.dy) > 0.10 || isPressed
        ZStack {
            // Cover the static cap in the SVG while preserving its original shape at rest.
            Circle().fill(Color(red: 0.055, green: 0.065, blue: 0.085))
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2 * scale))
            Circle().stroke(Color.accentColor.opacity(active ? 0.8 : 0), lineWidth: 3 * scale)
            Path { path in
                path.move(to: CGPoint(x: 67 * scale, y: 67 * scale))
                path.addLine(
                    to: CGPoint(
                        x: (67 + vector.dx * 28) * scale,
                        y: (67 + vector.dy * 28) * scale))
            }
            .stroke(Color.accentColor.opacity(0.65), lineWidth: 4 * scale)

            Circle()
                .fill(
                    RadialGradient(
                        colors: isPressed
                            ? [Color.accentColor, Color(red: 0.12, green: 0.25, blue: 0.48)]
                            : [Color(red: 0.22, green: 0.25, blue: 0.30), Color(red: 0.085, green: 0.10, blue: 0.13)],
                        center: .topLeading, startRadius: 0, endRadius: 94 * scale)
                )
                .overlay(Circle().stroke(Color.black.opacity(0.8), lineWidth: 5 * scale))
                .overlay(
                    Circle().inset(by: 6 * scale)
                        .stroke(isPressed ? Color.white.opacity(0.8) : Color.white.opacity(0.18), lineWidth: 2 * scale)
                )
                .overlay(
                    Circle().fill(active ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 6 * scale, height: 6 * scale)
                )
                .frame(width: 96 * scale, height: 96 * scale)
                .shadow(color: .black.opacity(0.5), radius: 4 * scale, y: isPressed ? scale : 5 * scale)
                .scaleEffect(isPressed && !reduceMotion ? 0.96 : 1)
                .offset(x: vector.dx * 28 * scale, y: vector.dy * 28 * scale)
                // Interpolate only the display between coalesced UI samples, never controller output.
                .animation(reduceMotion ? nil : .linear(duration: 0.055), value: vector)
        }
        .frame(width: 134 * scale, height: 134 * scale)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct LiveTriggerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let amount: Double
    let label: String
    let scale: CGFloat

    var body: some View {
        let amount = ControllerLiveFeedback.unit(amount)
        let shape = RoundedRectangle(cornerRadius: 16 * scale)
        ZStack(alignment: .bottom) {
            shape.fill(Color(red: 0.13, green: 0.16, blue: 0.21))
            Rectangle().fill(Color.accentColor.opacity(0.85))
                .frame(height: 48 * scale * amount)
            Text(label).font(.system(size: 16 * scale, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 116 * scale, height: 48 * scale)
        .clipShape(shape)
        .overlay(shape.stroke(Color.accentColor.opacity(amount > 0.02 ? 1 : 0), lineWidth: 3 * scale))
        .offset(y: reduceMotion ? 0 : 8 * scale * amount)
        .animation(reduceMotion ? nil : .linear(duration: 0.055), value: amount)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
