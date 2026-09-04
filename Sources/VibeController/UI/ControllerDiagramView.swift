import SwiftUI

struct ControllerDiagramView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isConfirmingLayerRemoval = false
    @State private var pendingApplicationAction: PendingApplicationMappingAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                ProductSectionTitle(
                    "Controller Map",
                    subtitle: appModel.controllerSnapshot.isConnected
                        ? "Select a control to change its action. Live input lights up in blue."
                        : "Your mappings are ready while Vibe Controller waits for a gamepad.",
                    symbol: "gamecontroller.fill"
                )
                Spacer()
                if appModel.controllerSnapshot.isConnected {
                    Text(appModel.controllerSnapshot.controllerFamily == .playStation ? "PlayStation layout" : "Xbox layout")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.08), in: Capsule())
                }
            }

            applicationScopeToolbar

            HStack(spacing: 10) {
                Label("Layer", systemImage: "square.3.layers.3d")
                    .font(.subheadline.weight(.semibold))

                Picker(
                    "Mapping layer",
                    selection: Binding(
                        get: { appModel.visibleMappingLayer },
                        set: { appModel.selectMappingLayer($0) }
                    )
                ) {
                    ForEach(appModel.mappingLayers) { layer in
                        Text(appModel.mappingLayerDisplayName(layer)).tag(layer)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
                .frame(minHeight: 40)
                .disabled(appModel.liveModifierPreviewControl != nil)

                if let previewControl = appModel.liveModifierPreviewControl {
                    Label(
                        "Live · \(appModel.controlDisplayName(previewControl)) held",
                        systemImage: "eye.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                Menu {
                    ForEach(appModel.availableModifierControls) { control in
                        Button(appModel.controlDisplayName(control)) {
                            appModel.addModifierLayer(control)
                        }
                    }
                } label: {
                    Label("Add Modifier", systemImage: "plus")
                }
                .frame(minHeight: 40)
                .disabled(
                    appModel.availableModifierControls.isEmpty ||
                        appModel.liveModifierPreviewControl != nil
                )

                if appModel.liveModifierPreviewControl == nil,
                   let modifierControl = appModel.selectedModifierControl {
                    Button(role: .destructive) {
                        isConfirmingLayerRemoval = true
                    } label: {
                        Label("Remove Layer", systemImage: "trash")
                    }
                    .frame(minHeight: 40)
                    .accessibilityHint("Removes all overrides configured for \(appModel.controlDisplayName(modifierControl)).")
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(appModel.mappingLayerDetail)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    if let contextHint = appModel.mappingLayerContextHint {
                        Text(contextHint)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .multilineTextAlignment(.trailing)
            }
            .controlSize(.regular)
            .frame(minHeight: 40)
            .animation(
                .easeOut(duration: 0.16),
                value: appModel.liveModifierPreviewControl
            )

            ControllerCanvas(canvasColors: canvasColors, borderColor: borderColor)
                .frame(minHeight: 450, idealHeight: 530, maxHeight: 590)
                .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .productPanel()
        .accessibilityIdentifier("workspace.controller-map")
        .confirmationDialog(
            "Remove modifier layer?",
            isPresented: $isConfirmingLayerRemoval
        ) {
            if let modifierControl = appModel.selectedModifierControl {
                Button("Remove \(appModel.controlDisplayName(modifierControl)) Layer", role: .destructive) {
                    appModel.removeModifierLayer(modifierControl)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let modifierControl = appModel.selectedModifierControl {
                Text("This removes every shortcut override used while \(appModel.controlDisplayName(modifierControl)) is held.")
            }
        }
        .confirmationDialog(
            pendingApplicationAction?.title ?? "Change app shortcuts?",
            isPresented: Binding(
                get: { pendingApplicationAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingApplicationAction = nil
                    }
                }
            )
        ) {
            if let pendingApplicationAction {
                Button(pendingApplicationAction.confirmationTitle, role: .destructive) {
                    perform(pendingApplicationAction)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingApplicationAction = nil
            }
        } message: {
            if let pendingApplicationAction,
               let application = appModel.selectedApplicationMapping {
                Text(pendingApplicationAction.message(for: application.displayName))
            }
        }
    }

    private var applicationScopeToolbar: some View {
        HStack(spacing: 10) {
            Label("App", systemImage: "app.badge")
                .font(.subheadline.weight(.semibold))

            Menu {
                ForEach(appModel.mappingScopes) { scope in
                    Button {
                        appModel.selectMappingScope(scope)
                    } label: {
                        HStack(spacing: 7) {
                            applicationScopeIcon(scope, size: 16)
                            Text(appModel.mappingScopeDisplayName(scope))
                            if scope == appModel.selectedMappingScope {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    applicationScopeIcon(appModel.selectedMappingScope, size: 18)
                    Text(appModel.mappingScopeDisplayName(appModel.selectedMappingScope))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .frame(width: 190)
            .frame(minHeight: 40)
            .accessibilityLabel("App-specific shortcuts")
            .accessibilityValue(
                appModel.mappingScopeDisplayName(appModel.selectedMappingScope)
            )

            Menu {
                if appModel.canAddCodexStarterMappings {
                    Button {
                        appModel.addCodexStarterMappings()
                    } label: {
                        Label("Codex Starter", systemImage: "terminal")
                    }
                }

                let runningApplications = appModel.availableRunningApplications.filter {
                    $0.bundleIdentifier != ApplicationMappingOverrides.codexBundleIdentifier
                }
                if !runningApplications.isEmpty {
                    if appModel.canAddCodexStarterMappings {
                        Divider()
                    }
                    ForEach(runningApplications) { application in
                        Button(application.displayName) {
                            appModel.addApplicationMappings(application)
                        }
                    }
                }

                Divider()
                Button("Choose Application…") {
                    appModel.chooseApplicationForMappings()
                }
            } label: {
                Label("Add App", systemImage: "plus")
            }
            .frame(minHeight: 40)

            if let application = appModel.selectedApplicationMapping {
                Menu {
                    if application.bundleIdentifier == ApplicationMappingOverrides.codexBundleIdentifier {
                        Button("Restore Codex Starter…") {
                            pendingApplicationAction = .restoreStarter
                        }
                    }
                    Button("Reset to All Apps…") {
                        pendingApplicationAction = .clearOverrides
                    }
                    .disabled(application.overrideCount == 0)
                    Divider()
                    Button("Remove \(application.displayName)…", role: .destructive) {
                        pendingApplicationAction = .removeApplication
                    }
                } label: {
                    Label("App Settings", systemImage: "ellipsis.circle")
                }
                .frame(minHeight: 40)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(appModel.selectedMappingScopeDetail)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                if let application = appModel.selectedApplicationMapping {
                    Label(
                        appModel.isSelectedApplicationCurrentlyActive
                            ? "Active now"
                            : "Applies automatically when \(application.displayName) is frontmost",
                        systemImage: appModel.isSelectedApplicationCurrentlyActive
                            ? "bolt.fill"
                            : "arrow.triangle.2.circlepath"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        appModel.isSelectedApplicationCurrentlyActive
                            ? Color.green
                            : Color.secondary
                    )
                }
            }
            .multilineTextAlignment(.trailing)
        }
        .controlSize(.regular)
        .frame(minHeight: 40)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("controller-map.application-scope")
    }

    @ViewBuilder
    private func applicationScopeIcon(
        _ scope: ControllerMappingScope,
        size: CGFloat
    ) -> some View {
        if scope.applicationBundleIdentifier == nil {
            Image(systemName: "square.grid.2x2.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else if let icon = appModel.applicationIcon(for: scope) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .stroke(
                            colorScheme == .dark
                                ? Color.white.opacity(0.10)
                                : Color.black.opacity(0.10),
                            lineWidth: 1
                        )
                }
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    private func perform(_ action: PendingApplicationMappingAction) {
        switch action {
        case .restoreStarter:
            appModel.restoreSelectedApplicationMappings()
        case .clearOverrides:
            appModel.clearSelectedApplicationMappings()
        case .removeApplication:
            appModel.removeSelectedApplicationMappings()
        }
        pendingApplicationAction = nil
    }

    private var canvasColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.11, green: 0.13, blue: 0.17),
                Color(red: 0.065, green: 0.075, blue: 0.10),
            ]
        }
        return [
            Color(red: 0.94, green: 0.95, blue: 0.97),
            Color(red: 0.84, green: 0.87, blue: 0.92),
        ]
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
}

private enum PendingApplicationMappingAction {
    case restoreStarter
    case clearOverrides
    case removeApplication

    var title: String {
        switch self {
        case .restoreStarter:
            return "Restore the Codex starter mappings?"
        case .clearOverrides:
            return "Reset this app to All Apps?"
        case .removeApplication:
            return "Remove app-specific shortcuts?"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .restoreStarter:
            return "Restore Starter"
        case .clearOverrides:
            return "Reset to All Apps"
        case .removeApplication:
            return "Remove App"
        }
    }

    func message(for applicationName: String) -> String {
        switch self {
        case .restoreStarter:
            return "This replaces the current \(applicationName) overrides with Vibe Controller's Codex Micro-inspired starter controls."
        case .clearOverrides:
            return "This clears every \(applicationName) override. All controls will inherit their All Apps mappings."
        case .removeApplication:
            return "This removes \(applicationName) from the App picker. Your All Apps mappings are not changed."
        }
    }
}

private struct ControllerCanvas: View {
    @EnvironmentObject private var appModel: AppModel

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
                    .padding(16)
            }
            .frame(width: fittedSize.width + 32, height: fittedSize.height + 32)
            .position(x: size.width / 2, y: size.height / 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var controllerLayout: some View {
        if appModel.controllerSnapshot.controllerFamily == .playStation {
            playStationLayout
        } else {
            xboxLayout
        }
    }

    private var xboxLayout: some View {
        ZStack(alignment: .topLeading) {
            PositionedNode(x: 500, y: 572) {
                Ellipse()
                    .fill(Color.black.opacity(0.48))
                    .frame(width: 740, height: 72)
                    .blur(radius: 22)
            }

            PositionedNode(x: 500, y: 164) {
                ControllerBackRidgeShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.29, green: 0.31, blue: 0.35),
                                Color(red: 0.12, green: 0.13, blue: 0.15),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        ControllerBackRidgeShape()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    }
                    .frame(width: 640, height: 94)
            }

            PositionedNode(x: 500, y: 394) {
                XboxControllerShell()
                    .frame(width: 860, height: 458)
            }

            PositionedNode(x: 296, y: 61) {
                HardwareControlButton(control: .leftTrigger, style: .trigger, showsLevel: true)
            }
            PositionedNode(x: 704, y: 61) {
                HardwareControlButton(control: .rightTrigger, style: .trigger, showsLevel: true)
            }
            PositionedNode(x: 296, y: 132) {
                HardwareControlButton(control: .leftShoulder, style: .shoulder)
            }
            PositionedNode(x: 704, y: 132) {
                HardwareControlButton(control: .rightShoulder, style: .shoulder)
            }

            PositionedNode(x: 292, y: 271) {
                StickNode(side: .left)
            }
            PositionedNode(x: 384, y: 265) {
                CompactMappedControl(control: .leftThumbstickButton, label: "L3")
            }

            PositionedNode(x: 500, y: 222) {
                CompactMappedControl(control: .home, symbol: "xbox.logo", size: 48)
            }
            PositionedNode(x: 448, y: 305) {
                CompactMappedControl(control: .options, symbol: "rectangle.on.rectangle", size: 44)
            }
            PositionedNode(x: 552, y: 305) {
                CompactMappedControl(control: .menu, symbol: "line.3.horizontal", size: 44)
            }

            PositionedNode(x: 397, y: 454) {
                DPadCluster()
            }
            PositionedNode(x: 604, y: 460) {
                StickNode(side: .right)
            }
            PositionedNode(x: 690, y: 462) {
                CompactMappedControl(control: .rightThumbstickButton, label: "R3")
            }

            PositionedNode(x: 716, y: 280) {
                FaceButtonsCluster()
            }
        }
    }

    private var playStationLayout: some View {
        ZStack(alignment: .topLeading) {
            PositionedNode(x: 500, y: 572) {
                Ellipse()
                    .fill(Color.black.opacity(0.48))
                    .frame(width: 740, height: 72)
                    .blur(radius: 22)
            }

            PositionedNode(x: 500, y: 164) {
                ControllerBackRidgeShape()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.92), Color(red: 0.48, green: 0.52, blue: 0.60)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        ControllerBackRidgeShape()
                            .stroke(Color.white.opacity(0.40), lineWidth: 1)
                    }
                    .frame(width: 640, height: 94)
            }

            PositionedNode(x: 500, y: 394) {
                PlayStationControllerShell()
                    .frame(width: 860, height: 458)
            }

            PositionedNode(x: 296, y: 61) {
                HardwareControlButton(control: .leftTrigger, style: .trigger, showsLevel: true)
            }
            PositionedNode(x: 704, y: 61) {
                HardwareControlButton(control: .rightTrigger, style: .trigger, showsLevel: true)
            }
            PositionedNode(x: 296, y: 132) {
                HardwareControlButton(control: .leftShoulder, style: .shoulder)
            }
            PositionedNode(x: 704, y: 132) {
                HardwareControlButton(control: .rightShoulder, style: .shoulder)
            }

            PositionedNode(x: 500, y: 250) {
                TouchpadMappedControl()
            }
            PositionedNode(x: 384, y: 326) {
                CompactMappedControl(control: .options, label: "Create", size: 42, showsCaption: false)
            }
            PositionedNode(x: 616, y: 326) {
                CompactMappedControl(control: .menu, label: "Options", size: 42, showsCaption: false)
            }
            PositionedNode(x: 500, y: 353) {
                CompactMappedControl(control: .home, label: "PS", size: 44, showsCaption: false)
            }

            PositionedNode(x: 298, y: 306) {
                DPadCluster(showsCaptions: false)
            }
            PositionedNode(x: 702, y: 306) {
                FaceButtonsCluster(showsCaptions: false)
            }

            PositionedNode(x: 390, y: 470) {
                StickNode(side: .left)
            }
            PositionedNode(x: 308, y: 470) {
                CompactMappedControl(control: .leftThumbstickButton, label: "L3", showsCaption: false)
            }
            PositionedNode(x: 610, y: 470) {
                StickNode(side: .right)
            }
            PositionedNode(x: 692, y: 470) {
                CompactMappedControl(control: .rightThumbstickButton, label: "R3", showsCaption: false)
            }
        }
    }
}

private struct PositionedNode<Content: View>: View {
    let x: CGFloat
    let y: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content.position(x: x, y: y)
    }
}

private struct XboxControllerShell: View {
    var body: some View {
        ZStack {
            ControllerBodyShape()
                .fill(Color.black.opacity(0.72))
                .offset(y: 15)
                .shadow(color: .black.opacity(0.42), radius: 18, y: 16)

            ControllerBodyShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.27, green: 0.29, blue: 0.33),
                            Color(red: 0.16, green: 0.17, blue: 0.20),
                            Color(red: 0.105, green: 0.11, blue: 0.13),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    ControllerBodyShape()
                        .stroke(Color.white.opacity(0.13), lineWidth: 1.2)
                }

            ControllerTopPlateShape()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.075), Color.white.opacity(0.012)],
                        center: .top,
                        startRadius: 10,
                        endRadius: 350
                    )
                )
                .overlay {
                    ControllerTopPlateShape()
                        .stroke(Color.white.opacity(0.055), lineWidth: 1)
                }
                .padding(.horizontal, 112)
                .padding(.top, 24)
                .padding(.bottom, 42)

            HStack {
                GripTexture()
                Spacer()
                GripTexture()
                    .scaleEffect(x: -1, y: 1)
            }
            .padding(.horizontal, 72)
            .padding(.top, 220)
            .padding(.bottom, 28)
            .mask(ControllerBodyShape())
        }
    }
}

