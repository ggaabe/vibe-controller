import SwiftUI

struct FullUSBSettingsView: View {
    @ObservedObject var session: FullUSBSession
    @State private var confirmRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProductSectionTitle("Full USB input", symbol: "cable.connector")
            Text("EXPERIMENTAL · XBOX SERIES")
                .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                .foregroundStyle(.secondary)
            Text(session.helperStatus.detail)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if session.hasAttemptedSession && session.message != session.helperStatus.detail {
                Text(session.message)
                    .font(.caption).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                if session.isEnabled { session.stop() } else { session.start() }
            } label: {
                Label(session.isEnabled ? "Stop full USB" : session.helperStatus.buttonTitle,
                      systemImage: session.isEnabled ? "stop.fill" : "lock.shield")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .disabled(session.helperStatus == .unavailable || session.isRemovingHelper)
            .accessibilityIdentifier("settings.full-usb.toggle")
            if session.isReady {
                Text("\(session.receivedReports) reports · \(session.sharePresses) Share presses")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Label("Universal Control output unchanged", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else if !session.isEnabled {
                Text("Other apps cannot use this controller while Full USB is enabled. Capture stops when this app quits or your Mac sleeps; helper approval remains saved.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("If vibration stops after switching back, unplug and reconnect the controller. Nothing is installed on your other Macs.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if session.helperStatus == .enabled || session.helperStatus == .requiresApproval {
                Button { confirmRemoval = true } label: {
                    Text("Remove USB Helper").frame(maxWidth: .infinity, minHeight: 40)
                }
                .disabled(session.isEnabled || session.isRemovingHelper)
                .help("Stop Full USB first. Removes helper registration without changing your profile or Universal Control support.")
            }
        }
        .alert("Remove the USB helper?", isPresented: $confirmRemoval) {
            Button("Remove Helper", role: .destructive) {
                Task { await session.removeHelperApproval() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Full USB will need setup approval again. Normal controller input, your mappings, and Universal Control are unchanged.")
        }
        .accessibilityIdentifier("settings.full-usb")
    }
}
