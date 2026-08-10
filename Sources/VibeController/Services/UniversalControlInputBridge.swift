import CoreGraphics
import Foundation
import IOKit
import IOKit.hidsystem
import simd

private final class LegacyHIDEventPoster: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: io_connect_t?
    let initializationMessage: String

    init() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching(kIOHIDSystemClass)
        )
        guard service != IO_OBJECT_NULL else {
            initializationMessage = "IOHIDSystem is unavailable; using Quartz cursor fallback."
            return
        }
        defer { IOObjectRelease(service) }

        var openedConnection = io_connect_t()
        let result = IOServiceOpen(
            service,
            mach_task_self_,
            UInt32(kIOHIDParamConnectType),
            &openedConnection
        )
        guard result == KERN_SUCCESS else {
            initializationMessage = String(
                format: "Could not open IOHIDSystem (0x%08x); using Quartz cursor fallback.",
                result
            )
            return
        }

        connection = openedConnection
        initializationMessage = "Legacy relative pointer fallback is ready."
    }

    deinit {
        if let connection {
            IOServiceClose(connection)
        }
    }

    var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connection != nil
    }

    func post(
        eventType: UInt32,
        eventData: inout NXEventData,
        includeGlobalFlags: Bool,
        eventFlags: UInt32
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let connection else { return false }

        var options = UInt32(kIOHIDSetRelativeCursorPosition | kIOHIDPostHIDManagerEvent)
        if includeGlobalFlags {
            options |= UInt32(kIOHIDSetGlobalEventFlags)
        }

        let result = IOHIDPostEvent(
            connection,
            eventType,
            IOGPoint(x: 0, y: 0),
            &eventData,
            UInt32(kNXEventDataVersion),
            eventFlags,
            options
        )
        return result == KERN_SUCCESS
    }
}

private final class RelativePointerOutput: @unchecked Sendable {
    private let lock = NSLock()
    private let virtualTransport: VirtualHIDCommandTransport
    private let legacyPoster: LegacyHIDEventPoster
    private var pendingDelta = SIMD2<Double>.zero
    private var buttons: UInt32 = 0

    init(
        virtualTransport: VirtualHIDCommandTransport,
        legacyPoster: LegacyHIDEventPoster
    ) {
        self.virtualTransport = virtualTransport
        self.legacyPoster = legacyPoster
    }

    var isVirtualPointingReady: Bool {
        virtualTransport.isPointingReady
    }

    func postRelativePointer(delta: SIMD2<Double>) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        pendingDelta += delta
        let dx = Int32(clamping: Int(pendingDelta.x.rounded(.towardZero)))
        let dy = Int32(clamping: Int(pendingDelta.y.rounded(.towardZero)))
        guard dx != 0 || dy != 0 else { return true }

        var eventData = NXEventData()
        eventData.mouseMove.dx = dx
        eventData.mouseMove.dy = dy

        let posted = postVirtualPointer(dx: dx, dy: dy) || legacyPoster.post(
            eventType: UInt32(NX_MOUSEMOVED),
            eventData: &eventData,
            includeGlobalFlags: false,
            eventFlags: 0
        )
        guard posted else {
            pendingDelta = .zero
            return false
        }

        pendingDelta -= SIMD2<Double>(Double(dx), Double(dy))
        return true
    }

    func postMouseButton(_ button: CGMouseButton, isDown: Bool, clickCount: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let mask = UInt32(1) << UInt32(button.rawValue)
        if isDown {
            buttons |= mask
        } else {
            buttons &= ~mask
        }
        if virtualTransport.postPointing(x: 0, y: 0, buttons: buttons) {
            return true
        }

        let eventType: UInt32
        switch (button, isDown) {
        case (.left, true):
            eventType = UInt32(NX_LMOUSEDOWN)
        case (.left, false):
            eventType = UInt32(NX_LMOUSEUP)
        case (.right, true):
            eventType = UInt32(NX_RMOUSEDOWN)
        case (.right, false):
            eventType = UInt32(NX_RMOUSEUP)
        case (_, true):
            eventType = UInt32(NX_OMOUSEDOWN)
        case (_, false):
            eventType = UInt32(NX_OMOUSEUP)
        }

        var eventData = NXEventData()
        eventData.mouse.buttonNumber = UInt8(clamping: Int(button.rawValue))
        eventData.mouse.click = Int32(clamping: clickCount)
        eventData.mouse.pressure = isDown ? 255 : 0
        return legacyPoster.post(
            eventType: eventType,
            eventData: &eventData,
            includeGlobalFlags: false,
            eventFlags: 0
        )
    }

    func postScroll(vertical: Int32, horizontal: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if virtualTransport.postPointing(
            x: 0,
            y: 0,
            verticalWheel: Int8(clamping: vertical),
            horizontalWheel: Int8(clamping: horizontal),
            buttons: buttons
        ) {
            return true
        }

        var eventData = NXEventData()
        eventData.scrollWheel.deltaAxis1 = Int16(clamping: Int(vertical))
        eventData.scrollWheel.deltaAxis2 = Int16(clamping: Int(horizontal))
        eventData.scrollWheel.fixedDeltaAxis1 = vertical.multipliedReportingOverflow(by: 65_536).partialValue
        eventData.scrollWheel.fixedDeltaAxis2 = horizontal.multipliedReportingOverflow(by: 65_536).partialValue
        eventData.scrollWheel.pointDeltaAxis1 = vertical
        eventData.scrollWheel.pointDeltaAxis2 = horizontal
        return legacyPoster.post(
            eventType: UInt32(NX_SCROLLWHEELMOVED),
            eventData: &eventData,
            includeGlobalFlags: false,
            eventFlags: 0
        )
    }

    private func postVirtualPointer(dx: Int32, dy: Int32) -> Bool {
        guard virtualTransport.isPointingReady else { return false }
        var remainingX = dx
        var remainingY = dy
        repeat {
            let stepX = Int8(clamping: remainingX)
            let stepY = Int8(clamping: remainingY)
            guard virtualTransport.postPointing(x: stepX, y: stepY, buttons: buttons) else {
                return false
            }
            remainingX -= Int32(stepX)
            remainingY -= Int32(stepY)
        } while remainingX != 0 || remainingY != 0
        return true
    }
}