private struct PlayStationControllerShell: View {
    var body: some View {
        ZStack {
            ControllerBodyShape()
                .fill(Color.black.opacity(0.68))
                .offset(y: 15)
                .shadow(color: .black.opacity(0.44), radius: 18, y: 16)

            ControllerBodyShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.90, green: 0.92, blue: 0.96),
                            Color(red: 0.64, green: 0.68, blue: 0.76),
                            Color(red: 0.34, green: 0.38, blue: 0.46),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    ControllerBodyShape()
                        .stroke(Color.white.opacity(0.34), lineWidth: 1.2)
                }

            ControllerTopPlateShape()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.20, green: 0.22, blue: 0.27), Color(red: 0.07, green: 0.08, blue: 0.10)],
                        center: .top,
                        startRadius: 10,
                        endRadius: 350
                    )
                )
                .overlay {
                    ControllerTopPlateShape()
                        .stroke(Color(red: 0.28, green: 0.62, blue: 1.0).opacity(0.34), lineWidth: 1.2)
                }
                .padding(.horizontal, 112)
                .padding(.top, 24)
                .padding(.bottom, 42)

            HStack {
                GripTexture()
                Spacer()
                GripTexture().scaleEffect(x: -1, y: 1)
            }
            .padding(.horizontal, 72)
            .padding(.top, 220)
            .padding(.bottom, 28)
            .mask(ControllerBodyShape())
        }
    }
}

