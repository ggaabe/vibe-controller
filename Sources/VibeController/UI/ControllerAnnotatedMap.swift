import SwiftUI

/// Fixed label lanes keep every action readable without covering the controller.
/// Both the connector endpoints and native buttons use ControllerArtwork's coordinates.
struct ControllerCalloutLayout {
    static let minimumHeight: CGFloat = 448
    let artworkFrame: CGRect
    let callouts: [ControllerCalloutPlacement]

    init(family: ControllerFamily, size: CGSize) {
        let labelWidth = min(190, size.width * 0.20)
        let availableWidth = max(1, size.width - 2 * (labelWidth + 18))
        let artworkWidth = min(availableWidth, size.height / 0.66)
        let artworkSize = CGSize(width: artworkWidth, height: artworkWidth * 0.66)
        artworkFrame = CGRect(
            x: (size.width - artworkSize.width) / 2,
            y: (size.height - artworkSize.height) / 2,
            width: artworkSize.width, height: artworkSize.height)

        let left: [ControllerControlID]
        if family == .playStation {
            left = [
                .leftTrigger, .leftShoulder, .options, .touchpadButton,
                .dpadUp, .dpadLeft, .dpadRight, .dpadDown, .leftThumbstickButton,
            ]
        } else {
            left = [
                .leftTrigger, .leftShoulder, .home, .leftThumbstickButton, .options,
                .dpadUp, .dpadLeft, .dpadRight, .dpadDown,
            ]
        }
        let regions = ControllerArtwork.controls(for: family)
        let right = regions.filter { !left.contains($0.control) }
            .sorted {
                if $0.center.y == $1.center.y { return $0.center.x < $1.center.x }
                return $0.center.y < $1.center.y
            }.map(\.control)
        let rowCount = max(left.count, right.count)
        let rowHeight = (size.height - 24) / CGFloat(rowCount)
        let frame = artworkFrame

        callouts = [(left, true), (right, false)].flatMap { controls, isLeft in
            controls.enumerated().compactMap { index, control in
                guard let region = regions.first(where: { $0.control == control }) else { return nil }
                let y = 12 + rowHeight * (CGFloat(index) + 0.5)
                let labelFrame = CGRect(
                    x: isLeft ? 4 : size.width - labelWidth - 4, y: y - 22,
                    width: labelWidth, height: 44)
                let anchor = CGPoint(
                    x: frame.minX + region.center.x * frame.width / 1000,
                    y: frame.minY + region.center.y * frame.height / 660)
                let origin = CGPoint(x: isLeft ? labelFrame.maxX + 4 : labelFrame.minX - 4, y: y)
                return ControllerCalloutPlacement(
                    control: control, labelFrame: labelFrame, anchor: anchor,
                    origin: origin, elbow: CGPoint(x: origin.x + (isLeft ? 12 : -12), y: y))
            }
        }
    }
}

struct ControllerCalloutPlacement: Identifiable {
    let control: ControllerControlID
    let labelFrame: CGRect
    let anchor: CGPoint
    let origin: CGPoint
    let elbow: CGPoint
    var id: ControllerControlID { control }
}

struct ControllerAnnotatedMap: View {
    let hardware: ControllerHardwareMap
    let hoveredControl: ControllerControlID?

    var body: some View {
        GeometryReader { proxy in
            let layout = ControllerCalloutLayout(family: hardware.family, size: proxy.size)
            ZStack(alignment: .topLeading) {
                hardware
                    .frame(width: layout.artworkFrame.width, height: layout.artworkFrame.height)
                    .position(x: layout.artworkFrame.midX, y: layout.artworkFrame.midY)

                ForEach(layout.callouts) { callout in
                    let active =
                        hoveredControl == callout.control
                        || hardware.liveFeedback.isActive(callout.control)
                        || hardware.modifierControl == callout.control
                    let overridden = hardware.overriddenControls.contains(callout.control)
                    Path { path in
                        path.move(to: callout.origin)
                        path.addLine(to: callout.elbow)
                        path.addLine(to: callout.anchor)
                    }
                    .stroke(
                        active ? Color.accentColor : Color.secondary.opacity(0.30),
                        style: StrokeStyle(lineWidth: active ? 1.5 : 0.75, lineCap: .round, lineJoin: .round)
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    Circle()
                        .fill(active ? Color.accentColor : Color.secondary.opacity(0.6))
                        .frame(width: active ? 5 : 3, height: active ? 5 : 3)
                        .position(callout.anchor)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    ControllerActionLabel(
                        name: callout.control.displayName(for: hardware.family),
                        action: hardware.actionDescription(callout.control),
                        active: active, overridden: overridden,
                        onSelect: { hardware.onSelect(callout.control) },
                        onHover: { hardware.onHover($0 ? callout.control : nil) }
                    )
                    .frame(width: callout.labelFrame.width, height: callout.labelFrame.height)
                    .position(x: callout.labelFrame.midX, y: callout.labelFrame.midY)
                    .accessibilityIdentifier("controller-label.\(callout.control.rawValue)")
                }
            }
        }
    }
}

private struct ControllerActionLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let name: String
    let action: String
    let active: Bool
    let overridden: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(active || overridden ? Color.accentColor : .secondary)
                Text(action)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                Color.accentColor.opacity(active ? 0.12 : overridden ? 0.045 : 0),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(HardwarePressStyle())
        .onHover(perform: onHover)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: active)
        .accessibilityLabel("\(name): \(action)")
        .accessibilityHint("Edit this controller mapping.")
        .help("\(name): \(action)")
    }
}
