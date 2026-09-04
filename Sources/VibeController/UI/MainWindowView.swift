import AppKit
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportDocument: ExportProfileDocument?
    @State private var diagnosticsExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(2)
            Divider()
            if let presentation = appModel.setupBannerPresentation {
                SetupBannerView(presentation: presentation) { action in
                    appModel.performSetupAction(action)
                }
                .padding(.horizontal, MainWindowLayoutMetrics.horizontalPadding)
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            }
            ScrollView(.vertical) {
                content
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(MainWindowLayoutMetrics.horizontalPadding)
            }
            .scrollIndicators(.automatic)
            .zIndex(0)
            Divider()
            footer
                .zIndex(2)
        }
        .background(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.095, green: 0.105, blue: 0.125), Color(red: 0.055, green: 0.06, blue: 0.075)]
                    : [Color(NSColor.windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .animation(.easeOut(duration: 0.2), value: appModel.setupBannerPresentation?.title)
        .sheet(item: $appModel.presentedSheet) { selection in
            switch selection {
            case .mapping(let control, let layer, let scope):
                MappingSheetView(control: control, layer: layer, scope: scope)
                    .environmentObject(appModel)
            case .stick(let side):
                StickRoleSheetView(stickSide: side)
                    .environmentObject(appModel)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.vibeControllerProfile, .json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    appModel.importProfile(from: url)
                }
            case .failure(let error):
                appModel.lastErrorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .vibeControllerProfile,
            defaultFilename: appModel.activeProfile.name.replacingOccurrences(of: " ", with: "-")
        ) { result in
            if case .failure(let error) = result {
                appModel.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Vibe Controller")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    Text(appModel.controllerSnapshot.controllerName ?? "Connect an Xbox or PlayStation controller")
                        .lineLimit(1)
                    if let connection = appModel.controllerSnapshot.connectionSummary {
                        Text("·")
                        Text(connection)
                    }
                    if let battery = appModel.batterySummary {
                        Text("·")
                        Label(battery, systemImage: "battery.75")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            StatusBadgeView(state: appModel.statusBadgeState)

            Toggle(isOn: Binding(
                get: { appModel.isRuntimeEnabled },
                set: { appModel.setRuntimeEnabled($0) }
            )) {
                Text("Enabled")
                    .font(.subheadline.weight(.medium))
            }
            .toggleStyle(.switch)
            .disabled(!appModel.accessibilityTrusted)
            .help("Enable or pause controller input without closing the app.")

            Divider()
                .frame(height: 32)

            Picker("Profile", selection: Binding(
                get: { appModel.activeProfileID },
                set: { appModel.selectProfile($0) }
            )) {
                ForEach(appModel.availableProfiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 210)
        }
        .padding(.horizontal, MainWindowLayoutMetrics.horizontalPadding)
        .padding(.vertical, 13)
        .background(.bar)
        .accessibilityIdentifier("workspace.header")
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 14) {
                CursorSettingsView()
                    .environmentObject(appModel)
                    .frame(width: MainWindowLayoutMetrics.inspectorWidth)

                CompanionSettingsView()
                    .environmentObject(appModel)
                    .frame(width: MainWindowLayoutMetrics.inspectorWidth)
            }

            VStack(spacing: 14) {
                ControllerDiagramView()
                    .environmentObject(appModel)
                    .frame(maxWidth: .infinity, alignment: .top)
                if !appModel.controllerSnapshot.isConnected {
                    NoControllerHelpView()
                }
                diagnosticsAndTesting
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var diagnosticsAndTesting: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    diagnosticsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(Color.accentColor)
                    Text("Diagnostics & Testing")
                        .font(.headline.weight(.semibold))
                    Text(appModel.listeningStatusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(diagnosticsExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("workspace.diagnostics.toggle")

            if diagnosticsExpanded {
                Divider()
                    .padding(.vertical, 14)

                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        LiveControllerCard()
                            .environmentObject(appModel)
                        DiagnosticCard(
                            title: "Cursor",
                            value: appModel.cursorDiagnostics.state.rawValue.capitalized,
                            detail: appModel.cursorDiagnostics.message,
                            symbol: "cursorarrow.motionlines",
                            tint: appModel.cursorDiagnostics.state == .moving ? .blue : .secondary
                        )
                        DiagnosticCard(
                            title: "Last action",
                            value: appModel.lastActionStatus,
                            detail: "Live feedback from shortcuts and cross-screen actions.",
                            symbol: "sparkles",
                            tint: .secondary
                        )
                    }

                    HStack(spacing: 10) {
                        Text("Hardware checks")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cross-Mac Sweep") { appModel.testCursorNudge() }
                            .buttonStyle(.borderedProminent)
                        Button("Left Click") { appModel.testLeftClick() }
                            .buttonStyle(.bordered)
                        Button("Capture Remote Proof") { appModel.captureRemoteProof() }
                            .buttonStyle(.bordered)
                            .disabled(!appModel.virtualHardwareReady)
                    }
                    .controlSize(.regular)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .productPanel(padding: 16)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label(
                appModel.virtualHardwareReady ? "Universal Control ready" : appModel.virtualHardwareSetupTitle,
                systemImage: appModel.virtualHardwareReady ? "checkmark.circle.fill" : "gearshape.2"
            )
            .font(.footnote.weight(.medium))
            .foregroundStyle(appModel.virtualHardwareReady ? Color.green : .secondary)

            Spacer()

            if let error = appModel.lastErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            AppUpdateControlView(
                presentation: appModel.appUpdatePresentation,
                action: appModel.performPrimaryUpdateAction
            )

            Menu {
                Button("Import Profile…") {
                    isImporting = true
                }
                Button("Export Profile…") {
                    prepareProfileExport()
                }
                Divider()
                Button("Reset Profile to Defaults", role: .destructive) {
                    appModel.resetActiveProfileToDefaults()
                }
            } label: {
                Label("Manage Profile", systemImage: "ellipsis.circle")
            }
        }
        .padding(.horizontal, MainWindowLayoutMetrics.horizontalPadding)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func prepareProfileExport() {
        do {
            exportDocument = try ExportProfileDocument(profile: appModel.activeProfile)
            isExporting = true
        } catch {
            appModel.lastErrorMessage = error.localizedDescription
        }
    }
}

struct AppUpdateControlView: View {
    let presentation: AppUpdatePresentation
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if presentation.isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: presentation.symbolName)
                        .foregroundStyle(presentation.isProminent ? Color.accentColor : .secondary)
                }
            }
            .frame(width: 18, height: 18)

            Text(presentation.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if presentation.isProminent {
                Button(presentation.buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .frame(minHeight: 40)
                    .disabled(presentation.isBusy)
            } else {
                Button(presentation.buttonTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .frame(minHeight: 40)
                    .disabled(presentation.isBusy)
            }
        }
        .frame(width: 360, alignment: .trailing)
        .help("Checks the signed Vibe Controller releases on GitHub and installs updates in place.")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("updates.control")
    }
}

private struct LiveControllerCard: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        let snapshot = appModel.controllerSnapshot
        let pressed = snapshot.pressedControls
            .map { appModel.controlDisplayName($0) }
            .sorted()
            .joined(separator: ", ")

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Controller", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(appModel.controllerInputEvents) events")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isConnected ? .green : .secondary)
            }

            HStack(alignment: .top, spacing: 14) {
                StickTelemetryView(title: "Left", stick: snapshot.leftStick)
                StickTelemetryView(title: "Right", stick: snapshot.rightStick)
                TriggerTelemetryView(title: appModel.controlDisplayName(.leftTrigger), value: snapshot.value(for: .leftTrigger))
                TriggerTelemetryView(title: appModel.controlDisplayName(.rightTrigger), value: snapshot.value(for: .rightTrigger))
            }

            Text("Pressed: \(pressed.isEmpty ? "none" : pressed)")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.065))
        )
    }
}