private struct GripTexture: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<10, id: \.self) { row in
                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule()
                            .fill(Color.white.opacity(0.045))
                            .frame(width: 18, height: 2)
                    }
                }
                .offset(x: CGFloat(row) * 2)
            }
        }
        .rotationEffect(.degrees(-13))
    }
}

private struct ControllerBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()

        path.move(to: CGPoint(x: w * 0.21, y: h * 0.06))
        path.addCurve(
            to: CGPoint(x: w * 0.075, y: h * 0.27),
            control1: CGPoint(x: w * 0.135, y: h * 0.065),
            control2: CGPoint(x: w * 0.095, y: h * 0.14)
        )
        path.addLine(to: CGPoint(x: w * 0.008, y: h * 0.69))
        path.addCurve(
            to: CGPoint(x: w * 0.145, y: h * 0.965),
            control1: CGPoint(x: -w * 0.012, y: h * 0.86),
            control2: CGPoint(x: w * 0.045, y: h * 1.04)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.30, y: h * 0.70),
            control1: CGPoint(x: w * 0.205, y: h * 0.88),
            control2: CGPoint(x: w * 0.245, y: h * 0.74)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.43, y: h * 0.70),
            control1: CGPoint(x: w * 0.345, y: h * 0.64),
            control2: CGPoint(x: w * 0.385, y: h * 0.655)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.57, y: h * 0.70),
            control1: CGPoint(x: w * 0.475, y: h * 0.73),
            control2: CGPoint(x: w * 0.525, y: h * 0.73)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.70, y: h * 0.70),
            control1: CGPoint(x: w * 0.615, y: h * 0.655),
            control2: CGPoint(x: w * 0.655, y: h * 0.64)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.855, y: h * 0.965),
            control1: CGPoint(x: w * 0.755, y: h * 0.74),
            control2: CGPoint(x: w * 0.795, y: h * 0.88)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.992, y: h * 0.69),
            control1: CGPoint(x: w * 0.955, y: h * 1.04),
            control2: CGPoint(x: w * 1.012, y: h * 0.86)
        )
        path.addLine(to: CGPoint(x: w * 0.925, y: h * 0.27))
        path.addCurve(
            to: CGPoint(x: w * 0.79, y: h * 0.06),
            control1: CGPoint(x: w * 0.905, y: h * 0.14),
            control2: CGPoint(x: w * 0.865, y: h * 0.065)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.57, y: h * 0.105),
            control1: CGPoint(x: w * 0.70, y: h * 0.025),
            control2: CGPoint(x: w * 0.64, y: h * 0.09)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.43, y: h * 0.105),
            control1: CGPoint(x: w * 0.525, y: h * 0.125),
            control2: CGPoint(x: w * 0.475, y: h * 0.125)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.21, y: h * 0.06),
            control1: CGPoint(x: w * 0.36, y: h * 0.09),
            control2: CGPoint(x: w * 0.30, y: h * 0.025)
        )
        path.closeSubpath()
        return path
    }
}