/// Prefers a DriverKit-backed virtual mouse and keyboard that Universal Control
/// treats like physical hardware, with IOHIDSystem retained as a local-only
/// compatibility fallback.
@MainActor
final class UniversalControlInputBridge {
    private let virtualHIDBridge: PrivilegedVirtualHIDBridge
    private nonisolated let legacyPoster: LegacyHIDEventPoster
    private nonisolated let relativePointerOutput: RelativePointerOutput
    var onStatusChange: (() -> Void)? {
        didSet {
            virtualHIDBridge.onStatusChange = onStatusChange
        }
    }

    init() {
        let virtualHIDBridge = PrivilegedVirtualHIDBridge()
        let legacyPoster = LegacyHIDEventPoster()
        self.virtualHIDBridge = virtualHIDBridge
        self.legacyPoster = legacyPoster
        relativePointerOutput = RelativePointerOutput(
            virtualTransport: virtualHIDBridge.commandTransport,
            legacyPoster: legacyPoster
        )
    }

    var isAvailable: Bool {
        virtualHIDBridge.isPointingReady || legacyPoster.isAvailable
    }

    var isVirtualHardwareReady: Bool {
        virtualHIDBridge.isPointingReady && virtualHIDBridge.isKeyboardReady
    }

    var isVirtualHardwareDriverActivated: Bool {
        virtualHIDBridge.isDriverActivated
    }

    var isVirtualHardwareDriverConnected: Bool {
        virtualHIDBridge.isDriverConnected
    }

    var isVirtualHardwareDriverVersionMismatched: Bool {
        virtualHIDBridge.isDriverVersionMismatched
    }

    var hasReceivedVirtualHardwareDriverStatus: Bool {
        virtualHIDBridge.hasReceivedDriverStatus
    }

    var initializationMessage: String {
        if isVirtualHardwareReady {
            return virtualHIDBridge.statusMessage
        }
        return "\(virtualHIDBridge.statusMessage) \(legacyPoster.initializationMessage)"
    }

    func refreshVirtualHardwareSupport() {
        virtualHIDBridge.startIfInstalled()
    }

    nonisolated var isVirtualPointingReady: Bool {
        relativePointerOutput.isVirtualPointingReady
    }

    nonisolated func postRelativePointer(delta: SIMD2<Double>) -> Bool {
        relativePointerOutput.postRelativePointer(delta: delta)
    }

    nonisolated func postMouseButton(
        _ button: CGMouseButton,
        isDown: Bool,
        clickCount: Int = 1
    ) -> Bool {
        relativePointerOutput.postMouseButton(button, isDown: isDown, clickCount: clickCount)
    }

    nonisolated func postScroll(vertical: Int32, horizontal: Int32) -> Bool {
        relativePointerOutput.postScroll(vertical: vertical, horizontal: horizontal)
    }

    func postShortcutDown(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        if postVirtualShortcut(keyCode: keyCode, flags: flags, isDown: true) {
            return true
        }
        return postKeyboardEvent(
            eventType: UInt32(NX_KEYDOWN),
            keyCode: keyCode,
            flags: flags
        )
    }

    func postShortcutUp(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        if postVirtualShortcut(keyCode: keyCode, flags: flags, isDown: false) {
            return true
        }
        guard postKeyboardEvent(
            eventType: UInt32(NX_KEYUP),
            keyCode: keyCode,
            flags: flags
        ) else {
            return false
        }

        return postKeyboardEvent(
            eventType: UInt32(NX_FLAGSCHANGED),
            keyCode: 0,
            flags: []
        )
    }