private struct DiagnosticCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.065))
        )
    }
}

private struct StickTelemetryView: View {
    let title: String
    let stick: StickSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            AxisMeter(label: "X", value: stick.x)
            AxisMeter(label: "Y", value: stick.y)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TriggerTelemetryView: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ProgressView(value: min(max(value, 0), 1))
                .progressViewStyle(.linear)
            Text(value.formatted(.number.precision(.fractionLength(2))))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(width: 72, alignment: .leading)
    }
}

private struct AxisMeter: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12, alignment: .leading)
            GeometryReader { proxy in
                let clamped = min(max(value, -1), 1)
                let indicatorX = ((clamped + 1) / 2) * max(proxy.size.width - 10, 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))
                    Rectangle()
                        .fill(Color.secondary.opacity(0.22))
                        .frame(width: 1)
                        .frame(maxWidth: .infinity)
                        .offset(x: (proxy.size.width / 2) - 0.5)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                        .offset(x: indicatorX)
                }
            }
            .frame(width: 96, height: 10)
            Text(value.formatted(.number.precision(.fractionLength(2))))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

struct SetupBannerView: View {
    let presentation: SetupBannerPresentation
    let action: (SetupActionID) -> Void

    private var tint: Color {
        switch presentation.tone {
        case .neutral:
            return .secondary
        case .attention:
            return .orange
        case .progress:
            return .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: presentation.symbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(presentation.title)
                        .font(.headline.weight(.semibold))
                    if let stepLabel = presentation.stepLabel {
                        Text(stepLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(presentation.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !presentation.instructions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(presentation.instructions.enumerated()), id: \.offset) { index, instruction in
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Text("\(index + 1).")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(tint)
                                    .frame(width: 18, alignment: .trailing)
                                Text(instruction)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                ForEach(presentation.actions, id: \.id) { setupAction in
                    if setupAction.isProminent {
                        Button(setupAction.title) {
                            action(setupAction.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .frame(minHeight: 40)
                        .accessibilityIdentifier("setup.\(setupAction.id.rawValue)")
                    } else {
                        Button(setupAction.title) {
                            action(setupAction.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .frame(minHeight: 40)
                        .accessibilityIdentifier("setup.\(setupAction.id.rawValue)")
                    }
                }
            }
            .frame(minWidth: 210, alignment: .trailing)
        }
        .productPanel(padding: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("setup.banner")
    }
}

enum MainWindowLayoutMetrics {
    static let minimumWidth: CGFloat = 1_180
    static let minimumHeight: CGFloat = 760
    static let defaultWidth: CGFloat = 1_280
    static let defaultHeight: CGFloat = 840
    static let horizontalPadding: CGFloat = 20
    static let inspectorWidth: CGFloat = 332
}

private struct NoControllerHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No controller detected")
                .font(.headline)
            Text("Connect an Xbox or PlayStation controller by Bluetooth or USB, then open System Settings → Game Controllers if macOS does not detect it.")
                .foregroundStyle(.secondary)
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .productPanel()
    }
}

private struct CompanionSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var advancedExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProductSectionTitle(
                "Universal Control",
                subtitle: "Move through every nearby Mac from this one.",
                symbol: "rectangle.connected.to.line.below"
            )

            if appModel.companionMode == .off {
                ReadinessRow(
                    title: "Native handoff",
                    detail: appModel.virtualHardwareReady
                        ? "Virtual mouse and keyboard are active."
                        : appModel.virtualHardwareSetupTitle,
                    isReady: appModel.virtualHardwareReady
                )

                Text("Recommended. Vibe Controller uses virtual hardware on this lead Mac so Apple Universal Control keeps forwarding movement after the pointer crosses an edge.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label("Nothing to install on your other Macs", systemImage: "checkmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                if !appModel.virtualHardwareReady {
                    Text("Finish the guided setup above. Vibe Controller will recheck the permission and driver automatically when you return.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ReadinessRow(
                    title: appModel.companionMode.displayName,
                    detail: appModel.companionStatusText,
                    isReady: appModel.companionConnectionState.isConnected
                )
            }

            Divider()

            DisclosureGroup("Advanced connection mode", isExpanded: $advancedExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Use the network fallback only when Apple Universal Control is unavailable. It requires Vibe Controller on both Macs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker("Connection", selection: Binding(
                        get: { appModel.companionMode },
                        set: { appModel.setCompanionMode($0) }
                    )) {
                        ForEach(CompanionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    if appModel.companionMode == .controller {
                        controllerMacControls
                    } else if appModel.companionMode == .receiver {
                        Text("This Mac advertises itself on the local network and accepts forwarded pointer, click, scroll, and shortcut events.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if appModel.companionMode != .off {
                        Text(appModel.companionRemoteBuildSummary)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .productPanel()
        .accessibilityIdentifier("settings.universal-control")
        .onAppear {
            advancedExpanded = appModel.companionMode != .off
        }
        .onChange(of: appModel.companionMode) { _, mode in
            if mode != .off {
                withAnimation(.easeInOut(duration: 0.18)) {
                    advancedExpanded = true
                }
            }
        }
    }

    private var controllerMacControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Handoff edge", selection: Binding(
                get: { appModel.companionEdge },
                set: { appModel.setCompanionEdge($0) }
            )) {
                ForEach(CompanionEdge.allCases) { edge in
                    Text(edge.displayName).tag(edge)
                }
            }
            .pickerStyle(.menu)

            Picker("Receiver", selection: Binding(
                get: { appModel.selectedCompanionPeerID ?? "" },
                set: { appModel.selectCompanionPeer($0.isEmpty ? nil : $0) }
            )) {
                Text("Auto / first available").tag("")
                ForEach(appModel.discoveredCompanionPeers) { peer in
                    Text(peer.name).tag(peer.id)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 8) {
                Button("Connect") { appModel.connectSelectedCompanionPeer() }
                    .disabled(appModel.discoveredCompanionPeers.isEmpty)
                Button("Disconnect") { appModel.disconnectCompanion() }
                Button("Test Handoff") { appModel.forceCompanionHandoff() }
                    .disabled(!appModel.companionConnectionState.isConnected)
            }
            .controlSize(.small)
        }
    }
}