private struct ControllerTopPlateShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.18, y: h * 0.02))
        path.addCurve(
            to: CGPoint(x: w * 0.08, y: h * 0.58),
            control1: CGPoint(x: w * 0.08, y: h * 0.16),
            control2: CGPoint(x: w * 0.04, y: h * 0.38)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.33, y: h * 0.86),
            control1: CGPoint(x: w * 0.12, y: h * 0.76),
            control2: CGPoint(x: w * 0.23, y: h * 0.82)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.67, y: h * 0.86),
            control1: CGPoint(x: w * 0.43, y: h * 0.91),
            control2: CGPoint(x: w * 0.57, y: h * 0.91)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.92, y: h * 0.58),
            control1: CGPoint(x: w * 0.77, y: h * 0.82),
            control2: CGPoint(x: w * 0.88, y: h * 0.76)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.82, y: h * 0.02),
            control1: CGPoint(x: w * 0.96, y: h * 0.38),
            control2: CGPoint(x: w * 0.92, y: h * 0.16)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.18, y: h * 0.02),
            control1: CGPoint(x: w * 0.65, y: -h * 0.03),
            control2: CGPoint(x: w * 0.35, y: -h * 0.03)
        )
        path.closeSubpath()
        return path
    }
}

private struct ControllerBackRidgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.10, y: 0))
        path.addLine(to: CGPoint(x: rect.width * 0.90, y: 0))
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height),
            control1: CGPoint(x: rect.width * 0.96, y: 0),
            control2: CGPoint(x: rect.width, y: rect.height * 0.40)
        )
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.10, y: 0),
            control1: CGPoint(x: 0, y: rect.height * 0.40),
            control2: CGPoint(x: rect.width * 0.04, y: 0)
        )
        path.closeSubpath()
        return path
    }
}

