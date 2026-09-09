import SwiftUI

struct FullUSBSettingsView: View {
    @ObservedObject var session: FullUSBSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProductSectionTitle("Full USB input", symbol: "cable.connector")
            Text("EXPERIMENTAL · XBOX SERIES")
                .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                .foregroundStyle(.secondary)
            Text(session.message)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if session.isEnabled { session.stop() } else { session.start() }
            } label: {
                Label(session.isEnabled ? "Stop full USB" : "Enable full USB",
                      systemImage: session.isEnabled ? "stop.fill" : "lock.shield")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .accessibilityIdentifier("settings.full-usb.toggle")
            if session.isReady {
                Text("\(session.receivedReports) reports · \(session.sharePresses) Share presses")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Label("Universal Control output unchanged", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else if !session.isEnabled {
                Text("Requires administrator approval each session. Other apps cannot use this controller while enabled. Stops when this app quits or your Mac sleeps.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("If vibration stops after switching back, unplug and reconnect the controller. Nothing is installed on your other Macs.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("settings.full-usb")
    }
}
