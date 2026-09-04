import SwiftUI

struct MappingSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    let control: ControllerControlID
    let layer: ControllerMappingLayer
    let scope: ControllerMappingScope

    @State private var mapping = ControllerActionMapping()
    @State private var isCapturingShortcut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))
            if scope.applicationBundleIdentifier != nil {
                HStack(spacing: 8) {
                    Label(
                        "Only in \(appModel.mappingScopeDisplayName(scope))",
                        systemImage: "app.badge"
                    )
                    .font(.subheadline.weight(.medium))
                    if !appModel.hasMappingOverride(for: control, in: layer, scope: scope) {
                        Text("Uses All Apps until you save an override")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if case .modifier(let modifierControl) = layer {
                HStack(spacing: 8) {
                    Label(
                        "While holding \(appModel.controlDisplayName(modifierControl))",
                        systemImage: "square.3.layers.3d"
                    )
                    .font(.subheadline.weight(.medium))
                    if scope.applicationBundleIdentifier == nil,
                       !appModel.hasMappingOverride(for: control, in: layer, scope: scope) {
                        Text("Uses Default until you save an override")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("Current mapping: \(appModel.mapping(for: control, in: layer, scope: scope).summary)")
                .font(.subheadline)
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

                if mapping.actionType.crossEdgeDirection != nil {
                    Label(
                        "Sends a short virtual-mouse sweep through this Universal Control edge. Virtual Hardware Support must be ready.",
                        systemImage: "rectangle.connected.to.line.below"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if mapping.actionType == .keyboardShortcut {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shortcut")
                            .font(.subheadline.weight(.medium))
                        ShortcutCaptureField(
                            shortcut: $mapping.shortcut,
                            isCapturing: $isCapturingShortcut
                        )
                        Text("Click the field and press a shortcut. Left/right pairs of Command, Option, Shift, and Control can be recorded together. You can also use a quick set button for a system-owned key.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Function keys")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                            spacing: 8
                        ) {
                            ForEach(1...12, id: \.self) { number in
                                Button("F\(number)") {
                                    guard let keyCode = ShortcutDescriptor.functionKeyCodes[number] else { return }
                                    mapping.shortcut = ShortcutDescriptor(keyCode: keyCode, modifiers: [])
                                    isCapturingShortcut = false
                                }
                            }
                        }
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                            spacing: 8
                        ) {
                            Button("Return") {
                                mapping.shortcut = ShortcutDescriptor(keyCode: 36, modifiers: [])
                            }
                            Button("Escape") {
                                mapping.shortcut = ShortcutDescriptor(keyCode: 53, modifiers: [])
                            }
                            Button("fn") {
                                mapping.shortcut = ShortcutDescriptor(keyCode: 63, modifiers: [])
                            }
                            Button("Right Option") {
                                mapping.shortcut = ShortcutDescriptor(keyCode: 61, modifiers: [])
                                mapping.triggerMode = .holdWhilePressed
                                isCapturingShortcut = false
                            }
                            Button("Delete") {
                                mapping.shortcut = ShortcutDescriptor(keyCode: 51, modifiers: [])
                            }
                            Button("⌘⇧2") {
                                mapping.shortcut = ShortcutDescriptor(keyCode: 19, modifiers: [.command, .shift])
                            }
                            Button("L⌘ + R⌘") {
                                mapping.shortcut = .leftRightModifierChord(.command)
                                isCapturingShortcut = false
                            }
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
                if appModel.hasMappingOverride(for: control, in: layer, scope: scope) {
                    Button(scope.applicationBundleIdentifier == nil ? "Use Default" : "Use All Apps") {
                        appModel.clearMappingOverride(for: control, in: layer, scope: scope)
                        dismiss()
                    }
                    .frame(minHeight: 40)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .frame(minHeight: 40)
                Button(saveButtonTitle) {
                    appModel.saveMapping(mapping, for: control, in: layer, scope: scope)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 40)
                .disabled(!canSave)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            mapping = appModel.mapping(for: control, in: layer, scope: scope)
        }
    }

    private var title: String {
        let controlTitle: String
        switch layer {
        case .base:
            controlTitle = appModel.controlDisplayName(control)
        case .modifier(let modifierControl):
            controlTitle = "\(appModel.controlDisplayName(modifierControl)) + \(appModel.controlDisplayName(control))"
        }
        guard scope.applicationBundleIdentifier != nil else { return controlTitle }
        return "\(appModel.mappingScopeDisplayName(scope)) · \(controlTitle)"
    }

    private var saveButtonTitle: String {
        if scope.applicationBundleIdentifier != nil {
            return "Save App Override"
        }
        if case .modifier = layer {
            return "Save Override"
        }
        return "Save"
    }

    private var canSave: Bool {
        validationError == nil
    }

    private var validationError: String? {
        guard mapping.actionType == .keyboardShortcut else { return nil }
        guard let shortcut = mapping.shortcut else {
            return "Choose a shortcut"
        }
        return shortcut.isAssignable(for: mapping.triggerMode)
            ? nil
            : "Use a non-modifier key, a matching left/right pair, or Hold while pressed for one modifier key"
    }

    private var duplicateWarning: String? {
        guard let shortcut = mapping.shortcut else { return nil }
        let duplicates = appModel.duplicateAssignments(
            for: shortcut,
            excluding: control,
            in: layer,
            scope: scope
        )
        guard !duplicates.isEmpty else { return nil }
        let names = duplicates.map { appModel.controlDisplayName($0) }.joined(separator: ", ")
        return "This shortcut is already used by \(names)."
    }

    private var conflictWarning: String? {
        mapping.shortcut?.knownSystemConflictWarning
    }
}