private struct TriggerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.18, y: 0))
        path.addLine(to: CGPoint(x: rect.width * 0.82, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.72),
            control: CGPoint(x: rect.width * 0.94, y: rect.height * 0.10)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.86, y: rect.height),
            control: CGPoint(x: rect.width, y: rect.height)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.14, y: rect.height))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.height * 0.72),
            control: CGPoint(x: 0, y: rect.height)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.18, y: 0),
            control: CGPoint(x: rect.width * 0.06, y: rect.height * 0.10)
        )
        path.closeSubpath()
        return path
    }
}

private enum HardwareControlStyle {
    case face(Color)
    case utility
    case shoulder
    case trigger
}

private struct HardwareControlButton: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let control: ControllerControlID
    let style: HardwareControlStyle
    var label: String?
    var symbol: String?
    var showsLevel = false
    var sizeOverride: CGFloat?

    @State private var isHovered = false

    private var isActive: Bool {
        appModel.controllerSnapshot.pressedControls.contains(control)
    }

    private var level: Double {
        appModel.controllerSnapshot.value(for: control)
    }

    var body: some View {
        Button {
            appModel.presentMapping(for: control)
        } label: {
            ZStack {
                controlSurface
                if showsLevel {
                    VStack {
                        Spacer()
                        Capsule()
                            .fill(Color.accentColor.opacity(0.82))
                            .frame(width: max(4, (width - 22) * level), height: 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 11)
                            .padding(.bottom, 7)
                    }
                }
                controlLabel
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle())
        .offset(y: isHovered ? -2 : 0)
        .shadow(
            color: isActive ? Color.accentColor.opacity(0.50) : Color.black.opacity(isHovered ? 0.34 : 0.22),
            radius: isActive ? 12 : (isHovered ? 8 : 4),
            y: isHovered ? 5 : 3
        )
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isActive)
        .scaleEffect(isActive ? 0.96 : 1)
    }

    @ViewBuilder
    private var controlSurface: some View {
        switch style {
        case .face(let tint):
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(isActive ? 0.20 : 0.11), Color.black.opacity(0.28)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    Circle()
                        .stroke(isActive ? Color.accentColor : tint.opacity(0.62), lineWidth: isActive ? 2.5 : 1.5)
                }
        case .utility:
            Circle()
                .fill(isActive ? Color.accentColor.opacity(0.55) : Color.black.opacity(0.31))
                .overlay {
                    Circle().stroke(Color.white.opacity(isActive ? 0.30 : 0.12), lineWidth: 1)
                }
        case .shoulder:
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isActive
                            ? [Color.accentColor.opacity(0.72), Color.accentColor.opacity(0.42)]
                            : [Color(red: 0.31, green: 0.33, blue: 0.37), Color(red: 0.14, green: 0.15, blue: 0.17)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
        case .trigger:
            TriggerShape()
                .fill(
                    LinearGradient(
                        colors: isActive
                            ? [Color.accentColor.opacity(0.70), Color.accentColor.opacity(0.38)]
                            : [Color(red: 0.34, green: 0.36, blue: 0.40), Color(red: 0.13, green: 0.14, blue: 0.16)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    TriggerShape().stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private var controlLabel: some View {
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: styleIsUtility ? 16 : 18, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
        } else if styleShowsInlineMapping {
            VStack(spacing: 2) {
                Text(label ?? control.diagramLabel(for: appModel.controllerSnapshot.controllerFamily))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(appModel.mappingSummary(for: control))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, showsLevel ? 6 : 0)
        } else {
            Text(label ?? control.diagramLabel(for: appModel.controllerSnapshot.controllerFamily))
                .font(.system(size: styleIsFace ? 17 : 12, weight: .bold, design: .rounded))
                .foregroundStyle(faceTint ?? Color.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.64)
                .padding(.horizontal, 3)
        }
    }

    private var width: CGFloat {
        if let sizeOverride { return sizeOverride }
        switch style {
        case .face:
            return 52
        case .utility:
            return 46
        case .shoulder:
            return 184
        case .trigger:
            return 166
        }
    }

    private var height: CGFloat {
        if let sizeOverride { return sizeOverride }
        switch style {
        case .face:
            return 52
        case .utility:
            return 46
        case .shoulder:
            return 54
        case .trigger:
            return 60
        }
    }

    private var styleShowsInlineMapping: Bool {
        switch style {
        case .shoulder, .trigger:
            return true
        case .face, .utility:
            return false
        }
    }

    private var styleIsFace: Bool {
        if case .face = style { return true }
        return false
    }

    private var styleIsUtility: Bool {
        if case .utility = style { return true }
        return false
    }

    private var faceTint: Color? {
        if case .face(let tint) = style { return tint }
        return nil
    }
}

private struct CompactMappedControl: View {
    @EnvironmentObject private var appModel: AppModel

    let control: ControllerControlID
    var label: String?
    var symbol: String?
    var size: CGFloat = 46
    var showsCaption = true

    var body: some View {
        VStack(spacing: 5) {
            HardwareControlButton(
                control: control,
                style: .utility,
                label: label,
                symbol: symbol,
                sizeOverride: size
            )
            if showsCaption {
                MappingCaption(text: appModel.mappingSummary(for: control), maxWidth: 104)
            }
        }
    }
}

private struct TouchpadMappedControl: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 5) {
            Button {
                appModel.presentMapping(for: .touchpadButton)
            } label: {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.25, green: 0.27, blue: 0.32), Color(red: 0.10, green: 0.11, blue: 0.14)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(
                                appModel.controllerSnapshot.pressedControls.contains(.touchpadButton)
                                    ? Color.accentColor
                                    : Color.white.opacity(0.16),
                                lineWidth: 1.5
                            )
                    }
                    .overlay {
                        VStack(spacing: 2) {
                            Text("Touchpad")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Text(appModel.mappingSummary(for: .touchpadButton))
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.62))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                    }
                    .frame(width: 202, height: 78)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TactileButtonStyle())
        }
    }
}

