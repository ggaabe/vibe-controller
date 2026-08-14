import AppKit
import CoreGraphics
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
    private var keyboardEventTap: CFMachPort?
    private var keyboardEventTapSource: CFRunLoopSource?
    private var localSystemDefinedMonitor: Any?
    private var globalSystemDefinedMonitor: Any?
    private var pressedModifierKeyCodes = Set<UInt16>()

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
        isCapturing = true
        updateAppearance()
        startCaptureMonitors()
        coordinator?.beginCapture()
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        isCapturing = false
        stopCaptureMonitors()
        coordinator?.endCapture()
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else { return }
        capture(keyCode: UInt16(event.keyCode), modifiers: KeyboardModifier.from(event.modifierFlags))
    }

    func refresh(shortcut: ShortcutDescriptor?, isCapturing: Bool) {
        self.shortcut = shortcut
        self.isCapturing = isCapturing
        if isCapturing {
            startCaptureMonitors()
        } else {
            stopCaptureMonitors()
        }
        updateAppearance()
        if isCapturing, window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
    }

    fileprivate func handleKeyboardEventTap(
        type: CGEventType,
        keyCode: UInt16,
        eventFlags: CGEventFlags
    ) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let keyboardEventTap {
                CGEvent.tapEnable(tap: keyboardEventTap, enable: true)
            }
            return false
        }

        guard isCapturing else { return false }
        if type == .flagsChanged,
           ShortcutDescriptor.modifierKeyCodes.contains(keyCode),
           keyCode != 57,
           keyCode != 63 {
            if pressedModifierKeyCodes.contains(keyCode) {
                pressedModifierKeyCodes.remove(keyCode)
            } else {
                pressedModifierKeyCodes.insert(keyCode)
            }
            if let shortcut = ShortcutDescriptor.leftRightModifierChord(
                pressedKeyCodes: pressedModifierKeyCodes
            ) {
                capture(shortcut)
            }
            return true
        }
        guard type == .keyDown else { return false }
        capture(keyCode: keyCode, modifiers: KeyboardModifier.from(eventFlags))
        return true
    }

    private func captureSystemDefinedEvent(_ event: NSEvent) -> Bool {
        guard isCapturing,
              let keyCode = ShortcutCaptureEventInterpreter.functionKeyCode(
                systemDefinedData1: Int64(event.data1)
              ) else {
            return false
        }

        let modifiers = KeyboardModifier.from(event.modifierFlags)
        if Thread.isMainThread {
            capture(keyCode: keyCode, modifiers: modifiers)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.capture(keyCode: keyCode, modifiers: modifiers)
            }
        }
        return true
    }

    private func capture(keyCode: UInt16, modifiers: [KeyboardModifier]) {
        guard isCapturing else { return }
        if keyCode == 53 {
            isCapturing = false
            stopCaptureMonitors()
            updateAppearance()
            coordinator?.endCapture()
            return
        }
        guard !ShortcutDescriptor.modifierKeyCodes.contains(keyCode) else { return }

        capture(ShortcutDescriptor(keyCode: keyCode, modifiers: modifiers))
    }

    private func capture(_ shortcut: ShortcutDescriptor) {
        guard shortcut.isAssignable else { return }

        self.shortcut = shortcut
        isCapturing = false
        stopCaptureMonitors()
        updateAppearance()
        coordinator?.setShortcut(shortcut)
    }

    private func startCaptureMonitors() {
        if keyboardEventTap == nil {
            pressedModifierKeyCodes.removeAll()
            let eventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
                | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            if let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: shortcutCaptureEventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) {
                let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
                keyboardEventTap = tap
                keyboardEventTapSource = source
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }

        if localSystemDefinedMonitor == nil {
            localSystemDefinedMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) {
                [weak self] event in
                self?.captureSystemDefinedEvent(event) == true ? nil : event
            }
        }
        if globalSystemDefinedMonitor == nil {
            globalSystemDefinedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) {
                [weak self] event in
                _ = self?.captureSystemDefinedEvent(event)
            }
        }
    }

    private func stopCaptureMonitors() {
        pressedModifierKeyCodes.removeAll()
        if let localSystemDefinedMonitor {
            NSEvent.removeMonitor(localSystemDefinedMonitor)
            self.localSystemDefinedMonitor = nil
        }
        if let globalSystemDefinedMonitor {
            NSEvent.removeMonitor(globalSystemDefinedMonitor)
            self.globalSystemDefinedMonitor = nil
        }
        if let keyboardEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), keyboardEventTapSource, .commonModes)
        }
        if let keyboardEventTap {
            CGEvent.tapEnable(tap: keyboardEventTap, enable: false)
            CFMachPortInvalidate(keyboardEventTap)
        }
        keyboardEventTapSource = nil
        keyboardEventTap = nil
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

    static func from(_ eventFlags: CGEventFlags) -> [KeyboardModifier] {
        var modifiers: [KeyboardModifier] = []
        if eventFlags.contains(.maskControl) {
            modifiers.append(.control)
        }
        if eventFlags.contains(.maskAlternate) {
            modifiers.append(.option)
        }
        if eventFlags.contains(.maskShift) {
            modifiers.append(.shift)
        }
        if eventFlags.contains(.maskCommand) {
            modifiers.append(.command)
        }
        return ShortcutDescriptor.normalizeModifiers(modifiers)
    }
}

enum ShortcutCaptureEventInterpreter {
    private static let missionControlMediaKeyCode: Int64 = 2

    static func functionKeyCode(systemDefinedData1 data1: Int64) -> UInt16? {
        let mediaKeyCode = (data1 & 0xFFFF_0000) >> 16
        guard mediaKeyCode == missionControlMediaKeyCode else { return nil }

        let state = (data1 & 0x0000_FF00) >> 8
        guard state == 0x0A || state == 0x0C else { return nil }
        return ShortcutDescriptor.functionKeyCodes[3]
    }
}

private nonisolated(unsafe) let shortcutCaptureEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let captureViewPointer = UInt(bitPattern: userInfo)
    let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    let eventFlagsRawValue = event.flags.rawValue
    let shouldSuppress = MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: captureViewPointer) else { return false }
        let captureView = Unmanaged<ShortcutCaptureNSView>
            .fromOpaque(pointer)
            .takeUnretainedValue()
        return captureView.handleKeyboardEventTap(
            type: type,
            keyCode: keyCode,
            eventFlags: CGEventFlags(rawValue: eventFlagsRawValue)
        )
    }
    return shouldSuppress ? nil : Unmanaged.passUnretained(event)
}
