import AppKit
import SwiftUI

/// Artwork and native hit regions share a 1000 × 660 design space.
enum ControllerArtwork {
    static let size = CGSize(width: 1000, height: 660)

    @MainActor private static let images: [ControllerFamily: NSImage] = {
        var images: [ControllerFamily: NSImage] = [:]
        for family in [ControllerFamily.xbox, .playStation] {
            let name = family == .playStation ? "playstation" : "xbox"
            let url =
                Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Controllers")
                ?? Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "Controllers")
            if let url, let image = NSImage(contentsOf: url) { images[family] = image }
        }
        return images
    }()

    @MainActor static func image(for family: ControllerFamily) -> NSImage? {
        images[family == .playStation ? .playStation : .xbox]
    }

    static func controls(for family: ControllerFamily) -> [HardwareControlRegion] {
        let ps = family == .playStation
        var controls: [HardwareControlRegion] = [
            .init(.leftTrigger, 288, 118, 116, 48, radius: 18),
            .init(.rightTrigger, 712, 118, 116, 48, radius: 18),
            .init(.leftShoulder, 288, 171, 158, 46, radius: 19),
            .init(.rightShoulder, 712, 171, 158, 46, radius: 19),
            .init(.leftThumbstickButton, ps ? 380 : 283, ps ? 420 : 292, 134, 134, radius: 67),
            .init(.rightThumbstickButton, ps ? 620 : 600, 420, 134, 134, radius: 67),
            .init(.home, 500, ps ? 356 : 230, 50, 50, radius: 25),
            .init(.options, ps ? 351 : 446, ps ? 232 : 296, ps ? 32 : 48, ps ? 40 : 48, radius: ps ? 12 : 24),
            .init(.menu, ps ? 649 : 554, ps ? 232 : 296, ps ? 32 : 48, ps ? 40 : 48, radius: ps ? 12 : 24),
        ]
        let x: CGFloat = ps ? 737 : 743
        let y: CGFloat = ps ? 280 : 285
        controls += [
            .init(.buttonNorth, x, y - 58, 54, 54, radius: 27),
            .init(.buttonEast, x + 58, y, 54, 54, radius: 27),
            .init(.buttonSouth, x, y + 58, 54, 54, radius: 27),
            .init(.buttonWest, x - 58, y, 54, 54, radius: 27),
        ]
        let dx: CGFloat = ps ? 263 : 390
        let dy: CGFloat = ps ? 280 : 417
        controls += [
            .init(.dpadUp, dx, dy - 36, 35, 43, radius: 8),
            .init(.dpadDown, dx, dy + 36, 35, 43, radius: 8),
            .init(.dpadLeft, dx - 36, dy, 35, 28, radius: 8),
            .init(.dpadRight, dx + 36, dy, 35, 28, radius: 8),
        ]
        if ps { controls.append(.init(.touchpadButton, 500, 241, 230, 104, radius: 18)) }
        return controls
    }
}

struct HardwareControlRegion: Identifiable {
    let control: ControllerControlID
    let center: CGPoint
    let size: CGSize
    let radius: CGFloat
    var id: ControllerControlID { control }

    init(
        _ control: ControllerControlID, _ x: CGFloat, _ y: CGFloat,
        _ width: CGFloat, _ height: CGFloat, radius: CGFloat
    ) {
        self.control = control
        center = CGPoint(x: x, y: y)
        size = CGSize(width: width, height: height)
        self.radius = radius
    }
}

struct ControllerArtworkView: View {
    let family: ControllerFamily
    var body: some View {
        if let image = ControllerArtwork.image(for: family) {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                .accessibilityHidden(true)
        } else {
            Image(systemName: "gamecontroller").resizable().scaledToFit().padding(100)
                .foregroundStyle(.secondary)
        }
    }
}

struct ControllerHardwareMap: View {
    let family: ControllerFamily
    let pressedControls: Set<ControllerControlID>
    var analogValues: [ControllerControlID: Double] = [:]
    var overriddenControls: Set<ControllerControlID> = []
    var focusedControl: ControllerControlID? = nil
    let modifierControl: ControllerControlID?
    let leftStick: StickSnapshot
    let rightStick: StickSnapshot
    let actionDescription: (ControllerControlID) -> String
    let onSelect: (ControllerControlID) -> Void
    let onHover: (ControllerControlID?) -> Void