private struct FaceButtonsCluster: View {
    @EnvironmentObject private var appModel: AppModel

    var showsCaptions = true

    var body: some View {
        ZStack {
            HardwareControlButton(control: .buttonNorth, style: .face(tint(for: .buttonNorth)))
                .offset(y: -61)
            HardwareControlButton(control: .buttonWest, style: .face(tint(for: .buttonWest)))
                .offset(x: -61)
            HardwareControlButton(control: .buttonEast, style: .face(tint(for: .buttonEast)))
                .offset(x: 61)
            HardwareControlButton(control: .buttonSouth, style: .face(tint(for: .buttonSouth)))
                .offset(y: 61)

            if showsCaptions {
                MappingCaption(text: appModel.mappingSummary(for: .buttonNorth), maxWidth: 106)
                    .offset(y: -105)
                MappingCaption(text: appModel.mappingSummary(for: .buttonWest), maxWidth: 106)
                    .offset(x: -123)
                MappingCaption(text: appModel.mappingSummary(for: .buttonEast), maxWidth: 106)
                    .offset(x: 123)
                MappingCaption(text: appModel.mappingSummary(for: .buttonSouth), maxWidth: 106)
                    .offset(y: 105)
            }
        }
        .frame(width: 310, height: 250)
    }

    private func tint(for control: ControllerControlID) -> Color {
        if appModel.controllerSnapshot.controllerFamily == .playStation {
            switch control {
            case .buttonNorth:
                return Color(red: 0.35, green: 0.82, blue: 0.58)
            case .buttonWest:
                return Color(red: 0.95, green: 0.48, blue: 0.70)
            case .buttonEast:
                return Color(red: 0.96, green: 0.36, blue: 0.40)
            default:
                return Color(red: 0.38, green: 0.64, blue: 1.0)
            }
        }
        switch control {
        case .buttonNorth:
            return Color(red: 0.96, green: 0.75, blue: 0.20)
        case .buttonWest:
            return Color(red: 0.24, green: 0.62, blue: 0.98)
        case .buttonEast:
            return Color(red: 0.96, green: 0.33, blue: 0.30)
        default:
            return Color(red: 0.40, green: 0.82, blue: 0.40)
        }
    }
}

