import Foundation

/// Native wired Xbox 360 packets (Microsoft 045e:028e), not Xbox One GIP.
/// Layout reference: SDL's HIDAPI Xbox 360 driver and Linux xpad's
/// xpad360_process_packet. No third-party driver or exclusive USB capture.
enum Xbox360USBReportParser {
    static func parse(reportID: Int, bytes: [UInt8]) -> XboxUSBInputState? {
        guard reportID == 0 else { return nil }

        // Report 0 has a 20-byte packet, beginning with type 0 and length 20.
        // Accept IOKit's report-ID-stripped form only at its exact length;
        // never guess offsets from button/axis data or accept status packets.
        let start: Int
        if bytes.count == 20, bytes[0] == 0, bytes[1] == 20 {
            start = 0
        } else if bytes.count == 19, bytes[0] == 20 {
            start = -1
        } else {
            return nil
        }

        var pressed = Set<ControllerControlID>()
        var values: [ControllerControlID: Double] = [:]
        func capture(_ control: ControllerControlID, offset: Int, mask: UInt8) {
            let isPressed = bytes[offset + start] & mask != 0
            values[control] = isPressed ? 1 : 0
            if isPressed { pressed.insert(control) }
        }

        capture(.dpadUp, offset: 2, mask: 0x01)
        capture(.dpadDown, offset: 2, mask: 0x02)
        capture(.dpadLeft, offset: 2, mask: 0x04)
        capture(.dpadRight, offset: 2, mask: 0x08)
        capture(.menu, offset: 2, mask: 0x10) // Start
        capture(.options, offset: 2, mask: 0x20) // Back
        capture(.leftThumbstickButton, offset: 2, mask: 0x40)
        capture(.rightThumbstickButton, offset: 2, mask: 0x80)
        capture(.leftShoulder, offset: 3, mask: 0x01)
        capture(.rightShoulder, offset: 3, mask: 0x02)
        capture(.home, offset: 3, mask: 0x04) // Guide is in every input packet.
        capture(.buttonSouth, offset: 3, mask: 0x10)
        capture(.buttonEast, offset: 3, mask: 0x20)
        capture(.buttonWest, offset: 3, mask: 0x40)
        capture(.buttonNorth, offset: 3, mask: 0x80)

        for (control, offset) in [(ControllerControlID.leftTrigger, 4), (.rightTrigger, 5)] {
            let value = Double(bytes[offset + start]) / 255
            values[control] = value
            if value >= 0.18 { pressed.insert(control) }
        }

        func axis(_ offset: Int) -> Double {
            let bits = UInt16(bytes[offset + start]) | UInt16(bytes[offset + start + 1]) << 8
            let value = Int16(bitPattern: bits)
            // Like GameController/GIP, positive Y means up, not screen-down.
            return Double(value) / (value >= 0 ? 32_767 : 32_768)
        }
        let left = StickSnapshot(
            x: axis(6), y: axis(8), pressed: pressed.contains(.leftThumbstickButton))
        let right = StickSnapshot(
            x: axis(10), y: axis(12), pressed: pressed.contains(.rightThumbstickButton))
        values[.leftThumbstick] = min(1, hypot(left.x, left.y))
        values[.rightThumbstick] = min(1, hypot(right.x, right.y))

        return XboxUSBInputState(
            pressedControls: pressed, analogValues: values, leftStick: left, rightStick: right)
    }
}
