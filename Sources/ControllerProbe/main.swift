import Foundation
import GameController
import IOKit.hid
import Darwin

setbuf(stdout, nil)

if CommandLine.arguments.contains("--raw-hid") {
    runRawHIDProbe()
    exit(0)
}

GCController.shouldMonitorBackgroundEvents = true

let center = NotificationCenter.default
let connectToken = center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { note in
    if let controller = note.object as? GCController {
        print("Controller connected: \(controller.vendorName ?? "Unknown")")
    }
}

defer {
    center.removeObserver(connectToken)
}

print("Waiting up to 5 seconds for Game Controller discovery...")
RunLoop.main.run(until: Date().addingTimeInterval(5))

let controllers = GCController.controllers()
print("Detected controllers: \(controllers.count)")
for controller in controllers {
    let batterySummary: String
    if let battery = controller.battery {
        batterySummary = String(format: "%.0f%% %@", battery.batteryLevel * 100, battery.batteryState.vibeDescription)
    } else {
        batterySummary = "n/a"
    }
    print("- \(controller.vendorName ?? "Unknown") | battery: \(batterySummary)")
}

guard let controller = GCController.current ?? controllers.first(where: { $0.extendedGamepad != nil }),
      let gamepad = controller.extendedGamepad else {
    print("No extended gamepad available after waiting.")
    exit(0)
}

print("Listening to \(controller.vendorName ?? "Unknown") for 10 seconds. Move sticks or press buttons.")

gamepad.valueChangedHandler = { _, element in
    let name = element.localizedName ?? String(describing: type(of: element))
    let left = gamepad.leftThumbstick
    let right = gamepad.rightThumbstick
    let pressed = [
        ("A", gamepad.buttonA.isPressed),
        ("B", gamepad.buttonB.isPressed),
        ("X", gamepad.buttonX.isPressed),
        ("Y", gamepad.buttonY.isPressed),
        ("LB", gamepad.leftShoulder.isPressed),
        ("RB", gamepad.rightShoulder.isPressed),
        ("LT", gamepad.leftTrigger.isPressed),
        ("RT", gamepad.rightTrigger.isPressed),
        ("View", gamepad.buttonOptions?.isPressed ?? false),
        ("Menu", gamepad.buttonMenu.isPressed),
    ]
    .filter(\.1)
    .map(\.0)
    .joined(separator: ", ")

    print(
        String(
            format: "%@ | left:(%.2f, %.2f) right:(%.2f, %.2f) pressed:[%@]",
            name,
            left.xAxis.value,
            left.yAxis.value,
            right.xAxis.value,
            right.yAxis.value,
            pressed
        )
    )
}

RunLoop.main.run(until: Date().addingTimeInterval(10))

private func runRawHIDProbe() {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching: [String: Any] = [
        kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
        kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad,
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, device in
        let vendor = integerProperty(kIOHIDVendorIDKey, device: device)
        let productID = integerProperty(kIOHIDProductIDKey, device: device)
        let product = stringProperty(kIOHIDProductKey, device: device) ?? "Unknown"
        let synthetic = IOHIDDeviceGetProperty(device, "GCSyntheticDevice" as CFString)
        print("Matched HID gamepad: \(product) vendor=\(vendor) product=\(productID) synthetic=\(String(describing: synthetic))")
        let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        IOHIDDeviceRegisterInputReportCallback(
            device,
            reportBuffer,
            64,
            { _, result, _, reportType, reportID, report, reportLength in
                let hex = (0..<reportLength).map { String(format: "%02x", report[$0]) }.joined(separator: " ")
                print("Raw HID report type=\(reportType.rawValue) id=\(reportID) result=\(result) bytes=[\(hex)]")
            },
            nil
        )

        if let elements = IOHIDDeviceCopyMatchingElements(
            device,
            nil,
            IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement] {
            for element in elements where IOHIDElementGetReportID(element) == 0x20 {
                let valuePointer = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)
                defer { valuePointer.deallocate() }
                let valueResult = IOHIDDeviceGetValue(
                    device,
                    element,
                    valuePointer
                )
                guard valueResult == kIOReturnSuccess else { continue }
                let value = valuePointer.pointee.takeUnretainedValue()
                let length = IOHIDValueGetLength(value)
                let bytes = IOHIDValueGetBytePtr(value)
                let hex = (0..<length).map { String(format: "%02x", bytes[$0]) }.joined(separator: " ")
                print("Current report-32 element value bytes=[\(hex)]")
            }
        }
    }, nil)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    print(String(format: "Raw HID manager open: 0x%08x", result))
    print("Listening to gamepad HID values for 15 seconds.")
    RunLoop.main.run(until: Date().addingTimeInterval(15))
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
}

private func integerProperty(_ key: String, device: IOHIDDevice) -> Int {
    (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
}

private func stringProperty(_ key: String, device: IOHIDDevice) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString) as? String
}

private extension GCDeviceBattery.State {
    var vibeDescription: String {
        switch self {
        case .charging:
            return "charging"
        case .discharging:
            return "discharging"
        case .full:
            return "full"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }
}