private struct DPadCluster: View {
    @EnvironmentObject private var appModel: AppModel

    var showsCaptions = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.black.opacity(0.36))
                .frame(width: 150, height: 50)
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.black.opacity(0.36))
                .frame(width: 50, height: 150)
            Circle()
                .fill(Color.black.opacity(0.22))
                .frame(width: 42, height: 42)

            DPadDirectionButton(control: .dpadUp, symbol: "chevron.up")
                .offset(y: -50)
            DPadDirectionButton(control: .dpadDown, symbol: "chevron.down")
                .offset(y: 50)
            DPadDirectionButton(control: .dpadLeft, symbol: "chevron.left")
                .offset(x: -50)
            DPadDirectionButton(control: .dpadRight, symbol: "chevron.right")
                .offset(x: 50)

            if showsCaptions {
                MappingCaption(text: appModel.mappingSummary(for: .dpadUp), maxWidth: 112)
                    .offset(y: -91)
                MappingCaption(text: appModel.mappingSummary(for: .dpadDown), maxWidth: 112)
                    .offset(y: 91)
                MappingCaption(text: appModel.mappingSummary(for: .dpadLeft), maxWidth: 106)
                    .offset(x: -111)
                MappingCaption(text: appModel.mappingSummary(for: .dpadRight), maxWidth: 106)
                    .offset(x: 111)
            }
        }
        .frame(width: 340, height: 250)
    }
}

