import SwiftUI

struct ControllerDiagramView: View {
    var canvasHeight: CGFloat = 440
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isConfirmingLayerRemoval = false
    @State private var pendingApplicationAction: PendingApplicationMappingAction?
    @State private var previewFamily: ControllerFamily?
    @State private var showsList = false
    @State private var search = ""
    @State private var hoveredControl: ControllerControlID?
    @AppStorage("controllerMap.showLabels") private var showsLabels = true

    private var family: ControllerFamily {
        previewFamily ?? (appModel.controllerSnapshot.controllerFamily == .playStation ? .playStation : .xbox)
    }

    private var overrideControls: [ControllerControlID] {
        ControllerArtwork.controls(for: family).map(\.control).filter { control in
            appModel.hasMappingOverride(for: control, in: appModel.visibleMappingLayer)
                || (appModel.visibleMappingLayer != .base
                    && appModel.hasMappingOverride(
                        for: control, in: appModel.visibleMappingLayer, scope: .allApplications))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Controller map")
                        .font(.system(size: 23, weight: .semibold)).tracking(-0.5)
                    Text("Select a control to customize its action.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Map view", selection: $showsList) {
                    Label("Controller", systemImage: "gamecontroller").tag(false)
                    Label("Bindings", systemImage: "list.bullet").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 205)
                .accessibilityIdentifier("controller-map.view")
            }
            .padding(.bottom, 22)
            applicationScopeToolbar
            layerToolbar.padding(.top, 8).padding(.bottom, 14)
            Group {
                if showsList {
                    bindingList
                } else {
                    artworkWorkspace
                    if !showsLabels { actionReadout.padding(.top, 10) }
                }
            }
            .transition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showsList)
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text(
                    appModel.selectedApplicationMapping == nil
                        ? "Hold a modifier to preview its shortcuts. Click any control to remap."
                        : "Controls without an app override use your All Apps settings.")
            }
            .font(.caption).foregroundStyle(.secondary).padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("workspace.controller-map")
        .confirmationDialog("Remove modifier layer?", isPresented: $isConfirmingLayerRemoval) {
            if let modifier = appModel.selectedModifierControl {
                Button("Remove \(appModel.controlDisplayName(modifier)) Layer", role: .destructive) {
                    appModel.removeModifierLayer(modifier)
                }
            }
        } message: {
            Text("This removes all shortcuts configured for this modifier.")
        }
        .confirmationDialog(
            pendingApplicationAction?.title ?? "Change app shortcuts?",
            isPresented: Binding(
                get: { pendingApplicationAction != nil },
                set: { if !$0 { pendingApplicationAction = nil } }
            )
        ) {
            if let action = pendingApplicationAction {
                Button(action.confirmationTitle, role: .destructive) { perform(action) }
            }
            Button("Cancel", role: .cancel) { pendingApplicationAction = nil }
        } message: {
            if let action = pendingApplicationAction,
                let application = appModel.selectedApplicationMapping
            {
                Text(action.message(for: application.displayName))
            }
        }
    }

    private var artworkWorkspace: some View {
        VStack(spacing: 0) {
            HStack {
                Menu {
                    Button("Automatic") { previewFamily = nil }
                    Divider()
                    Button("Xbox") { previewFamily = .xbox }
                    Button("PlayStation") { previewFamily = .playStation }
                } label: {
                    HStack(spacing: 6) {
                        Text(family == .playStation ? "PLAYSTATION" : "XBOX")
                            .font(.system(size: 10, weight: .bold)).tracking(1.8)
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Controller artwork")
                .help("Choose a layout to preview. Automatic follows your connected controller.")
                Spacer()
                Toggle("Show labels", isOn: $showsLabels)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .fixedSize()
                    .padding(.trailing, 12)
                    .help("Show every button's current action. Labels follow the selected app and held modifier.")
                    .accessibilityIdentifier("controller-map.show-labels")
                HStack(spacing: 6) {
                    Circle().fill(appModel.controllerSnapshot.isConnected ? Color.green : .secondary)
                        .frame(width: 5, height: 5)
                    Text(
                        previewFamily != nil
                            ? "Layout preview"
                            : appModel.controllerSnapshot.isConnected ? "Live input" : "Connect to test"
                    )
                    .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22).padding(.top, 20)
            if showsLabels {
                ControllerAnnotatedMap(hardware: hardwareMap, hoveredControl: hoveredControl)
                    .frame(height: max(ControllerCalloutLayout.minimumHeight, canvasHeight - 76))
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            } else {
                hardwareMap
                    .frame(width: (canvasHeight - 76) / 0.66, height: canvasHeight - 76)
                    .scaleEffect(1.12)
                    .frame(maxWidth: .infinity)
                    .padding(.top, -10)
            }
            HStack(spacing: 12) {
                stickRoleButton(.left)
                Spacer()
                stickRoleButton(.right)
            }
            .padding(.horizontal, 24).padding(.bottom, 18)
        }
        .background(ProductSurfaceStyle.canvas(for: colorScheme), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(ProductSurfaceStyle.border(for: colorScheme), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var hardwareMap: ControllerHardwareMap {
        ControllerHardwareMap(
            family: family,
            pressedControls: appModel.controllerSnapshot.pressedControls,
            analogValues: appModel.controllerSnapshot.analogValues,
            overriddenControls: Set(overrideControls),
            focusedControl: hoveredControl,
            modifierControl: appModel.liveModifierPreviewControl,
            leftStick: appModel.controllerSnapshot.leftStick,
            rightStick: appModel.controllerSnapshot.rightStick,
            actionDescription: { appModel.mappingSummary(for: $0) },
            onSelect: { appModel.presentMapping(for: $0) },
            onHover: { hoveredControl = $0 }
        )
    }

    private func stickRoleButton(_ side: StickSide) -> some View {
        Button {
            appModel.presentStickSheet(for: side)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "circle.circle").foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(side == .left ? "LEFT STICK" : "RIGHT STICK")
                        .font(.system(size: 9, weight: .semibold)).tracking(0.9).foregroundStyle(.secondary)
                    Text(appModel.roleChoice(for: side).displayName).font(.caption.weight(.medium))
                }
                Image(systemName: "slider.horizontal.3").font(.caption).foregroundStyle(.secondary)
            }
            .frame(minHeight: 40)
        }
        .buttonStyle(.plain)
        .help("Configure \(side.displayName.lowercased()) movement. Click the stick itself to remap its press.")
    }

    private var actionReadout: some View {
        let control =
            hoveredControl
            ?? appModel.controllerSnapshot.pressedControls
            .filter { $0 != appModel.liveModifierPreviewControl }
            .sorted { $0.rawValue < $1.rawValue }.first
        return Group {
            if control == nil, appModel.visibleMappingLayer != .base, !overrideControls.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(overrideControls) { control in
                            Button {
                                appModel.presentMapping(for: control)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(control.displayName(for: family)).font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                    Text(appModel.mapping(for: control).summary).font(.caption)
                                        .foregroundStyle(.secondary).lineLimit(1)
                                }
                                .padding(.horizontal, 12).frame(height: 50)
                                .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(height: 54)
                .accessibilityLabel("Active modifier shortcuts")
            } else {
                focusedReadout(control)
            }
        }
    }

    private func focusedReadout(_ control: ControllerControlID?) -> some View {
        return HStack(spacing: 12) {
            Image(systemName: control?.sfSymbolName ?? "cursorarrow")
                .font(.system(size: 19, weight: .medium)).foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(control?.displayName(for: family) ?? "Explore your controller")
                    .font(.subheadline.weight(.semibold))
                Text(
                    control.map { appModel.mappingSummary(for: $0) } ?? "Point to a button to see its assigned action."
                )
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let control {
                Text(appModel.mapping(for: control).triggerMode.displayName)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("CLICK TO EDIT").font(.system(size: 9, weight: .semibold))
                    .tracking(1).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 4).frame(height: 54)
        .accessibilityIdentifier("controller-map.action-readout")
    }

    private var applicationScopeToolbar: some View {
        HStack(spacing: 10) {
            Text("App").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
            Menu {
                ForEach(appModel.mappingScopes) { scope in
                    Button {
                        appModel.selectMappingScope(scope)
                    } label: {
                        HStack {
                            applicationScopeIcon(scope)
                            Text(appModel.mappingScopeDisplayName(scope))
                            if scope == appModel.selectedMappingScope { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    applicationScopeIcon(appModel.selectedMappingScope)
                    Text(appModel.mappingScopeDisplayName(appModel.selectedMappingScope)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 210)
            .accessibilityLabel("App-specific shortcuts")
            .accessibilityValue(appModel.mappingScopeDisplayName(appModel.selectedMappingScope))
            Menu {
                if appModel.canAddCodexStarterMappings {
                    Button("Codex / ChatGPT Starter") { appModel.addCodexStarterMappings() }
                    Divider()
                }
                ForEach(appModel.availableRunningApplications) { application in
                    Button {
                        appModel.addApplicationMappings(application)
                    } label: {
                        HStack {
                            applicationScopeIcon(.application(application.bundleIdentifier))
                            Text(application.displayName)
                        }
                    }
                }
                Divider()
                Button("Choose Application…") { appModel.chooseApplicationForMappings() }
            } label: {
                Image(systemName: "plus")
            }
            .fixedSize().accessibilityLabel("Add App").help("Add app-specific shortcuts")
            if let application = appModel.selectedApplicationMapping {
                Menu {
                    if application.bundleIdentifier == ApplicationMappingOverrides.codexBundleIdentifier {
                        Button("Restore Codex Starter…") { pendingApplicationAction = .restoreStarter }
                    }
                    Button("Reset to All Apps…") { pendingApplicationAction = .clearOverrides }
                        .disabled(application.overrideCount == 0)
                    Divider()
                    Button("Remove App…", role: .destructive) { pendingApplicationAction = .removeApplication }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .fixedSize().accessibilityLabel("App Settings")
            }
            Spacer(minLength: 0)
            Text(appModel.selectedMappingScopeDetail)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .controlSize(.large).frame(minHeight: 38)
        .accessibilityIdentifier("controller-map.application-scope")
    }

    private var layerToolbar: some View {
        HStack(spacing: 10) {
            Text("Layer").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
            ScrollView(.horizontal) {
                HStack(spacing: 3) {
                    ForEach(appModel.mappingLayers) { layer in
                        Button {
                            appModel.selectMappingLayer(layer)
                        } label: {
                            Text(appModel.mappingLayerDisplayName(layer))
                                .font(
                                    .system(
                                        size: 12, weight: appModel.visibleMappingLayer == layer ? .semibold : .medium)
                                )
                                .padding(.horizontal, 13).frame(height: 32)
                                .foregroundStyle(appModel.visibleMappingLayer == layer ? Color.accentColor : .secondary)
                                .background(
                                    appModel.visibleMappingLayer == layer ? Color.accentColor.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                        }
                        .buttonStyle(.plain).disabled(appModel.liveModifierPreviewControl != nil)
                        .accessibilityAddTraits(appModel.visibleMappingLayer == layer ? .isSelected : [])
                    }
                }
                .padding(3)
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 340, alignment: .leading)
            .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: appModel.visibleMappingLayer)
            Menu {
                ForEach(appModel.availableModifierControls) { control in
                    Button(appModel.controlDisplayName(control)) { appModel.addModifierLayer(control) }
                }
                if appModel.selectedModifierControl != nil {
                    Divider()
                    Button("Remove Layer…", role: .destructive) { isConfirmingLayerRemoval = true }
                }
            } label: {
                Image(systemName: "plus")
            }
            .fixedSize().disabled(appModel.liveModifierPreviewControl != nil)
            .accessibilityLabel("Manage modifier layers")
            Spacer(minLength: 0)
            if let control = appModel.liveModifierPreviewControl {
                Label("\(appModel.controlDisplayName(control)) held", systemImage: "bolt.fill")
                    .foregroundStyle(Color.accentColor).font(.caption.weight(.semibold))
            } else {
                Text(appModel.selectedModifierControl == nil ? "Base controls" : "Modifier shortcuts")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(minHeight: 38)
    }

    private var bindingList: some View {
        let controls = ControllerArtwork.controls(for: family).map(\.control).filter {
            search.isEmpty || $0.displayName(for: family).localizedCaseInsensitiveContains(search)
                || appModel.mappingSummary(for: $0).localizedCaseInsensitiveContains(search)
        }
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a button or action", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(14)
            Divider()
            if controls.isEmpty { ContentUnavailableView.search(text: search).frame(height: 220) }
            ForEach(controls) { control in
                Button {
                    appModel.presentMapping(for: control)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: control.sfSymbolName).font(.system(size: 17))
                            .foregroundStyle(Color.accentColor).frame(width: 26)
                        Text(control.displayName(for: family)).font(.subheadline.weight(.medium))
                            .frame(width: 110, alignment: .leading)
                        Text(appModel.mappingSummary(for: control)).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 46).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(control.displayName(for: family)): \(appModel.mappingSummary(for: control))")
                if control != controls.last { Divider().padding(.leading, 54) }
            }
        }
        .background(ProductSurfaceStyle.canvas(for: colorScheme), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private func applicationScopeIcon(_ scope: ControllerMappingScope) -> some View {
        if let icon = appModel.applicationIcon(for: scope) {
            Image(nsImage: icon).resizable().scaledToFit().frame(width: 18, height: 18)
        } else {
            Image(systemName: scope == .allApplications ? "square.grid.2x2" : "app")
                .foregroundStyle(.secondary).frame(width: 18, height: 18)
        }
    }

    private func perform(_ action: PendingApplicationMappingAction) {
        switch action {
        case .restoreStarter: appModel.restoreSelectedApplicationMappings()
        case .clearOverrides: appModel.clearSelectedApplicationMappings()
        case .removeApplication: appModel.removeSelectedApplicationMappings()
        }
        pendingApplicationAction = nil
    }
}

private enum PendingApplicationMappingAction {
    case restoreStarter, clearOverrides, removeApplication
    var title: String {
        switch self {
        case .restoreStarter: return "Restore Codex shortcuts?"
        case .clearOverrides: return "Reset this app to All Apps?"
        case .removeApplication: return "Remove app-specific shortcuts?"
        }
    }
    var confirmationTitle: String {
        switch self {
        case .restoreStarter: return "Restore Starter"
        case .clearOverrides: return "Reset to All Apps"
        case .removeApplication: return "Remove App"
        }
    }
    func message(for name: String) -> String {
        switch self {
        case .restoreStarter: return "This replaces \(name) overrides with the Codex starter."
        case .clearOverrides: return "Every \(name) control will inherit its All Apps mapping."
        case .removeApplication: return "This removes \(name) from the App picker and clears its overrides."
        }
    }
}
