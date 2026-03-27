import SwiftUI

struct ControllerDiagramView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Controller Map")
                    .font(.title2.weight(.semibold))
                Spacer()
                if appModel.controllerSnapshot.isConnected {
                    Text("Click any control to remap. Live input highlights in blue.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            ControllerCanvas(canvasColors: canvasColors, borderColor: borderColor)
                .frame(minHeight: 420, idealHeight: 520, maxHeight: 560)
                .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private var canvasColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.15, green: 0.17, blue: 0.21),
                Color(red: 0.10, green: 0.12, blue: 0.16),
            ]
        }
        return [
            Color(red: 0.96, green: 0.97, blue: 0.99),
            Color(red: 0.88, green: 0.91, blue: 0.96),
        ]
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
}

private struct ControllerCanvas: View {
    let canvasColors: [Color]
    let borderColor: Color

    private static let designSize = CGSize(width: 1000, height: 620)

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scale = min(size.width / Self.designSize.width, size.height / Self.designSize.height)
            let fittedSize = CGSize(
                width: Self.designSize.width * scale,
                height: Self.designSize.height * scale
            )

            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: canvasColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)

                controllerLayout
                    .frame(width: Self.designSize.width, height: Self.designSize.height, alignment: .topLeading)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: fittedSize.width, height: fittedSize.height, alignment: .topLeading)
                    .padding(18)
            }
            .frame(width: fittedSize.width + 36, height: fittedSize.height + 36)
            .position(x: size.width / 2, y: size.height / 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controllerLayout: some View {
        ZStack(alignment: .topLeading) {
            PositionedNode(x: 120, y: 52) {
                ControlNode(control: .leftShoulder, style: .wide)
            }
            PositionedNode(x: 120, y: 130) {
                ControlNode(control: .leftTrigger, style: .wide, showsLevel: true)
            }
            PositionedNode(x: 500, y: 80) {
                ControlNode(control: .home, style: .compact)
            }
            PositionedNode(x: 880, y: 52) {
                ControlNode(control: .rightShoulder, style: .wide)
            }
            PositionedNode(x: 880, y: 130) {
                ControlNode(control: .rightTrigger, style: .wide, showsLevel: true)
            }

            PositionedNode(x: 165, y: 250) {
                ControlNode(control: .options, style: .compact)
            }
            PositionedNode(x: 265, y: 250) {
                ControlNode(control: .menu, style: .compact)
            }

            PositionedNode(x: 190, y: 340) {
                ControlNode(control: .dpadUp, style: .compact)
            }
            PositionedNode(x: 120, y: 410) {
                ControlNode(control: .dpadLeft, style: .compact)
            }
            PositionedNode(x: 260, y: 410) {
                ControlNode(control: .dpadRight, style: .compact)
            }
            PositionedNode(x: 190, y: 480) {
                ControlNode(control: .dpadDown, style: .compact)
            }

            PositionedNode(x: 200, y: 530) {
                StickNode(side: .left)
            }
            PositionedNode(x: 330, y: 560) {
                ControlNode(control: .leftThumbstickButton, style: .compact)
            }

            PositionedNode(x: 830, y: 210) {
                FaceButtonsCluster()
            }
            PositionedNode(x: 820, y: 530) {
                StickNode(side: .right)
            }
            PositionedNode(x: 690, y: 560) {
                ControlNode(control: .rightThumbstickButton, style: .compact)
            }
        }
    }
}

private struct PositionedNode<Content: View>: View {
    let x: CGFloat
    let y: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .position(x: x, y: y)
    }
}

private struct FaceButtonsCluster: View {
    var body: some View {
        VStack(spacing: 10) {
            ControlNode(control: .buttonNorth, style: .round)
            HStack(spacing: 10) {
                ControlNode(control: .buttonWest, style: .round)
                ControlNode(control: .buttonEast, style: .round)
            }
            ControlNode(control: .buttonSouth, style: .round)
        }
    }
}

private struct StickNode: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.colorScheme) private var colorScheme

    let side: StickSide

    var body: some View {
        let snapshot = side == .left ? appModel.controllerSnapshot.leftStick : appModel.controllerSnapshot.rightStick
        Button {
            appModel.presentStickSheet(for: side)
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(baseFill)
                        .frame(width: 118, height: 118)
                    Circle()
                        .strokeBorder(borderColor, lineWidth: 1)
                        .frame(width: 118, height: 118)
                    Circle()
                        .fill(Color.accentColor.opacity(0.45))
                        .frame(width: 32, height: 32)
                        .offset(x: snapshot.x * 28, y: -snapshot.y * 28)
                }
                Text(appModel.mappingSummary(for: side == .left ? .leftThumbstick : .rightThumbstick))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var baseFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
    }
}

private struct ControlNode: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.colorScheme) private var colorScheme

    enum Style {
        case round
        case compact
        case wide
    }

    let control: ControllerControlID
    let style: Style
    var showsLevel = false

    private var isPressed: Bool {
        appModel.controllerSnapshot.pressedControls.contains(control)
    }

    private var level: Double {
        appModel.controllerSnapshot.value(for: control)
    }

    var body: some View {
        Button {
            appModel.presentMapping(for: control)
        } label: {
            VStack(spacing: 6) {
                Text(control.displayName)
                    .font(labelFont)
                    .foregroundStyle(.primary)
                    .frame(width: width, height: height)
                    .background {
                        switch style {
                        case .round:
                            Circle().fill(backgroundColor)
                        case .compact:
                            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(backgroundColor)
                        case .wide:
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(backgroundColor)
                        }
                    }
                    .overlay {
                        switch style {
                        case .round:
                            Circle().stroke(borderColor, lineWidth: 1)
                        case .compact:
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(borderColor, lineWidth: 1)
                        case .wide:
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(borderColor, lineWidth: 1)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if showsLevel {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.65))
                                .frame(width: width * 0.78, height: 6)
                                .padding(.bottom, 10)
                                .mask(alignment: .leading) {
                                    Rectangle()
                                        .frame(width: max(4, (width * 0.78) * level))
                                }
                        }
                    }
                Text(appModel.mappingSummary(for: control))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: textWidth)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
    }

    private var labelFont: Font {
        switch style {
        case .round:
            return .headline.weight(.semibold)
        case .compact:
            return .subheadline.weight(.semibold)
        case .wide:
            return .subheadline.weight(.semibold)
        }
    }

    private var width: CGFloat {
        switch style {
        case .round:
            return 74
        case .compact:
            return 58
        case .wide:
            return 136
        }
    }

    private var height: CGFloat {
        switch style {
        case .round:
            return 74
        case .compact:
            return 58
        case .wide:
            return 56
        }
    }

    private var textWidth: CGFloat {
        switch style {
        case .wide:
            return 150
        case .round:
            return 90
        case .compact:
            return 100
        }
    }

    private var backgroundColor: Color {
        if isPressed {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.55 : 0.35)
        }
        return colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.72)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }
}
