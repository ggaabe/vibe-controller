import Foundation
@preconcurrency import IOKit.hid

struct XboxUSBInputState: Equatable, Sendable {
    var pressedControls: Set<ControllerControlID> = []
    var analogValues: [ControllerControlID: Double] = [:]
    var leftStick = StickSnapshot()
    var rightStick = StickSnapshot()
}

enum XboxUSBReportParser {
    static func parse(
        reportID: Int,
        bytes: [UInt8],
        previous: XboxUSBInputState = XboxUSBInputState()
    ) -> XboxUSBInputState? {
        let includesReportID = bytes.first == UInt8(truncatingIfNeeded: reportID)
        let payloadStart = includesReportID ? 0 : -1

        switch reportID {
        case 0x20:
            return parseStandardInput(bytes, payloadStart: payloadStart, previous: previous)
        case 0x07:
            return parseGuideButton(bytes, payloadStart: payloadStart, previous: previous)
        default:
            return nil
        }
    }

    private static func parseStandardInput(
        _ bytes: [UInt8],
        payloadStart: Int,
        previous: XboxUSBInputState
    ) -> XboxUSBInputState? {
        guard let buttonByte1 = byte(atProtocolOffset: 4, in: bytes, payloadStart: payloadStart),
              let buttonByte2 = byte(atProtocolOffset: 5, in: bytes, payloadStart: payloadStart),
              let leftTrigger = unsigned16(atProtocolOffset: 6, in: bytes, payloadStart: payloadStart),
              let rightTrigger = unsigned16(atProtocolOffset: 8, in: bytes, payloadStart: payloadStart),
              let leftX = signed16(atProtocolOffset: 10, in: bytes, payloadStart: payloadStart),
              let leftY = signed16(atProtocolOffset: 12, in: bytes, payloadStart: payloadStart),
              let rightX = signed16(atProtocolOffset: 14, in: bytes, payloadStart: payloadStart),
              let rightY = signed16(atProtocolOffset: 16, in: bytes, payloadStart: payloadStart) else {
            return nil
        }

        var pressed = Set<ControllerControlID>()
        var values: [ControllerControlID: Double] = [:]

        func capture(_ control: ControllerControlID, byte: UInt8, mask: UInt8) {
            let isPressed = (byte & mask) != 0
            values[control] = isPressed ? 1 : 0
            if isPressed {
                pressed.insert(control)
            }
        }

        capture(.menu, byte: buttonByte1, mask: 0x04)
        capture(.options, byte: buttonByte1, mask: 0x08)
        capture(.buttonSouth, byte: buttonByte1, mask: 0x10)
        capture(.buttonEast, byte: buttonByte1, mask: 0x20)
        capture(.buttonWest, byte: buttonByte1, mask: 0x40)
        capture(.buttonNorth, byte: buttonByte1, mask: 0x80)

        capture(.dpadUp, byte: buttonByte2, mask: 0x01)
        capture(.dpadDown, byte: buttonByte2, mask: 0x02)
        capture(.dpadLeft, byte: buttonByte2, mask: 0x04)
        capture(.dpadRight, byte: buttonByte2, mask: 0x08)
        capture(.leftShoulder, byte: buttonByte2, mask: 0x10)
        capture(.rightShoulder, byte: buttonByte2, mask: 0x20)
        capture(.leftThumbstickButton, byte: buttonByte2, mask: 0x40)
        capture(.rightThumbstickButton, byte: buttonByte2, mask: 0x80)

        let normalizedLeftTrigger = min(1, Double(leftTrigger) / 1_023)
        let normalizedRightTrigger = min(1, Double(rightTrigger) / 1_023)
        values[.leftTrigger] = normalizedLeftTrigger
        values[.rightTrigger] = normalizedRightTrigger
        if normalizedLeftTrigger >= 0.18 { pressed.insert(.leftTrigger) }
        if normalizedRightTrigger >= 0.18 { pressed.insert(.rightTrigger) }

        if previous.pressedControls.contains(.home) {
            pressed.insert(.home)
            values[.home] = 1
        } else {
            values[.home] = 0
        }

        let leftStick = StickSnapshot(
            x: normalizedAxis(leftX),
            y: normalizedAxis(leftY),
            pressed: pressed.contains(.leftThumbstickButton)
        )
        let rightStick = StickSnapshot(
            x: normalizedAxis(rightX),
            y: normalizedAxis(rightY),
            pressed: pressed.contains(.rightThumbstickButton)
        )
        values[.leftThumbstick] = min(1, hypot(leftStick.x, leftStick.y))
        values[.rightThumbstick] = min(1, hypot(rightStick.x, rightStick.y))

        return XboxUSBInputState(
            pressedControls: pressed,
            analogValues: values,
            leftStick: leftStick,
            rightStick: rightStick
        )
    }

