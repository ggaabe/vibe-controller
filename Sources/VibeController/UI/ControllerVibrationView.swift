import SwiftUI

struct MappingVibrationEditor: View {
    @Binding var pattern: ControllerVibration
    @ObservedObject var haptics: ControllerHaptics

    var body: some View {
        Section {
            Picker("Vibration pattern", selection: $pattern) {
                ForEach(ControllerVibration.allCases) { pattern in
                    Text(pattern.displayName).tag(pattern)
                }
            }
            .frame(minHeight: 40)
            .accessibilityIdentifier("mapping.vibration.pattern")
            Text(pattern.detail)
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button {
                    haptics.preview(pattern)
                } label: {
                    Label("Test vibration", systemImage: "play.fill")
                        .frame(minHeight: 40)
                }
                .disabled(pattern == .none || !haptics.isEnabled || !haptics.status.canPlay)
                .accessibilityIdentifier("mapping.vibration.test")
                .help("Plays only the selected vibration. Does not run the command or save changes.")
                Spacer()
                if !haptics.isEnabled {
                    Button("Enable vibration") { haptics.isEnabled = true }
                        .frame(minHeight: 40)
                        .help("Unmutes vibration for all mappings on this Mac.")
                }
            }
            Text(haptics.isEnabled ? haptics.status.message : "Vibration is muted on this Mac. Patterns are still saved with your profile.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Plays once, not on every repeat. Modifier buttons play when their layer is engaged. Feedback acknowledges a command, not completion in another app.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Vibration")
        }
    }
}

struct ControllerVibrationSettingsView: View {
    @ObservedObject var haptics: ControllerHaptics
    let applySuggestions: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProductSectionTitle("Vibration", symbol: "waveform")
            Toggle("Haptic feedback", isOn: $haptics.isEnabled)
                .toggleStyle(.switch)
                .frame(minHeight: 40)
                .accessibilityIdentifier("settings.haptics.enabled")
                .help("Mute or enable every controller vibration on this Mac.")
            Text(haptics.status.message)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if haptics.isEnabled {
                SliderSettingRow(title: "Strength", value: $haptics.strength, range: 0.1...1,
                                 formatter: { "\(Int($0 * 100))%" })
                Toggle("Pulse on connection", isOn: $haptics.connectionFeedback)
                    .frame(minHeight: 40)
                Button("Test vibration") { haptics.preview(.doubleTap) }
                    .frame(minHeight: 40)
                    .disabled(!haptics.status.canPlay)
                    .accessibilityIdentifier("settings.haptics.test")
            }
            Button("Use suggested patterns", action: applySuggestions)
                .frame(minHeight: 40)
                .accessibilityIdentifier("settings.haptics.suggestions")
                .help("Replaces vibration patterns in the current profile and enables feedback. Shortcuts and cursor settings stay unchanged.")
            Text("Customize each pattern in its button editor. Suggestions change feedback only, in the current profile.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("settings.haptics")
    }
}
