import Foundation
import CoreGraphics
import Darwin

#if canImport(CoreHID)
import CoreHID
#endif

private final class PrivateHIDEventSystem {
    private typealias CreateClient = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    private typealias CreateMouseEvent = @convention(c) (
        CFAllocator?,
        UInt64,
        Double,
        Double,
        Double,
        UInt32,
        UInt32
    ) -> UnsafeMutableRawPointer?
    private typealias DispatchEvent = @convention(c) (
        UnsafeMutableRawPointer,
        UnsafeMutableRawPointer
    ) -> Void

    enum ExperimentError: LocalizedError {
        case frameworkUnavailable(String)
        case symbolUnavailable(String)
        case clientCreationFailed
        case eventCreationFailed

        var errorDescription: String? {
            switch self {
            case .frameworkUnavailable(let message):
                "Could not open IOKit: \(message)"
            case .symbolUnavailable(let name):
                "IOKit does not export \(name) on this macOS build."
            case .clientCreationFailed:
                "IOHIDEventSystemClientCreate returned nil."
            case .eventCreationFailed:
                "IOHIDEventCreateMouseEvent returned nil."
            }
        }
    }

    private let frameworkHandle: UnsafeMutableRawPointer
    private let client: UnsafeMutableRawPointer
    private let createMouseEvent: CreateMouseEvent
    private let dispatchEvent: DispatchEvent

    init() throws {
        let path = "/System/Library/Frameworks/IOKit.framework/IOKit"
        guard let frameworkHandle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw ExperimentError.frameworkUnavailable(String(cString: dlerror()))
        }