    private static func parseGuideButton(
        _ bytes: [UInt8],
        payloadStart: Int,
        previous: XboxUSBInputState
    ) -> XboxUSBInputState? {
        guard let guideByte = byte(atProtocolOffset: 4, in: bytes, payloadStart: payloadStart) else {
            return nil
        }

        var state = previous
        if (guideByte & 0x01) != 0 {
            state.pressedControls.insert(.home)
            state.analogValues[.home] = 1
        } else {
            state.pressedControls.remove(.home)
            state.analogValues[.home] = 0
        }
        return state
    }

    private static func byte(
        atProtocolOffset offset: Int,
        in bytes: [UInt8],
        payloadStart: Int
    ) -> UInt8? {
        let index = offset + payloadStart
        guard bytes.indices.contains(index) else { return nil }
        return bytes[index]
    }

    private static func unsigned16(
        atProtocolOffset offset: Int,
        in bytes: [UInt8],
        payloadStart: Int
    ) -> UInt16? {
        guard let low = byte(atProtocolOffset: offset, in: bytes, payloadStart: payloadStart),
              let high = byte(atProtocolOffset: offset + 1, in: bytes, payloadStart: payloadStart) else {
            return nil
        }
        return UInt16(low) | (UInt16(high) << 8)
    }

    private static func signed16(
        atProtocolOffset offset: Int,
        in bytes: [UInt8],
        payloadStart: Int
    ) -> Int16? {
        unsigned16(atProtocolOffset: offset, in: bytes, payloadStart: payloadStart)
            .map(Int16.init(bitPattern:))
    }

    private static func normalizedAxis(_ value: Int16) -> Double {
        let normalized = value >= 0
            ? Double(value) / Double(Int16.max)
            : Double(value) / Double(-Int(Int16.min))
        return min(1, max(-1, normalized))
    }
}

/// Reads the physical Xbox controller's USB HID reports directly. macOS's
/// higher-level GameController state can pause when Universal Control moves
/// pointer ownership to another Mac; the source Mac's USB HID stream does not.
final class XboxUSBControllerReader: @unchecked Sendable {
    var onConnectionChanged: (@Sendable (Bool, String?) -> Void)?
    var onInput: (@Sendable (XboxUSBInputState) -> Void)?

    private let queue: DispatchQueue
    private let manager: IOHIDManager
    private var matchedDeviceIDs = Set<ObjectIdentifier>()
    private var latestState = XboxUSBInputState()
    private var hasReceivedStandardInput = false
    private var isStarted = false

    init(queue: DispatchQueue) {
        self.queue = queue
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad,
            kIOHIDVendorIDKey: 0x045e,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let reader = Unmanaged<XboxUSBControllerReader>.fromOpaque(context).takeUnretainedValue()
            reader.deviceMatched(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let reader = Unmanaged<XboxUSBControllerReader>.fromOpaque(context).takeUnretainedValue()
            reader.deviceRemoved(device)
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { context, result, sender, _, reportID, report, reportLength in
            guard result == kIOReturnSuccess, let context, let sender else { return }
            let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
            let reader = Unmanaged<XboxUSBControllerReader>.fromOpaque(context).takeUnretainedValue()
            let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            reader.receivedReport(from: device, reportID: Int(reportID), bytes: bytes)
        }, context)

        IOHIDManagerSetDispatchQueue(manager, queue)
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isStarted else { return }
            self.isStarted = true
            _ = IOHIDManagerOpen(self.manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerActivate(self.manager)
        }
    }

