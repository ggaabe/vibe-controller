import Foundation
import GameController
import CoreHaptics
import IOKit.hid

/// Explicit, finite hardware test. Never emits keyboard or mouse input.
func runHapticsProbe() {
    GCController.shouldMonitorBackgroundEvents = true
    RunLoop.main.run(until: Date().addingTimeInterval(3))
    guard let controller = GCController.controllers().first(where: { $0.extendedGamepad != nil }),
          let haptics = controller.haptics else {
        print("No controller haptics exposed.")
        return
    }
    print("Controller: \(controller.vendorName ?? "Unknown")")
    print("Localities: \(haptics.supportedLocalities.map(\.rawValue).sorted())")
    for locality in [GCHapticsLocality.default, .handles] {
        guard haptics.supportedLocalities.contains(locality),
              let engine = haptics.createEngine(withLocality: locality) else { continue }
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = false
        do {
            let start = ProcessInfo.processInfo.systemUptime
            try engine.start()
            print("\(locality.rawValue): engine started in \(ProcessInfo.processInfo.systemUptime - start)s; muted=\(engine.isMutedForHaptics)")
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
            ], relativeTime: 0, duration: 0.65)
            let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
            print("PLAY \(locality.rawValue): 650ms at 80 percent")
            try player.start(atTime: CHHapticTimeImmediate)
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            try player.stop(atTime: CHHapticTimeImmediate)
            engine.stop(completionHandler: nil)
            print("STOP \(locality.rawValue)")
        } catch {
            engine.stop(completionHandler: nil)
            print("HAPTIC ERROR: \(error)")
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    }
    print("Haptic test finished. API success alone does not prove physical vibration.")
}

/// Tests the existing Apple USB driver's output pipe without detaching it.
/// XboxWirelessGamepad accepts HID report ID 1 with a 13-byte output buffer;
/// the buffer itself is the native GIP rumble command (command byte 0x09).
func runUSBHapticsProbe() {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, [
        kIOHIDVendorIDKey: 0x045e, kIOHIDProductIDKey: 0x0b12,
        kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
        kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad,
    ] as CFDictionary)
    let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    print(String(format: "USB rumble manager open: 0x%08x", opened))
    defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
    guard opened == kIOReturnSuccess,
          let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
          let device = devices.first(where: {
              (IOHIDDeviceGetProperty($0, kIOHIDTransportKey as CFString) as? String) == "USB" &&
              (IOHIDDeviceGetProperty($0, "GCSyntheticDevice" as CFString) as? NSNumber)?.boolValue != true
          }) else { print("No physical Xbox Series USB HID device."); return }
    func send(_ magnitude: UInt8, sequence: UInt8) -> IOReturn {
        let packet: [UInt8] = [0x09, 0, sequence, 0x09, 0, 0x0f, 0, 0,
                               magnitude, magnitude, magnitude == 0 ? 0 : 50, 0, 0]
        return packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 1, $0.baseAddress!, $0.count)
        }
    }
    defer { print(String(format: "USB rumble stop: 0x%08x", send(0, sequence: 2))) }
    print("PLAY direct USB: 500ms at 80 percent, followed by explicit stop")
    let result = send(80, sequence: 1)
    print(String(format: "USB rumble write: 0x%08x", result))
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))
}