    private func postVirtualShortcut(keyCode: UInt16, flags: CGEventFlags, isDown: Bool) -> Bool {
        if keyCode == 63 {
            return virtualHIDBridge.postFunction(isDown: isDown)
        }

        let modifierKey = Self.modifierKeyBits[keyCode]
        let usage = Self.hidUsageByMacKeyCode[keyCode]
        guard modifierKey != nil || usage != nil else {
            return false
        }

        guard isDown else {
            return virtualHIDBridge.postKeyboard(modifiers: 0, usage: 0)
        }

        var modifiers = Self.hidModifiers(for: flags)
        if let modifier = modifierKey {
            modifiers |= modifier
            return virtualHIDBridge.postKeyboard(modifiers: modifiers, usage: 0)
        }
        return virtualHIDBridge.postKeyboard(modifiers: modifiers, usage: usage ?? 0)
    }

    nonisolated static func hidModifiers(for flags: CGEventFlags) -> UInt8 {
        var result: UInt8 = 0
        if flags.contains(.maskControl) { result |= 0x01 }
        if flags.contains(.maskShift) { result |= 0x02 }
        if flags.contains(.maskAlternate) { result |= 0x04 }
        if flags.contains(.maskCommand) { result |= 0x08 }
        return result
    }

    nonisolated static let modifierKeyBits: [UInt16: UInt8] = [
        54: 0x80,
        55: 0x08,
        56: 0x02,
        58: 0x04,
        59: 0x01,
        60: 0x20,
        61: 0x40,
        62: 0x10,
    ]

    /// USB HID keyboard usages corresponding to macOS virtual key codes.
    nonisolated static let hidUsageByMacKeyCode: [UInt16: UInt16] = [
        0: 0x04, 1: 0x16, 2: 0x07, 3: 0x09, 4: 0x0b, 5: 0x0a,
        6: 0x1d, 7: 0x1b, 8: 0x06, 9: 0x19, 10: 0x64, 11: 0x05,
        12: 0x14, 13: 0x1a, 14: 0x08, 15: 0x15, 16: 0x1c, 17: 0x17,
        18: 0x1e, 19: 0x1f, 20: 0x20, 21: 0x21, 22: 0x23, 23: 0x22,
        24: 0x2e, 25: 0x26, 26: 0x24, 27: 0x2d, 28: 0x25, 29: 0x27,
        30: 0x30, 31: 0x12, 32: 0x18, 33: 0x2f, 34: 0x0c, 35: 0x13,
        36: 0x28, 37: 0x0f, 38: 0x0d, 39: 0x34, 40: 0x0e, 41: 0x33,
        42: 0x31, 43: 0x36, 44: 0x38, 45: 0x11, 46: 0x10, 47: 0x37,
        48: 0x2b, 49: 0x2c, 50: 0x35, 51: 0x2a, 53: 0x29,
        57: 0x39, 64: 0x6c, 65: 0x63, 67: 0x55, 69: 0x57, 71: 0x53,
        75: 0x54, 76: 0x58, 78: 0x56, 79: 0x6d, 80: 0x6e, 81: 0x67,
        82: 0x62, 83: 0x59, 84: 0x5a, 85: 0x5b, 86: 0x5c, 87: 0x5d,
        88: 0x5e, 89: 0x5f, 91: 0x60, 92: 0x61,
        96: 0x3e, 97: 0x3f, 98: 0x40, 99: 0x3c, 100: 0x41, 101: 0x42,
        103: 0x44, 105: 0x68, 106: 0x6b, 107: 0x69, 109: 0x43,
        111: 0x45, 113: 0x6a, 114: 0x49, 115: 0x4a, 116: 0x4b,
        117: 0x4c, 118: 0x3d, 119: 0x4d, 120: 0x3b, 121: 0x4e,
        122: 0x3a, 123: 0x50, 124: 0x4f, 125: 0x51, 126: 0x52,
    ]

    private func postKeyboardEvent(
        eventType: UInt32,
        keyCode: UInt16,
        flags: CGEventFlags
    ) -> Bool {
        var eventData = NXEventData()
        eventData.key.keyCode = keyCode
        eventData.key.repeat = 0

        return post(
            eventType: eventType,
            eventData: &eventData,
            includeGlobalFlags: true,
            eventFlags: UInt32(truncatingIfNeeded: flags.rawValue)
        )
    }

    private func post(
        eventType: UInt32,
        eventData: inout NXEventData,
        includeGlobalFlags: Bool,
        eventFlags: UInt32
    ) -> Bool {
        legacyPoster.post(
            eventType: eventType,
            eventData: &eventData,
            includeGlobalFlags: includeGlobalFlags,
            eventFlags: eventFlags
        )
    }
}
