import Foundation
@preconcurrency import IOKit.hid

protocol USBHapticsTransport: AnyObject {
    func play(_ pulse: ControllerVibration.Pulse, locality: ControllerVibration.Locality, strength: Float) throws
    func stop() throws
}

/// Native GIP motor command. Hardware duration is finite even if the process exits.
enum XboxUSBRumbleReport {
    static let hidReportID = 1

    static func make(left: Double, right: Double, duration: TimeInterval, sequence: UInt8) -> [UInt8] {
        func magnitude(_ value: Double) -> UInt8 {
            UInt8((min(1, max(0, value.isFinite ? value : 0)) * 100).rounded())
        }
        let left = magnitude(left)
        let right = magnitude(right)
        let seconds = duration.isFinite ? min(1, max(0, duration)) : 0
        let ticks = UInt8(ceil(seconds * 100)) // 10 ms per tick, no repeat.
        guard ticks > 0, left > 0 || right > 0 else {
            return [0x09, 0, sequence, 0x09, 0, 0x0f, 0, 0, 0, 0, 0, 0, 0]
        }
        return [0x09, 0, sequence, 0x09, 0, 0x0f, 0, 0, left, right, ticks, 0, 0]
    }
}

/// Queue-confined, shared access to Apple's existing Xbox USB output pipe.
/// No USB capture, driver detachment, administrator access, or input reads.
/// Apple's XboxWirelessGamepad accepts HID report ID 1 and forwards the 13-byte
/// buffer as GIP. The command byte in that buffer remains 0x09, not HID ID 1.
final class XboxUSBHapticsTransport: USBHapticsTransport {
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private var sequence: UInt8 = 0
    private var isPlaying = false

    private init(manager: IOHIDManager, device: IOHIDDevice) {
        self.manager = manager
        self.device = device
    }

    static func openIfAvailable() -> XboxUSBHapticsTransport? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x045e, kIOHIDProductIDKey: 0x0b12,
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad,
        ] as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []).filter {
            (IOHIDDeviceGetProperty($0, kIOHIDTransportKey as CFString) as? String) == "USB" &&
            (IOHIDDeviceGetProperty($0, "GCSyntheticDevice" as CFString) as? NSNumber)?.boolValue != true
        }
        guard devices.count == 1, let device = devices.first else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }
        return XboxUSBHapticsTransport(manager: manager, device: device)
    }

    deinit {
        try? stop()
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func play(_ pulse: ControllerVibration.Pulse, locality: ControllerVibration.Locality, strength: Float) throws {
        let intensity = Double(pulse.intensity * strength)
        try send(left: locality == .right ? 0 : intensity,
                 right: locality == .left ? 0 : intensity, duration: pulse.duration)
        isPlaying = true
    }

    func stop() throws {
        guard isPlaying else { return }
        isPlaying = false
        try send(left: 0, right: 0, duration: 0)
    }

    private func send(left: Double, right: Double, duration: TimeInterval) throws {
        sequence &+= 1
        if sequence == 0 { sequence = 1 }
        let packet = XboxUSBRumbleReport.make(left: left, right: right, duration: duration, sequence: sequence)
        let result = packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, XboxUSBRumbleReport.hidReportID,
                                $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else {
            throw NSError(domain: "VibeController.USBVibration", code: Int(result), userInfo: [
                NSLocalizedDescriptionKey: String(format: "USB vibration write failed (0x%08x). Reconnect the controller and retry.", result),
            ])
        }
    }
}