        do {
            let createClient: CreateClient = try Self.loadSymbol(
                "IOHIDEventSystemClientCreate",
                from: frameworkHandle
            )
            let createMouseEvent: CreateMouseEvent = try Self.loadSymbol(
                "IOHIDEventCreateMouseEvent",
                from: frameworkHandle
            )
            let dispatchEvent: DispatchEvent = try Self.loadSymbol(
                "IOHIDEventSystemClientDispatchEvent",
                from: frameworkHandle
            )
            guard let client = createClient(kCFAllocatorDefault) else {
                throw ExperimentError.clientCreationFailed
            }

            self.frameworkHandle = frameworkHandle
            self.client = client
            self.createMouseEvent = createMouseEvent
            self.dispatchEvent = dispatchEvent
        } catch {
            dlclose(frameworkHandle)
            throw error
        }
    }

    deinit {
        Unmanaged<AnyObject>.fromOpaque(client).release()
        dlclose(frameworkHandle)
    }

    func dispatchRelativeMouse(dx: Double, dy: Double, buttonMask: UInt32 = 0) throws {
        // A zero options value leaves kIOHIDEventOptionIsAbsolute clear, which
        // makes the mouse event relative at the HID event-system layer.
        guard let event = createMouseEvent(
            kCFAllocatorDefault,
            mach_absolute_time(),
            dx,
            dy,
            0,
            buttonMask,
            0
        ) else {
            throw ExperimentError.eventCreationFailed
        }

        dispatchEvent(client, event)
        Unmanaged<AnyObject>.fromOpaque(event).release()
    }

    private static func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer) throws -> T {
        guard let symbol = dlsym(handle, name) else {
            throw ExperimentError.symbolUnavailable(name)
        }
        return unsafeBitCast(symbol, to: T.self)
    }
}

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

        if args.contains("--event-system-demo-motion") || args.contains("--event-system-move") {
            runEventSystemMouseExperiment(
                demoMotion: args.contains("--event-system-demo-motion"),
                dx: numericArgument("--dx", in: args) ?? 12,
                dy: numericArgument("--dy", in: args) ?? 0,
                repeatCount: max(Int(numericArgument("--repeat", in: args) ?? 1), 1),
                interval: max(numericArgument("--interval", in: args) ?? 0.008, 0)
            )
            return
        }

        if args.contains("--iohid-post-move") {
            runLegacyIOHIDPostEventExperiment(
                dx: numericArgument("--dx", in: args) ?? 12,
                dy: numericArgument("--dy", in: args) ?? 0,
                repeatCount: max(Int(numericArgument("--repeat", in: args) ?? 1), 1),
                interval: max(numericArgument("--interval", in: args) ?? 0.008, 0),
                postAsHIDManagerEvent: args.contains("--hid-manager-event")
            )
            return
        }

        if args.contains("--iohid-post-click") {
            runLegacyIOHIDClickExperiment(
                buttonName: stringArgument("--button", in: args) ?? "left",
                clickCount: max(Int(numericArgument("--click-count", in: args) ?? 1), 1),
                phase: stringArgument("--phase", in: args) ?? "click",
                holdDuration: max(numericArgument("--hold", in: args) ?? 0, 0)
            )
            return
        }

        if args.contains("--iohid-post-key") {
            runLegacyIOHIDKeyExperiment(
                keyCode: UInt16(clamping: Int(numericArgument("--keycode", in: args) ?? 0)),
                flags: UInt32(clamping: Int(numericArgument("--flags", in: args) ?? 0))
            )
            return
        }

        if args.contains("--iohid-post-scroll") {
            runLegacyIOHIDScrollExperiment(
                vertical: Int32(clamping: Int(numericArgument("--vertical", in: args) ?? 0)),
                horizontal: Int32(clamping: Int(numericArgument("--horizontal", in: args) ?? 0)),
                repeatCount: max(Int(numericArgument("--repeat", in: args) ?? 1), 1)
            )
            return
        }

        if args.contains("--iohid-drag-move") {
            runLegacyIOHIDDragExperiment(
                dx: Int32(clamping: Int(numericArgument("--dx", in: args) ?? 10)),
                dy: Int32(clamping: Int(numericArgument("--dy", in: args) ?? 0)),
                repeatCount: max(Int(numericArgument("--repeat", in: args) ?? 1), 1),
                interval: max(numericArgument("--interval", in: args) ?? 0.008, 0)
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
        print("  swift run VirtualHIDExperiment --event-system-demo-motion")
        print("  swift run VirtualHIDExperiment --event-system-move [--dx points] [--dy points] [--repeat count] [--interval seconds]")
        print("  swift run VirtualHIDExperiment --iohid-post-move [--dx points] [--dy points] [--repeat count] [--interval seconds] [--hid-manager-event]")
        print("  swift run VirtualHIDExperiment --iohid-post-click [--button left|right|middle] [--click-count count] [--phase down|up|click] [--hold seconds]")
        print("  swift run VirtualHIDExperiment --iohid-post-key --keycode code [--flags rawValue]")
        print("  swift run VirtualHIDExperiment --iohid-post-scroll [--vertical lines] [--horizontal lines] [--repeat count]")
        print("  swift run VirtualHIDExperiment --iohid-drag-move [--dx points] [--dy points] [--repeat count] [--interval seconds]")
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

    static func numericArgument(_ name: String, in args: [String]) -> Double? {
        guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else {
            return nil
        }
        return Double(args[index + 1])
    }

    static func stringArgument(_ name: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else {
            return nil
        }
        return args[index + 1]
    }

    static func runEventSystemMouseExperiment(
        demoMotion: Bool,
        dx: Double,
        dy: Double,
        repeatCount: Int,
        interval: TimeInterval
    ) {
        do {
            let eventSystem = try PrivateHIDEventSystem()
            let start = CGEvent(source: nil)?.location ?? .zero
            print("Cursor before event-system demo: \(format(point: start))")

            if demoMotion {
                for deltaX in [24.0, 24.0, -24.0, -24.0] {
                    try eventSystem.dispatchRelativeMouse(dx: deltaX, dy: 0)
                    if interval > 0 {
                        usleep(useconds_t(interval * 1_000_000))
                    }
                }
            } else {
                for _ in 0..<repeatCount {
                    try eventSystem.dispatchRelativeMouse(dx: dx, dy: dy)
                    if interval > 0 {
                        usleep(useconds_t(interval * 1_000_000))
                    }
                }
            }

            usleep(80_000)
            let end = CGEvent(source: nil)?.location ?? .zero
            print("Cursor after event-system demo:  \(format(point: end))")
        } catch {
            print("Event-system experiment failed: \(error)")
        }
    }

    static func runLegacyIOHIDPostEventExperiment(
        dx: Double,
        dy: Double,
        repeatCount: Int,
        interval: TimeInterval,
        postAsHIDManagerEvent: Bool
    ) {
        #if canImport(IOKit.hidsystem)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != IO_OBJECT_NULL else {
            print("Could not find the IOHIDSystem service.")
            return
        }
        defer { IOObjectRelease(service) }

        var connection = io_connect_t()
        let openResult = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection)
        guard openResult == KERN_SUCCESS else {
            print("IOServiceOpen(IOHIDSystem) failed: \(formatIOReturn(openResult))")
            return
        }
        defer { IOServiceClose(connection) }

        let start = CGEvent(source: nil)?.location ?? .zero
        print("Cursor before IOHIDPostEvent demo: \(format(point: start))")
        var eventData = NXEventData()
        var options = UInt32(kIOHIDSetRelativeCursorPosition)
        if postAsHIDManagerEvent {
            options |= UInt32(kIOHIDPostHIDManagerEvent)
        }

        for _ in 0..<repeatCount {
            eventData.mouseMove.dx = Int32(dx.rounded())
            eventData.mouseMove.dy = Int32(dy.rounded())
            let location = IOGPoint(
                x: Int16(clamping: Int(dx.rounded())),
                y: Int16(clamping: Int(dy.rounded()))
            )
            let result = IOHIDPostEvent(
                connection,
                UInt32(NX_MOUSEMOVED),
                location,
                &eventData,
                UInt32(kNXEventDataVersion),
                0,
                options
            )
            print("IOHIDPostEvent result: \(formatIOReturn(result))")
            if interval > 0 {
                usleep(useconds_t(interval * 1_000_000))
            }
        }

        usleep(80_000)
        let end = CGEvent(source: nil)?.location ?? .zero
        print("Cursor after IOHIDPostEvent demo:  \(format(point: end))")
        #else
        print("IOHIDPostEvent is not available in this SDK.")
        #endif
    }

    static func runLegacyIOHIDClickExperiment(
        buttonName: String,
        clickCount: Int,
        phase: String,
        holdDuration: TimeInterval
    ) {
        #if canImport(IOKit.hidsystem)
        withIOHIDSystemConnection { connection in
            let buttonNumber: UInt8
            let downType: UInt32
            let upType: UInt32
            switch buttonName.lowercased() {
            case "right":
                buttonNumber = 1
                downType = UInt32(NX_RMOUSEDOWN)
                upType = UInt32(NX_RMOUSEUP)
            case "middle":
                buttonNumber = 2
                downType = UInt32(NX_OMOUSEDOWN)
                upType = UInt32(NX_OMOUSEUP)
            default:
                buttonNumber = 0
                downType = UInt32(NX_LMOUSEDOWN)
                upType = UInt32(NX_LMOUSEUP)
            }

            var eventData = NXEventData()
            eventData.mouse.buttonNumber = buttonNumber
            eventData.mouse.click = Int32(clamping: clickCount)
            let options = UInt32(kIOHIDSetRelativeCursorPosition | kIOHIDPostHIDManagerEvent)
            var results: [String] = []
            if phase != "up" {
                eventData.mouse.pressure = 255
                let downResult = IOHIDPostEvent(
                    connection,
                    downType,
                    IOGPoint(x: 0, y: 0),
                    &eventData,
                    UInt32(kNXEventDataVersion),
                    0,
                    options
                )
                results.append("down=\(formatIOReturn(downResult))")
                if phase == "down", holdDuration > 0 {
                    print("Holding IOHIDSystem connection open for \(holdDuration)s.")
                    usleep(useconds_t(holdDuration * 1_000_000))
                }
            }
            if phase != "down" {
                if phase == "click" {
                    usleep(40_000)
                }
                eventData.mouse.pressure = 0
                let upResult = IOHIDPostEvent(
                    connection,
                    upType,
                    IOGPoint(x: 0, y: 0),
                    &eventData,
                    UInt32(kNXEventDataVersion),
                    0,
                    options
                )
                results.append("up=\(formatIOReturn(upResult))")
            }
            print("IOHID click results: \(results.joined(separator: " "))")
        }
        #else
        print("IOHIDPostEvent is not available in this SDK.")
        #endif
    }

    static func runLegacyIOHIDKeyExperiment(keyCode: UInt16, flags: UInt32) {
        #if canImport(IOKit.hidsystem)
        withIOHIDSystemConnection { connection in
            var eventData = NXEventData()
            eventData.key.keyCode = keyCode
            let options = UInt32(
                kIOHIDSetRelativeCursorPosition |
                kIOHIDPostHIDManagerEvent |
                kIOHIDSetGlobalEventFlags
            )
            let downResult = IOHIDPostEvent(
                connection,
                UInt32(NX_KEYDOWN),
                IOGPoint(x: 0, y: 0),
                &eventData,
                UInt32(kNXEventDataVersion),
                flags,
                options
            )
            usleep(40_000)
            let upResult = IOHIDPostEvent(
                connection,
                UInt32(NX_KEYUP),
                IOGPoint(x: 0, y: 0),
                &eventData,
                UInt32(kNXEventDataVersion),
                flags,
                options
            )
            eventData.key.keyCode = 0
            let flagsResult = IOHIDPostEvent(
                connection,
                UInt32(NX_FLAGSCHANGED),
                IOGPoint(x: 0, y: 0),
                &eventData,
                UInt32(kNXEventDataVersion),
                0,
                options
            )
            print("IOHID key results: down=\(formatIOReturn(downResult)) up=\(formatIOReturn(upResult)) flags=\(formatIOReturn(flagsResult))")
        }
        #else
        print("IOHIDPostEvent is not available in this SDK.")
        #endif
    }

    static func runLegacyIOHIDScrollExperiment(
        vertical: Int32,
        horizontal: Int32,
        repeatCount: Int
    ) {
        #if canImport(IOKit.hidsystem)
        withIOHIDSystemConnection { connection in
            var eventData = NXEventData()
            eventData.scrollWheel.deltaAxis1 = Int16(clamping: Int(vertical))
            eventData.scrollWheel.deltaAxis2 = Int16(clamping: Int(horizontal))
            eventData.scrollWheel.fixedDeltaAxis1 = vertical.multipliedReportingOverflow(by: 65_536).partialValue
            eventData.scrollWheel.fixedDeltaAxis2 = horizontal.multipliedReportingOverflow(by: 65_536).partialValue
            eventData.scrollWheel.pointDeltaAxis1 = vertical
            eventData.scrollWheel.pointDeltaAxis2 = horizontal
            let options = UInt32(kIOHIDSetRelativeCursorPosition | kIOHIDPostHIDManagerEvent)

            for _ in 0..<repeatCount {
                let result = IOHIDPostEvent(
                    connection,
                    UInt32(NX_SCROLLWHEELMOVED),
                    IOGPoint(x: 0, y: 0),
                    &eventData,
                    UInt32(kNXEventDataVersion),
                    0,
                    options
                )
                guard result == KERN_SUCCESS else {
                    print("IOHID scroll failed: \(formatIOReturn(result))")
                    return
                }
                usleep(20_000)
            }
            print("IOHID scroll results: \(repeatCount) reports posted")
        }
        #else
        print("IOHIDPostEvent is not available in this SDK.")
        #endif
    }

    static func runLegacyIOHIDDragExperiment(
        dx: Int32,
        dy: Int32,
        repeatCount: Int,
        interval: TimeInterval
    ) {
        #if canImport(IOKit.hidsystem)
        withIOHIDSystemConnection { connection in
            let options = UInt32(kIOHIDSetRelativeCursorPosition | kIOHIDPostHIDManagerEvent)
            var buttonData = NXEventData()
            buttonData.mouse.buttonNumber = 0
            buttonData.mouse.click = 1
            buttonData.mouse.pressure = 255
            let downResult = IOHIDPostEvent(
                connection,
                UInt32(NX_LMOUSEDOWN),
                IOGPoint(x: 0, y: 0),
                &buttonData,
                UInt32(kNXEventDataVersion),
                0,
                options
            )
            guard downResult == KERN_SUCCESS else {
                print("IOHID drag down failed: \(formatIOReturn(downResult))")
                return
            }
            print("Left button state after down: \(CGEventSource.buttonState(.hidSystemState, button: .left))")

            var moveData = NXEventData()
            moveData.mouseMove.dx = dx
            moveData.mouseMove.dy = dy
            for _ in 0..<repeatCount {
                let moveResult = IOHIDPostEvent(
                    connection,
                    UInt32(NX_MOUSEMOVED),
                    IOGPoint(x: 0, y: 0),
                    &moveData,
                    UInt32(kNXEventDataVersion),
                    0,
                    options
                )
                guard moveResult == KERN_SUCCESS else {
                    print("IOHID drag move failed: \(formatIOReturn(moveResult))")
                    break
                }
                if interval > 0 {
                    usleep(useconds_t(interval * 1_000_000))
                }
            }
            print("Left button state after motion: \(CGEventSource.buttonState(.hidSystemState, button: .left))")

            buttonData.mouse.pressure = 0
            let upResult = IOHIDPostEvent(
                connection,
                UInt32(NX_LMOUSEUP),
                IOGPoint(x: 0, y: 0),
                &buttonData,
                UInt32(kNXEventDataVersion),
                0,
                options
            )
            print("IOHID drag results: down=\(formatIOReturn(downResult)) up=\(formatIOReturn(upResult))")
        }
        #else
        print("IOHIDPostEvent is not available in this SDK.")
        #endif
    }

    static func withIOHIDSystemConnection(_ operation: (io_connect_t) -> Void) {
        #if canImport(IOKit.hidsystem)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != IO_OBJECT_NULL else {
            print("Could not find the IOHIDSystem service.")
            return
        }
        defer { IOObjectRelease(service) }

        var connection = io_connect_t()
        let result = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection)
        guard result == KERN_SUCCESS else {
            print("IOServiceOpen(IOHIDSystem) failed: \(formatIOReturn(result))")
            return
        }
        defer { IOServiceClose(connection) }
        operation(connection)
        #endif
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
