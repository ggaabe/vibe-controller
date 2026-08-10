import CoreGraphics
import Foundation
import IOKit
import IOKit.hidsystem
import simd

/// Posts input through IOHIDSystem's HID-manager path. Unlike an absolute
/// Quartz cursor warp, these relative reports enter the pointing-device
/// pipeline that Universal Control observes at a display edge.
@MainActor
final class UniversalControlInputBridge {
    private(set) var initializationMessage: String

    private var connection: io_connect_t?
    private var pendingPointerDelta = SIMD2<Double>.zero

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
        initializationMessage = "Hardware-relative pointer ready for Universal Control."
    }

    deinit {
        if let connection {
            IOServiceClose(connection)
        }
    }

    var isAvailable: Bool {
        connection != nil
    }

    func postRelativePointer(delta: SIMD2<Double>) -> Bool {
        pendingPointerDelta += delta

        let dx = Int32(clamping: Int(pendingPointerDelta.x.rounded(.towardZero)))
        let dy = Int32(clamping: Int(pendingPointerDelta.y.rounded(.towardZero)))
        guard dx != 0 || dy != 0 else {
            return true
        }

        var eventData = NXEventData()
        eventData.mouseMove.dx = dx
        eventData.mouseMove.dy = dy

        guard post(
            eventType: UInt32(NX_MOUSEMOVED),
            eventData: &eventData,
            includeGlobalFlags: false,
            eventFlags: 0
        ) else {
            pendingPointerDelta = .zero
            return false
        }

        pendingPointerDelta -= SIMD2<Double>(Double(dx), Double(dy))
        return true
    }

    func postMouseButton(_ button: CGMouseButton, isDown: Bool, clickCount: Int = 1) -> Bool {
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

        return post(
            eventType: eventType,
            eventData: &eventData,
            includeGlobalFlags: false,
            eventFlags: 0
        )
    }

    func postScroll(vertical: Int32, horizontal: Int32) -> Bool {
        var eventData = NXEventData()
        eventData.scrollWheel.deltaAxis1 = Int16(clamping: Int(vertical))
        eventData.scrollWheel.deltaAxis2 = Int16(clamping: Int(horizontal))
        eventData.scrollWheel.fixedDeltaAxis1 = vertical.multipliedReportingOverflow(by: 65_536).partialValue
        eventData.scrollWheel.fixedDeltaAxis2 = horizontal.multipliedReportingOverflow(by: 65_536).partialValue
        eventData.scrollWheel.pointDeltaAxis1 = vertical
        eventData.scrollWheel.pointDeltaAxis2 = horizontal

        return post(
            eventType: UInt32(NX_SCROLLWHEELMOVED),
            eventData: &eventData,
            includeGlobalFlags: false,
            eventFlags: 0
        )
    }

    func postShortcutDown(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        postKeyboardEvent(
            eventType: UInt32(NX_KEYDOWN),
            keyCode: keyCode,
            flags: flags
        )
    }

    func postShortcutUp(keyCode: UInt16, flags: CGEventFlags) -> Bool {
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
        guard let connection else {
            return false
        }

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