    deinit {
        IOHIDManagerCancel(manager)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func deviceMatched(_ device: IOHIDDevice) {
        guard !isSynthetic(device) else { return }

        let deviceID = ObjectIdentifier(device)
        guard matchedDeviceIDs.insert(deviceID).inserted else { return }

        let name = stringProperty(kIOHIDProductKey, device: device) ?? "Xbox Controller"
        onConnectionChanged?(true, name)
        readCurrentStandardInput(from: device)
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let deviceID = ObjectIdentifier(device)
        guard matchedDeviceIDs.remove(deviceID) != nil else { return }
        hasReceivedStandardInput = false
        latestState = XboxUSBInputState()
        if matchedDeviceIDs.isEmpty {
            onConnectionChanged?(false, nil)
        }
    }

    private func receivedReport(
        from device: IOHIDDevice,
        reportID: Int,
        bytes: [UInt8]
    ) {
        guard matchedDeviceIDs.contains(ObjectIdentifier(device)) else { return }
        guard let parsed = XboxUSBReportParser.parse(
            reportID: reportID,
            bytes: bytes,
            previous: latestState
        ) else {
            return
        }

        let receivedFirstStandardReport = reportID == 0x20 && !hasReceivedStandardInput
        if reportID == 0x20 {
            hasReceivedStandardInput = true
        }
        guard hasReceivedStandardInput else { return }

        guard receivedFirstStandardReport || inputChangedMeaningfully(from: latestState, to: parsed) else {
            return
        }
        latestState = parsed
        onInput?(parsed)
    }

    private func readCurrentStandardInput(from device: IOHIDDevice) {
        guard let elements = IOHIDDeviceCopyMatchingElements(
            device,
            nil,
            IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement] else {
            return
        }

        for element in elements where IOHIDElementGetReportID(element) == 0x20 {
            let valuePointer = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)
            defer { valuePointer.deallocate() }
            guard IOHIDDeviceGetValue(device, element, valuePointer) == kIOReturnSuccess else {
                continue
            }

            let value = valuePointer.pointee.takeUnretainedValue()
            let length = IOHIDValueGetLength(value)
            guard length >= 18 else { continue }
            let bytes = Array(
                UnsafeBufferPointer(start: IOHIDValueGetBytePtr(value), count: length)
            )
            receivedReport(from: device, reportID: 0x20, bytes: bytes)
            return
        }
    }

    private func inputChangedMeaningfully(
        from previous: XboxUSBInputState,
        to current: XboxUSBInputState
    ) -> Bool {
        guard previous.pressedControls == current.pressedControls else { return true }

        let tolerance = 0.0015
        let stickValues = [
            (previous.leftStick.x, current.leftStick.x),
            (previous.leftStick.y, current.leftStick.y),
            (previous.rightStick.x, current.rightStick.x),
            (previous.rightStick.y, current.rightStick.y),
            (previous.analogValues[.leftTrigger] ?? 0, current.analogValues[.leftTrigger] ?? 0),
            (previous.analogValues[.rightTrigger] ?? 0, current.analogValues[.rightTrigger] ?? 0),
        ]
        return stickValues.contains { abs($0.0 - $0.1) >= tolerance }
    }

    private func isSynthetic(_ device: IOHIDDevice) -> Bool {
        if let value = IOHIDDeviceGetProperty(device, "GCSyntheticDevice" as CFString) as? NSNumber {
            return value.boolValue
        }
        return false
    }

    private func stringProperty(_ key: String, device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }
}
