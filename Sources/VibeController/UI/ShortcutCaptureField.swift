import AppKit
import SwiftUI

struct ShortcutCaptureField: NSViewRepresentable {
    @Binding var shortcut: ShortcutDescriptor?
    @Binding var isCapturing: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: $shortcut, isCapturing: $isCapturing)
    }

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.coordinator = context.coordinator
        view.refresh(shortcut: shortcut, isCapturing: isCapturing)
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.coordinator = context.coordinator
        nsView.refresh(shortcut: shortcut, isCapturing: isCapturing)
    }

    final class Coordinator: NSObject {
        @Binding var shortcut: ShortcutDescriptor?
        @Binding var isCapturing: Bool

        init(shortcut: Binding<ShortcutDescriptor?>, isCapturing: Binding<Bool>) {
            self._shortcut = shortcut
            self._isCapturing = isCapturing
        }

        func beginCapture() {
            isCapturing = true
        }

        func endCapture() {
            isCapturing = false
        }

        func clearShortcut() {
            shortcut = nil
            isCapturing = false
        }

        func setShortcut(_ shortcut: ShortcutDescriptor) {
            self.shortcut = shortcut
            isCapturing = false
        }
    }
}

final class ShortcutCaptureNSView: NSView {
    weak var coordinator: ShortcutCaptureField.Coordinator?

    private let label = NSTextField(labelWithString: "")
    private var shortcut: ShortcutDescriptor?
    private var isCapturing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1

        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 40).isActive = true

        refresh(shortcut: nil, isCapturing: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        coordinator?.beginCapture()
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        coordinator?.endCapture()
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else { return }

        let keyCode = UInt16(event.keyCode)
        if keyCode == 53 {
            coordinator?.endCapture()
            return
        }
        if ShortcutDescriptor.modifierKeyCodes.contains(keyCode) {
            return
        }

        let modifiers = KeyboardModifier.from(event.modifierFlags)
        let shortcut = ShortcutDescriptor(keyCode: keyCode, modifiers: modifiers)
        guard !shortcut.isModifierOnly else { return }
        coordinator?.setShortcut(shortcut)
    }

    func refresh(shortcut: ShortcutDescriptor?, isCapturing: Bool) {
        self.shortcut = shortcut
        self.isCapturing = isCapturing
        updateAppearance()
        if isCapturing, window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
    }

    private func updateAppearance() {
        label.stringValue = if isCapturing {
            "Press keyboard shortcut now"
        } else if let shortcut {
            shortcut.displayString
        } else {
            "Click to capture shortcut"
        }

        label.textColor = isCapturing ? .controlAccentColor : .labelColor
        layer?.backgroundColor = (isCapturing ? NSColor.controlAccentColor.withAlphaComponent(0.08) : NSColor.textBackgroundColor).cgColor
        layer?.borderColor = (isCapturing ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }
}

private extension KeyboardModifier {
    static func from(_ modifierFlags: NSEvent.ModifierFlags) -> [KeyboardModifier] {
        var modifiers: [KeyboardModifier] = []
        if modifierFlags.contains(.control) {
            modifiers.append(.control)
        }
        if modifierFlags.contains(.option) {
            modifiers.append(.option)
        }
        if modifierFlags.contains(.shift) {
            modifiers.append(.shift)
        }
        if modifierFlags.contains(.command) {
            modifiers.append(.command)
        }
        return ShortcutDescriptor.normalizeModifiers(modifiers)
    }
}