private struct DPadDirectionButton: View {
    @EnvironmentObject private var appModel: AppModel

    let control: ControllerControlID
    let symbol: String

    var body: some View {
        Button {
            appModel.presentMapping(for: control)
        } label: {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    appModel.controllerSnapshot.pressedControls.contains(control)
                        ? Color.accentColor.opacity(0.72)
                        : Color.white.opacity(0.07)
                )
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.82))
                }
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle())
    }
}

private struct StickNode: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let side: StickSide
    @State private var isHovered = false

    var body: some View {
        let snapshot = side == .left ? appModel.controllerSnapshot.leftStick : appModel.controllerSnapshot.rightStick
        let mappingControl: ControllerControlID = side == .left ? .leftThumbstick : .rightThumbstick

        Button {
            appModel.presentStickSheet(for: side)
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 106, height: 106)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.13), lineWidth: 2)
                        .frame(width: 106, height: 106)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.28, green: 0.30, blue: 0.34), Color(red: 0.11, green: 0.12, blue: 0.14)],
                                center: .topLeading,
                                startRadius: 3,
                                endRadius: 54
                            )
                        )
                        .frame(width: 76, height: 76)
                        .overlay {
                            Circle().stroke(Color.white.opacity(0.10), lineWidth: 1)
                        }
                        .offset(x: snapshot.x * 24, y: -snapshot.y * 24)
                        .shadow(color: .black.opacity(0.44), radius: 6, y: 5)
                    Circle()
                        .fill(Color.accentColor.opacity(0.72))
                        .frame(width: 12, height: 12)
                        .offset(x: snapshot.x * 24, y: -snapshot.y * 24)
                    Text(side == .left ? "LS" : "RS")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .offset(x: snapshot.x * 24, y: -snapshot.y * 24)
                }
                MappingCaption(text: appModel.mappingSummary(for: mappingControl), maxWidth: 126)
            }
        }
        .buttonStyle(TactileButtonStyle())
        .offset(y: isHovered ? -2 : 0)
        .shadow(color: .black.opacity(isHovered ? 0.34 : 0), radius: 8, y: 5)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
    }
}

private struct MappingCaption: View {
    let text: String
    let maxWidth: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(text == "No action" ? Color.white.opacity(0.42) : Color.white.opacity(0.74))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(maxWidth: maxWidth)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.24))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.055), lineWidth: 1)
            }
            .allowsHitTesting(false)
    }
}

private struct TactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}