    var liveFeedback: ControllerLiveFeedback {
        ControllerLiveFeedback(
            pressedControls: pressedControls, analogValues: analogValues,
            leftStick: leftStick, rightStick: rightStick)
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / ControllerArtwork.size.width
            ZStack(alignment: .topLeading) {
                ControllerArtworkView(family: family)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                stickIndicator(.left, scale: scale)
                stickIndicator(.right, scale: scale)
                ForEach(ControllerArtwork.controls(for: family)) { region in
                    if region.control == .leftTrigger || region.control == .rightTrigger {
                        LiveTriggerView(
                            amount: liveFeedback.amount(for: region.control),
                            label: region.control.displayName(for: family), scale: scale
                        )
                        .position(x: region.center.x * scale, y: region.center.y * scale)
                    }
                    HardwareHitTarget(
                        region: region, family: family, scale: scale,
                        isPressed: liveFeedback.isActive(region.control),
                        isModifier: modifierControl == region.control,
                        isOverridden: overriddenControls.contains(region.control),
                        isFocused: focusedControl == region.control,
                        label: "\(region.control.displayName(for: family)): \(actionDescription(region.control))",
                        onSelect: { onSelect(region.control) },
                        onHover: { onHover($0 ? region.control : nil) }
                    )
                    .position(x: region.center.x * scale, y: region.center.y * scale)
                }
            }
        }
        .aspectRatio(ControllerArtwork.size, contentMode: .fit)
    }

    private func stickIndicator(_ side: StickSide, scale: CGFloat) -> some View {
        let vector = side == .left ? leftStick : rightStick
        let control: ControllerControlID = side == .left ? .leftThumbstickButton : .rightThumbstickButton
        let center = ControllerArtwork.controls(for: family).first { $0.control == control }!.center
        return LiveThumbstickView(stick: vector, isPressed: liveFeedback.isActive(control), scale: scale)
            .position(x: center.x * scale, y: center.y * scale)
    }
}

private struct HardwareHitTarget: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @State private var releaseHighlight = false
    @State private var releaseTask: Task<Void, Never>?
    let region: HardwareControlRegion
    let family: ControllerFamily
    let scale: CGFloat
    let isPressed: Bool
    let isModifier: Bool
    let isOverridden: Bool
    let isFocused: Bool
    let label: String
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        let analogControl = region.control == .leftTrigger || region.control == .rightTrigger
        let stickControl = region.control == .leftThumbstickButton || region.control == .rightThumbstickButton
        let pressed = isPressed || (!analogControl && releaseHighlight)
        let highlighted = pressed || isModifier || hovered || isFocused
        let shape = RoundedRectangle(cornerRadius: region.radius * scale)
        Button(action: onSelect) {
            shape.fill(
                Color.accentColor.opacity(
                    pressed && !analogControl && !stickControl
                        ? 0.85
                        : hovered || isFocused ? 0.18 : isModifier ? 0.22 : 0.001)
            )
            .overlay {
                shape.stroke(
                    Color.accentColor.opacity(highlighted ? 0.95 : isOverridden ? 0.6 : 0),
                    lineWidth: pressed ? 3 : 2)
            }
            .overlay {
                if pressed && !analogControl && !stickControl { pressedGlyph }
            }
            .shadow(color: Color.accentColor.opacity(highlighted ? 0.25 : 0), radius: 9)
            .contentShape(shape)
        }
        .buttonStyle(HardwarePressStyle())
        .frame(width: region.size.width * scale, height: region.size.height * scale)
        .onHover { value in
            hovered = value
            onHover(value)
        }
        .onChange(of: isPressed) { _, value in
            guard !analogControl else { return }
            releaseTask?.cancel()
            if value {
                releaseHighlight = true
            } else {
                // Keep short button taps visible; this does not hold the mapped action.
                releaseTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(110))
                    guard !Task.isCancelled else { return }
                    releaseHighlight = false
                }
            }
        }
        .onDisappear {
            releaseTask?.cancel()
            releaseHighlight = false
        }
        .animation(reduceMotion || pressed ? nil : .easeOut(duration: 0.10), value: highlighted)
        .accessibilityLabel(label)
        .accessibilityHint("Edit this controller mapping.")
        .accessibilityIdentifier("controller.\(region.control.rawValue)")
        .help(label)
    }

    @ViewBuilder private var pressedGlyph: some View {
        Group {
            switch region.control {
            case .buttonSouth, .buttonEast, .buttonWest, .buttonNorth:
                Text(region.control.diagramLabel(for: family)).font(.system(size: 25 * scale, weight: .bold))
            case .dpadUp: Image(systemName: "chevron.up")
            case .dpadDown: Image(systemName: "chevron.down")
            case .dpadLeft: Image(systemName: "chevron.left")
            case .dpadRight: Image(systemName: "chevron.right")
            case .leftShoulder, .rightShoulder:
                Text(region.control.displayName(for: family)).font(.system(size: 16 * scale, weight: .bold))
            default: Image(systemName: region.control.sfSymbolName)
            }
        }
        .font(.system(size: 20 * scale, weight: .bold))
        .foregroundStyle(.white)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct HardwarePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
