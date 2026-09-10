import SwiftUI

/// Only prompt for the known truncated Xbox USB input path. A disconnected
/// controller, PlayStation, or a working Share transport needs no USB capture.
struct ShareButtonSetupPolicy {
    static func needsSetup(snapshot: ControllerSnapshot) -> Bool {
        snapshot.isConnected && snapshot.controllerFamily == .xbox && snapshot.shareRequiresFullUSB
    }

    static func shouldPrompt(snapshot: ControllerSnapshot, sessionEnabled: Bool, alreadyPrompted: Bool,
                             fullUSBAvailable: Bool) -> Bool {
        fullUSBAvailable && needsSetup(snapshot: snapshot) && !sessionEnabled && !alreadyPrompted
    }

    static func involvesShare(control: ControllerControlID, layer: ControllerMappingLayer) -> Bool {
        control == .share || layer == .modifier(.share)
    }

    static let approvalMessage = "macOS is omitting Share from this controller’s normal USB input. Full USB reads the complete report. Its signed helper needs administrator approval once during setup; later sessions reuse approval without storing your password. Vibe Controller will temporarily reserve the controller, so other apps cannot use it. Keep a trackpad available. If vibration is silent after stopping Full USB, unplug and reconnect the controller."
}

struct ShareButtonSetupPresentation: Equatable {
    enum State: Equatable { case unavailable, required, approval, connecting, ready, retry }
    var state: State
    var detail: String

    var title: String {
        switch state {
        case .unavailable: "Share unavailable on this USB connection"
        case .required: "Share needs Full USB"
        case .approval: "Approve the USB helper"
        case .connecting: "Connecting Share input…"
        case .ready: "Share input is ready"
        case .retry: "Share setup did not complete"
        }
    }

    var symbol: String {
        switch state {
        case .unavailable: "info.circle"
        case .required, .approval, .retry: "lock.shield"
        case .connecting: "cable.connector"
        case .ready: "checkmark.circle.fill"
        }
    }

    var canEnable: Bool { state == .required || state == .approval || state == .retry }
    var buttonTitle: String { state == .approval ? "Open Approval Settings" : "Enable Full USB" }

    static let unavailable = Self(state: .unavailable,
        detail: "macOS does not deliver Share presses on this USB connection. Your saved Share shortcuts are kept for supported connections. Other buttons and native Universal Control are unaffected.")
}

struct ShareButtonSetupView: View {
    var snapshot: ControllerSnapshot
    @ObservedObject var session: FullUSBSession
    var promptOnAppear = false
    @State private var hasPrompted = false
    @State private var isShowingApproval = false
    @State private var didRequestSession = false

    private var needsSetup: Bool { ShareButtonSetupPolicy.needsSetup(snapshot: snapshot) }

    private var presentation: ShareButtonSetupPresentation {
        guard session.isAvailable else { return .unavailable }
        if session.isReady {
            return .init(state: .ready, detail: "Share shortcuts use the full USB session. Universal Control output is unchanged.")
        }
        if session.isEnabled { return .init(state: .connecting, detail: session.message) }
        if session.helperStatus == .requiresApproval { return .init(state: .approval, detail: session.helperStatus.detail) }
        if didRequestSession || session.hasAttemptedSession { return .init(state: .retry, detail: session.message) }
        return .init(state: .required,
                     detail: "This USB connection does not deliver Share presses. Enable Full USB to use Share and its modifier shortcuts.")
    }

    var body: some View {
        Group {
            if needsSetup || (session.isAvailable && (session.isEnabled || didRequestSession || session.hasAttemptedSession)) {
                ShareButtonSetupCard(presentation: presentation) {
                    guard session.isAvailable else { return }
                    if session.helperStatus == .requiresApproval {
                        session.openHelperSettings()
                        return
                    }
                    hasPrompted = true
                    isShowingApproval = true
                }
            }
        }
        .onAppear { promptIfNeeded() }
        .onChange(of: needsSetup) { _, _ in promptIfNeeded() }
        .alert("Enable Full USB for Share?", isPresented: $isShowingApproval) {
            Button("Enable Full USB") {
                didRequestSession = true
                session.start()
            }
            Button(promptOnAppear ? "Edit Without Enabling" : "Not Now", role: .cancel) {}
        } message: {
            Text(ShareButtonSetupPolicy.approvalMessage)
        }
    }

    private func promptIfNeeded() {
        guard promptOnAppear,
              ShareButtonSetupPolicy.shouldPrompt(snapshot: snapshot,
                  sessionEnabled: session.isEnabled, alreadyPrompted: hasPrompted,
                  fullUSBAvailable: session.isAvailable) else { return }
        hasPrompted = true
        isShowingApproval = true
    }
}

/// Pure presentation keeps the card renderable in layout tests without opening
/// devices or presenting an administrator prompt.
struct ShareButtonSetupCard: View {
    let presentation: ShareButtonSetupPresentation
    var enable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(presentation.title, systemImage: presentation.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(presentation.state == .ready ? Color.green : Color.primary)
            Text(presentation.detail)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if presentation.canEnable {
                HStack(spacing: 12) {
                    Button(action: enable) {
                        Text(presentation.buttonTitle).frame(minHeight: 40)
                    }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("share.setup.enable")
                    Text("One-time helper approval · Capture this session only")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if presentation.state == .connecting {
                ProgressView().controlSize(.small).accessibilityLabel("Waiting for Full USB")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("share.setup")
    }
}
