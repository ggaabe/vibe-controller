import SwiftUI

struct MappingSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    let control: ControllerControlID

    @State private var mapping = ControllerActionMapping()
    @State private var isCapturingShortcut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(control.displayName)
                .font(.title2.weight(.semibold))
            Text("Current mapping: \(appModel.mappingSummary(for: control))")
                .foregroundStyle(.secondary)

            Form {
                Picker("Action type", selection: $mapping.actionType) {
                    ForEach(ActionType.allCases) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .onChange(of: mapping.actionType) { _, newValue in
                    if !newValue.supportedTriggerModes.contains(mapping.triggerMode) {
                        mapping.triggerMode = newValue.defaultTriggerMode
                    }
                }

                if mapping.actionType == .keyboardShortcut {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shortcut")
                            .font(.subheadline.weight(.medium))
                        ShortcutCaptureField(
                            shortcut: $mapping.shortcut,
                            isCapturing: $isCapturingShortcut
                        )
                        Text("System-managed shortcuts like ⌘⌃⇧4 may not reach the capture field. Use a quick set button if macOS intercepts the key combo. Use Clear Shortcut to remove a mapping.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Button("Return") {
                                    mapping.shortcut = ShortcutDescriptor(keyCode: 36, modifiers: [])
                                }
                                Button("Escape") {
                                    mapping.shortcut = ShortcutDescriptor(keyCode: 53, modifiers: [])
                                }
                                Button("fn") {
                                    mapping.shortcut = ShortcutDescriptor(keyCode: 63, modifiers: [])
                                }
                                Button("Delete") {
                                    mapping.shortcut = ShortcutDescriptor(keyCode: 51, modifiers: [])
                                }
                                Button("⌘⇧2") {
                                    mapping.shortcut = ShortcutDescriptor(keyCode: 19, modifiers: [.command, .shift])
                                }
                            }
                            HStack(spacing: 10) {
                                Button("⌘⌃⇧4") {
                                    mapping.shortcut = ShortcutDescriptor(keyCode: 21, modifiers: [.command, .control, .shift])
                                }
                                Button("Forward Delete") {
                                    mapping.shortcut = ShortcutDescriptor(keyCode: 117, modifiers: [])
                                }
                                Button("Clear Shortcut") {
                                    mapping.shortcut = nil
                                }
                            }
                        }
                        if let validationError {
                            Text(validationError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        if let duplicateWarning {
                            Text(duplicateWarning)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                        if let conflictWarning {
                            Text(conflictWarning)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Picker("Trigger mode", selection: $mapping.triggerMode) {
                    ForEach(mapping.actionType.supportedTriggerModes) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                if mapping.triggerMode == .repeatWhileHeld {
                    SliderSettingRow(
                        title: "Repeat delay",
                        value: $mapping.repeatDelay,
                        range: 0.05...1.2,
                        formatter: { String(format: "%.2fs", $0) }
                    )
                    SliderSettingRow(
                        title: "Repeat interval",
                        value: $mapping.repeatInterval,
                        range: 0.02...0.4,
                        formatter: { String(format: "%.2fs", $0) }
                    )
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    appModel.saveMapping(mapping, for: control)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            mapping = appModel.mapping(for: control)
        }
    }

    private var canSave: Bool {
        validationError == nil
    }

    private var validationError: String? {
        guard mapping.actionType == .keyboardShortcut else { return nil }
        guard let shortcut = mapping.shortcut else {
            return "Shortcut must include a non-modifier key"
        }
        return shortcut.isModifierOnly ? "Shortcut must include a non-modifier key" : nil
    }

    private var duplicateWarning: String? {
        guard let shortcut = mapping.shortcut else { return nil }
        let duplicates = appModel.duplicateAssignments(for: shortcut, excluding: control)
        guard !duplicates.isEmpty else { return nil }
        let names = duplicates.map(\.displayName).joined(separator: ", ")
        return "This shortcut is already used by \(names)."
    }

    private var conflictWarning: String? {
        mapping.shortcut?.knownSystemConflictWarning
    }
}
