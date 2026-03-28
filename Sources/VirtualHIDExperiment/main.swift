import Foundation
import CoreGraphics
import Darwin

#if canImport(CoreHID)
import CoreHID
#endif

#if canImport(IOKit.hid)
import IOKit.hid
#endif

#if canImport(IOKit.hidsystem)
import IOKit.hidsystem
#endif

@main
struct VirtualHIDExperiment {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())

        if args.contains("--descriptor") {
            print("Boot mouse report descriptor (\(bootMouseDescriptor.count) bytes):")
            print(bootMouseDescriptor.map { String(format: "%02X", $0) }.joined(separator: " "))
            return
        }

        if args.contains("--status") {
            print(statusSummary)
            return
        }

        if args.contains("--create") || args.contains("--demo-motion") {
            await runVirtualMouseExperiment(
                demoMotion: args.contains("--demo-motion"),
                holdDuration: holdDuration(from: args)
            )
            return
        }

        if args.contains("--iokit-create") || args.contains("--iokit-demo-motion") {
            await runIOKitVirtualMouseExperiment(
                demoMotion: args.contains("--iokit-demo-motion"),
                holdDuration: holdDuration(from: args)
            )
            return
        }

        print("VirtualHIDExperiment")
        print("Usage:")
        print("  swift run VirtualHIDExperiment --status")
        print("  swift run VirtualHIDExperiment --descriptor")
        print("  swift run VirtualHIDExperiment --create [--hold seconds]")
        print("  swift run VirtualHIDExperiment --demo-motion [--hold seconds]")
        print("  swift run VirtualHIDExperiment --iokit-create [--hold seconds]")
        print("  swift run VirtualHIDExperiment --iokit-demo-motion [--hold seconds]")
    }

    static var statusSummary: String {
        #if canImport(CoreHID)
        if #available(macOS 15.0, *) {
            return """
            CoreHID is available in this SDK. The next experiment step is creating a HIDVirtualDevice-backed mouse
            with the boot descriptor and validating whether macOS treats it like a true pointing device.
            """
        } else {
            return "CoreHID is present, but HIDVirtualDevice APIs require macOS 15.0 or newer at runtime."
        }
        #else
        return "CoreHID is not available in this SDK, so the virtual HID route cannot be compiled here yet."
        #endif
    }

    static let bootMouseDescriptor: [UInt8] = [
        0x05, 0x01,
        0x09, 0x02,
        0xA1, 0x01,
        0x09, 0x01,
        0xA1, 0x00,
        0x05, 0x09,
        0x19, 0x01,
        0x29, 0x03,
        0x15, 0x00,
        0x25, 0x01,
        0x95, 0x03,
        0x75, 0x01,
        0x81, 0x02,
        0x95, 0x01,
        0x75, 0x05,
        0x81, 0x01,
        0x05, 0x01,
        0x09, 0x30,
        0x09, 0x31,
        0x09, 0x38,
        0x15, 0x81,
        0x25, 0x7F,
        0x75, 0x08,
        0x95, 0x03,
        0x81, 0x06,
        0xC0,
        0xC0,
    ]

    static func holdDuration(from args: [String]) -> TimeInterval {
        guard let index = args.firstIndex(of: "--hold"),
              args.indices.contains(index + 1),
              let parsed = Double(args[index + 1]) else {
            return 8
        }
        return max(parsed, 0)
    }

    static func runVirtualMouseExperiment(demoMotion: Bool, holdDuration: TimeInterval) async {
        #if canImport(CoreHID)
        guard #available(macOS 15.0, *) else {
            print("HIDVirtualDevice requires macOS 15.0 or newer at runtime.")
            return
        }

        let vendorID: UInt32 = 0x1209
        let productID: UInt32 = 0x0001
        let manufacturer = "Vibe Controller"
        let product = "Vibe Virtual Mouse"
        let uniqueID = "com.vibe-controller.virtual-mouse"

        let candidateProperties: [(String, HIDVirtualDevice.Properties)] = [
            (
                "minimal",
                HIDVirtualDevice.Properties(
                    descriptor: Data(bootMouseDescriptor),
                    vendorID: vendorID,
                    productID: nil,
                    transport: nil,
                    product: nil,
                    manufacturer: nil,
                    modelNumber: nil,
                    versionNumber: nil,
                    serialNumber: nil,
                    uniqueID: nil,
                    locationID: nil,
                    localizationCode: nil,
                    extraProperties: nil
                )
            ),
            (
                "vendor-product",
                HIDVirtualDevice.Properties(
                    descriptor: Data(bootMouseDescriptor),
                    vendorID: vendorID,
                    productID: productID,
                    transport: nil,
                    product: nil,
                    manufacturer: nil,
                    modelNumber: nil,
                    versionNumber: nil,
                    serialNumber: nil,
                    uniqueID: nil,
                    locationID: nil,
                    localizationCode: nil,
                    extraProperties: nil
                )
            ),
            (
                "named-virtual",
                HIDVirtualDevice.Properties(
                    descriptor: Data(bootMouseDescriptor),
                    vendorID: vendorID,
                    productID: productID,
                    transport: .virtual,
                    product: product,
                    manufacturer: manufacturer,
                    modelNumber: nil,
                    versionNumber: nil,
                    serialNumber: nil,
                    uniqueID: uniqueID,
                    locationID: nil,
                    localizationCode: nil,
                    extraProperties: nil
                )
            ),
        ]

        var selectedLabel: String?
        var device: HIDVirtualDevice?
        for (label, properties) in candidateProperties {
            if let candidate = HIDVirtualDevice(properties: properties) {
                selectedLabel = label
                device = candidate
                break
            }
        }

        guard let device else {
            let labels = candidateProperties.map { $0.0 }.joined(separator: ", ")
            print("Failed to create HIDVirtualDevice for every candidate: \(labels).")
            print("Falling back to IOHIDUserDevice.")
            await runIOKitVirtualMouseExperiment(demoMotion: demoMotion, holdDuration: holdDuration)
            return
        }

        let delegate = VirtualMouseDelegate()
        let manager = HIDDeviceManager()
        let criteria = HIDDeviceManager.DeviceMatchingCriteria(
            primaryUsage: .genericDesktop(.mouse),
            vendorID: vendorID,
            productID: productID
        )

        let monitorTask = Task {
            let stream = await manager.monitorNotifications(matchingCriteria: [criteria])
            do {
                for try await notification in stream {
                    switch notification {
                    case .deviceMatched(let reference):
                        if let client = HIDDeviceClient(deviceReference: reference) {
                            let manufacturer = await client.manufacturer ?? "?"
                            let product = await client.product ?? "?"
                            let transport = await client.transport
                            let usage = await client.primaryUsage
                            print("Matched virtual device: \(manufacturer) / \(product) transport=\(String(describing: transport)) usage=\(usage)")
                        } else {
                            print("Matched virtual device reference: \(reference)")
                        }
                    case .deviceRemoved(let reference):
                        print("Virtual device removed: \(reference)")
                    @unknown default:
                        print("Received unknown HID device notification: \(notification)")
                    }
                }
            } catch {
                print("Device monitor stopped with error: \(error)")
            }
        }

        await device.activate(delegate: delegate)
        print("Activated virtual mouse device with property set: \(selectedLabel ?? "unknown").")
        print("Holding device live for \(holdDuration)s.")

        try? await Task.sleep(nanoseconds: 300_000_000)

        if demoMotion {
            let start = CGEvent(source: nil)?.location ?? .zero
            print("Cursor before demo: \(format(point: start))")
            do {
                try await dispatchRelativeMove(device: device, dx: 24, dy: 0)
                try? await Task.sleep(nanoseconds: 60_000_000)
                try await dispatchRelativeMove(device: device, dx: 24, dy: 0)
                try? await Task.sleep(nanoseconds: 60_000_000)
                try await dispatchRelativeMove(device: device, dx: -24, dy: 0)
                try? await Task.sleep(nanoseconds: 60_000_000)
                try await dispatchRelativeMove(device: device, dx: -24, dy: 0)
                let end = CGEvent(source: nil)?.location ?? .zero
                print("Cursor after demo:  \(format(point: end))")
            } catch {
                print("Failed to dispatch demo report: \(error)")
            }
        }

        if holdDuration > 0 {
            try? await Task.sleep(nanoseconds: UInt64(holdDuration * 1_000_000_000))
        }

        monitorTask.cancel()
        #else
        print("CoreHID is not available in this SDK.")
        #endif
    }

    static func runIOKitVirtualMouseExperiment(demoMotion: Bool, holdDuration: TimeInterval) async {
        #if canImport(IOKit.hid) && canImport(IOKit.hidsystem)
        let vendorID: Int = 0x1209
        let productID: Int = 0x0001
        let properties: [String: Any] = [
            kIOHIDReportDescriptorKey: Data(bootMouseDescriptor),
            kIOHIDPrimaryUsagePageKey: 0x01,
            kIOHIDPrimaryUsageKey: 0x02,
            kIOHIDTransportKey: kIOHIDTransportVirtualValue,
            kIOHIDVendorIDKey: vendorID,
            kIOHIDProductIDKey: productID,
            kIOHIDProductKey: "Vibe Virtual Mouse",
            kIOHIDManufacturerKey: "Vibe Controller",
        ]

        guard let device = IOHIDUserDeviceCreateWithProperties(kCFAllocatorDefault, properties as CFDictionary, 0) else {
            print("IOHIDUserDeviceCreateWithProperties returned nil.")
            return
        }

        IOHIDUserDeviceRegisterGetReportBlock(device) { _, _, _, reportLength in
            reportLength.pointee = 0
            return kIOReturnUnsupported
        }
        IOHIDUserDeviceRegisterSetReportBlock(device) { _, _, _, _ in
            kIOReturnUnsupported
        }

        let queue = DispatchQueue(label: "com.vibe-controller.virtual-hid.iokit")
        IOHIDUserDeviceSetDispatchQueue(device, queue)
        IOHIDUserDeviceActivate(device)
        print("Activated IOHIDUserDevice virtual mouse.")
        print("Holding device live for \(holdDuration)s.")

        if demoMotion {
            let start = CGEvent(source: nil)?.location ?? .zero
            print("Cursor before IOKit demo: \(format(point: start))")
            let reports: [[UInt8]] = [
                [0, UInt8(bitPattern: 24), 0, 0],
                [0, UInt8(bitPattern: 24), 0, 0],
                [0, UInt8(bitPattern: Int8(-24)), 0, 0],
                [0, UInt8(bitPattern: Int8(-24)), 0, 0],
            ]

            for report in reports {
                let result = report.withUnsafeBufferPointer { buffer in
                    IOHIDUserDeviceHandleReportWithTimeStamp(
                        device,
                        mach_absolute_time(),
                        buffer.baseAddress!,
                        buffer.count
                    )
                }
                print("IOKit report dispatch result: \(formatIOReturn(result))")
                try? await Task.sleep(nanoseconds: 60_000_000)
            }

            let end = CGEvent(source: nil)?.location ?? .zero
            print("Cursor after IOKit demo:  \(format(point: end))")
        }

        if holdDuration > 0 {
            try? await Task.sleep(nanoseconds: UInt64(holdDuration * 1_000_000_000))
        }

        IOHIDUserDeviceCancel(device)
        #else
        print("IOHIDUserDevice is not available in this SDK.")
        #endif
    }

    #if canImport(CoreHID)
    @available(macOS 15.0, *)
    static func dispatchRelativeMove(device: HIDVirtualDevice, dx: Int8, dy: Int8, wheel: Int8 = 0, buttons: UInt8 = 0) async throws {
        let report = Data([
            buttons,
            UInt8(bitPattern: dx),
            UInt8(bitPattern: dy),
            UInt8(bitPattern: wheel),
        ])
        try await device.dispatchInputReport(data: report, timestamp: SuspendingClock().now)
    }
    #endif

    static func format(point: CGPoint) -> String {
        String(format: "(%.1f, %.1f)", point.x, point.y)
    }

    static func formatIOReturn(_ value: IOReturn) -> String {
        String(format: "0x%08x", value)
    }
}

#if canImport(CoreHID)
@available(macOS 15.0, *)
private actor VirtualMouseDelegate: HIDVirtualDeviceDelegate {
    func hidVirtualDevice(_ device: HIDVirtualDevice, receivedSetReportRequestOfType type: HIDReportType, id: HIDReportID?, data: Data) async throws {}

    func hidVirtualDevice(_ device: HIDVirtualDevice, receivedGetReportRequestOfType type: HIDReportType, id: HIDReportID?, maxSize: Int) async throws -> Data {
        Data()
    }
}
#endif
