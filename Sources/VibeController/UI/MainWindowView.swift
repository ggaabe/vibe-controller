import AppKit
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportDocument: ExportProfileDocument?

    var body: some View {
        VStack(spacing: 18) {
            header
                .zIndex(2)
            diagnosticsStrip
                .zIndex(2)
            if appModel.accessibilityTrusted {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .zIndex(0)
            } else {
                PermissionSetupView()
                    .zIndex(0)
            }
            footer
                .zIndex(2)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.10, green: 0.11, blue: 0.13), Color(red: 0.07, green: 0.08, blue: 0.10)]
                    : [Color(NSColor.windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .sheet(item: $appModel.presentedSheet) { selection in
            switch selection {
            case .mapping(let control, let layer):
                MappingSheetView(control: control, layer: layer)
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
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Vibe Controller")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(appModel.controllerSnapshot.controllerName ?? "Waiting for controller")
                    .font(.headline)
                HStack(spacing: 10) {
                    if let connection = appModel.controllerSnapshot.connectionSummary {
                        Label(connection, systemImage: "cable.connector")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let battery = appModel.batterySummary {
                        Label(battery, systemImage: "battery.75")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 12) {
                StatusBadgeView(state: appModel.statusBadgeState)
                HStack(spacing: 8) {
                    Label(appModel.runtimeStatusText, systemImage: appModel.isRuntimeEnabled ? "power.circle.fill" : "power.circle")
                    Label(appModel.listeningStatusText, systemImage: "gamecontroller.fill")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                Picker("Profile", selection: Binding(
                    get: { appModel.activeProfileID },
                    set: { appModel.selectProfile($0) }
                )) {
                    ForEach(appModel.availableProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private var diagnosticsStrip: some View {
        HStack(spacing: 12) {
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
                title: "Actions",
                value: appModel.lastActionStatus,
                detail: "Space switching and desktop action feedback.",
                symbol: "sparkles",
                tint: .secondary
            )
            VStack(alignment: .leading, spacing: 8) {
                Text("Test")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Button("Test Cross-Mac Sweep") {
                    appModel.testCursorNudge()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button("Test Left Click") {
                    appModel.testLeftClick()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Capture Remote Proof") {
                    appModel.captureRemoteProof()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!appModel.virtualHardwareReady)
            }
            .frame(width: 200, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 16) {
                CursorSettingsView()
                    .environmentObject(appModel)
                    .frame(width: 360)

                CompanionSettingsView()
                    .environmentObject(appModel)
                    .frame(width: 360)
            }

            VStack(spacing: 16) {
                ControllerDiagramView()
                    .environmentObject(appModel)
                    .frame(maxWidth: .infinity, alignment: .top)
                if !appModel.controllerSnapshot.isConnected {
                    NoControllerHelpView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .clipped()
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Enable") {
                appModel.setRuntimeEnabled(true)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!appModel.accessibilityTrusted || appModel.isRuntimeEnabled)

            Button("Disable") {
                appModel.setRuntimeEnabled(false)
            }
            .buttonStyle(.bordered)
            .disabled(!appModel.isRuntimeEnabled)

            Button("Reset to Defaults") {
                appModel.resetActiveProfileToDefaults()
            }

            Spacer()

            if let error = appModel.lastErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Button("Import Profile") {
                isImporting = true
            }

            Button("Export Profile") {
                do {
                    exportDocument = try ExportProfileDocument(profile: appModel.activeProfile)
                    isExporting = true
                } catch {
                    appModel.lastErrorMessage = error.localizedDescription
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct LiveControllerCard: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        let snapshot = appModel.controllerSnapshot
        let pressed = snapshot.pressedControls.map(\.displayName).sorted().joined(separator: ", ")

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
                TriggerTelemetryView(title: "LT", value: snapshot.value(for: .leftTrigger))
                TriggerTelemetryView(title: "RT", value: snapshot.value(for: .rightTrigger))
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
                .fill(Color(NSColor.controlBackgroundColor))
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
                .fill(Color(NSColor.controlBackgroundColor))
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

private struct PermissionSetupView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Accessibility setup")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("Step 1 of 3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text("Vibe Controller automatically checks its setup on every launch. Accessibility lets controller input move the pointer and send clicks and keyboard shortcuts across macOS.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Open Privacy & Security") {
                    appModel.requestAccessibilitySetup()
                }
                .buttonStyle(.borderedProminent)

                Button("Refresh Status") {
                    appModel.permissionManager.refresh()
                }
            }
            HStack(spacing: 8) {
                Image(systemName: appModel.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(appModel.accessibilityTrusted ? .green : .orange)
                Text(appModel.accessibilityTrusted ? "Accessibility granted" : "Accessibility not granted yet")
                    .font(.subheadline.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .leading)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

private struct NoControllerHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No controller detected")
                .font(.headline)
            Text("Connect your Xbox controller by Bluetooth or USB, then open System Settings → Game Controllers to verify macOS can see it.")
                .foregroundStyle(.secondary)
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

private struct CompanionSettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Cross-Mac Control")
                    .font(.headline)
                Spacer()
                Text(appModel.companionStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            Picker("Mode", selection: Binding(
                get: { appModel.companionMode },
                set: { appModel.setCompanionMode($0) }
            )) {
                ForEach(CompanionMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)

            if appModel.companionMode == .off {
                Label("Uses virtual mouse hardware on the lead Mac so Universal Control keeps forwarding motion after the pointer crosses. The other Mac does not need Vibe Controller.", systemImage: "rectangle.connected.to.line.below")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(appModel.nativeUniversalControlStatusText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: appModel.virtualHardwareReady ? "checkmark.circle.fill" : "gearshape.2.fill")
                            .foregroundStyle(appModel.virtualHardwareReady ? .green : .orange)
                        Text(appModel.virtualHardwareSetupTitle)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if let step = appModel.virtualHardwareSetupStepLabel {
                            Text(step)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(appModel.virtualHardwareSetupDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !appModel.virtualHardwareReady {
                        HStack(spacing: 8) {
                            switch appModel.virtualHardwareSetupPhase {
                            case .needsAccessibility:
                                Button("Grant Accessibility") {
                                    appModel.retryAutomaticSetup()
                                }
                                .buttonStyle(.borderedProminent)

                            case .needsSupportInstall, .driverVersionMismatch:
                                Button("Open Installer") {
                                    appModel.openVirtualHardwareInstaller()
                                }
                                .buttonStyle(.borderedProminent)

                            case .needsDriverApproval:
                                Button("Open Driver Settings") {
                                    appModel.openDriverExtensionSettings()
                                }
                                .buttonStyle(.borderedProminent)

                            case .checking, .startingVirtualHardware:
                                ProgressView()
                                    .controlSize(.small)
                                Button("Refresh") {
                                    appModel.refreshVirtualHardwareSupport()
                                }

                            case .missingBundledInstaller:
                                EmptyView()

                            case .ready:
                                EmptyView()
                            }

                            Button("Run Setup Again") {
                                appModel.retryAutomaticSetup()
                            }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
            } else if appModel.companionMode == .controller {
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

                HStack(spacing: 10) {
                    Button("Connect") {
                        appModel.connectSelectedCompanionPeer()
                    }
                    .disabled(appModel.discoveredCompanionPeers.isEmpty)

                    Button("Disconnect") {
                        appModel.disconnectCompanion()
                    }
                }

                HStack(spacing: 10) {
                    Button("Force Handoff") {
                        appModel.forceCompanionHandoff()
                    }
                    .disabled({
                        if case .connected = appModel.companionConnectionState {
                            return false
                        }
                        return true
                    }())

                    Button("Return Local") {
                        appModel.forceReturnLocal()
                    }
                }
            } else if appModel.companionMode == .receiver {
                Text("Run this mode on the second Mac. It advertises itself on the local network and accepts forwarded pointer, click, scroll, and shortcut events.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if appModel.companionMode != .off {
                Text("This is the advanced route: when the local cursor pushes through the selected edge, Vibe Controller forwards motion and desktop actions to the other Mac until the remote cursor reaches the return edge.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Peer metadata")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(appModel.companionRemoteBuildSummary)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text("Handoff debug")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(appModel.companionHandoffDebug)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}
