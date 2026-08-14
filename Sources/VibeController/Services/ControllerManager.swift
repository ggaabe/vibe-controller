import Foundation
@preconcurrency import GameController

struct StickSnapshot: Equatable, Sendable {
    var x: Double = 0
    var y: Double = 0
    var pressed: Bool = false
}

struct ControllerSnapshot: Equatable, Sendable {
    var isConnected: Bool
    var controllerName: String?
    var connectionSummary: String?
    var controllerFamily: ControllerFamily = .generic
    var batteryLevel: Float?
    var batteryStateDescription: String?
    var pressedControls: Set<ControllerControlID>
    var analogValues: [ControllerControlID: Double]
    var leftStick: StickSnapshot
    var rightStick: StickSnapshot
    var lastUpdated: Date

    static let disconnected = ControllerSnapshot(
        isConnected: false,
        controllerName: nil,
        connectionSummary: nil,
        controllerFamily: .generic,
        batteryLevel: nil,
        batteryStateDescription: nil,
        pressedControls: [],
        analogValues: [:],
        leftStick: StickSnapshot(),
        rightStick: StickSnapshot(),
        lastUpdated: Date()
    )

    func value(for control: ControllerControlID) -> Double {
        analogValues[control] ?? (pressedControls.contains(control) ? 1 : 0)
    }
}

@MainActor
final class ControllerManager: ObservableObject {
    typealias RealtimeHandler = @Sendable (ControllerSnapshot) -> Void

    @Published private(set) var snapshot: ControllerSnapshot = .disconnected

    var onSnapshot: ((ControllerSnapshot) -> Void)?
    var onActionSnapshot: ((ControllerSnapshot) -> Void)?
    var onRealtimeSnapshot: RealtimeHandler? {
        didSet { inputRelay.setRealtimeHandler(onRealtimeSnapshot) }
    }

    private let inputQueue: DispatchQueue
    private let inputRelay: ControllerInputRelay
    private let xboxUSBReader: XboxUSBControllerReader
    private var connectedController: GCController?
    private var notificationTokens: [NSObjectProtocol] = []
    private var pollingTimer: DispatchSourceTimer?

    init() {
        let inputQueue = DispatchQueue(
            label: "com.vibe-controller.controller-input",
            qos: .userInteractive,
            autoreleaseFrequency: .workItem
        )
        let inputRelay = ControllerInputRelay(inputQueue: inputQueue)
        self.inputQueue = inputQueue
        self.inputRelay = inputRelay
        xboxUSBReader = XboxUSBControllerReader(queue: inputQueue)

        inputRelay.setTelemetryHandler { [weak self] snapshot in
            self?.publishTelemetry(snapshot)
        }
        inputRelay.setActionHandler { [weak self] snapshot in
            self?.onActionSnapshot?(snapshot)
        }

        GCController.shouldMonitorBackgroundEvents = true
        registerNotifications()

        xboxUSBReader.onConnectionChanged = { [weak self, weak inputRelay] isConnected, name, family in
            inputRelay?.setRawUSBConnection(
                isConnected: isConnected,
                name: name,
                family: family
            )
            if !isConnected {
                Task { @MainActor [weak self] in
                    self?.refreshConnectedController()
                }
            }
        }
        xboxUSBReader.onInput = { [weak inputRelay] state in
            inputRelay?.receiveRawUSB(state)
        }
        xboxUSBReader.start()
        refreshConnectedController()
    }

    func refreshConnectedController() {
        let candidate = GCController.current
            ?? GCController.controllers().first(where: { $0.extendedGamepad != nil })
        guard candidate !== connectedController else {
            if let candidate {
                enqueueSnapshot(from: candidate, forceTelemetry: true)
            } else {
                inputRelay.receiveGameController(.disconnected, forceTelemetry: true)
            }
            return
        }

        detachCurrentController()
        guard let candidate else {
            inputRelay.receiveGameController(.disconnected, forceTelemetry: true)
            return
        }
        attach(controller: candidate)
    }

    private func registerNotifications() {
        let center = NotificationCenter.default
        for name in [
            Notification.Name.GCControllerDidConnect,
            .GCControllerDidDisconnect,
            .GCControllerDidBecomeCurrent,
            .GCControllerDidStopBeingCurrent,
        ] {
            notificationTokens.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.refreshConnectedController()
                    }
                }
            )
        }
    }

    private func attach(controller: GCController) {
        connectedController = controller
        Self.claimOptionalControllerButtons(on: controller.extendedGamepad)
        Self.installInputHandler(
            on: controller,
            inputQueue: inputQueue,
            inputRelay: inputRelay
        )
        startPolling(controller: controller)
        enqueueSnapshot(from: controller, forceTelemetry: true)
    }

    private func detachCurrentController() {
        connectedController?.extendedGamepad?.valueChangedHandler = nil
        pollingTimer?.cancel()
        pollingTimer = nil
        connectedController = nil
    }

    private func startPolling(controller: GCController) {
        pollingTimer?.cancel()
        pollingTimer = Self.makePollingTimer(
            for: controller,
            inputQueue: inputQueue,
            inputRelay: inputRelay
        )
    }

    private func enqueueSnapshot(from controller: GCController, forceTelemetry: Bool) {
        Self.enqueueSnapshot(
            from: controller,
            inputQueue: inputQueue,
            inputRelay: inputRelay,
            forceTelemetry: forceTelemetry
        )
    }

    nonisolated private static func installInputHandler(
        on controller: GCController,
        inputQueue: DispatchQueue,
        inputRelay: ControllerInputRelay
    ) {
        controller.handlerQueue = inputQueue
        controller.extendedGamepad?.valueChangedHandler = { [weak controller] _, _ in
            guard let controller,
                  let snapshot = makeSnapshot(from: controller) else { return }
            inputRelay.receiveGameController(snapshot)
        }
    }

    nonisolated private static func claimOptionalControllerButtons(on gamepad: GCExtendedGamepad?) {
        guard let gamepad else { return }
        gamepad.buttonHome?.preferredSystemGestureState = .disabled
        gamepad.buttonOptions?.preferredSystemGestureState = .disabled
        gamepad.buttonMenu.preferredSystemGestureState = .disabled

        if let dualSense = gamepad as? GCDualSenseGamepad {
            dualSense.touchpadButton.preferredSystemGestureState = .disabled
        } else if let dualShock = gamepad as? GCDualShockGamepad {
            dualShock.touchpadButton.preferredSystemGestureState = .disabled
        }
    }

    nonisolated private static func makePollingTimer(
        for controller: GCController,
        inputQueue: DispatchQueue,
        inputRelay: ControllerInputRelay
    ) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: inputQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(2))
        timer.setEventHandler { [weak controller] in
            guard let controller,
                  let snapshot = makeSnapshot(from: controller) else { return }
            inputRelay.receiveGameController(snapshot)
        }
        timer.resume()
        return timer
    }

    nonisolated private static func enqueueSnapshot(
        from controller: GCController,
        inputQueue: DispatchQueue,
        inputRelay: ControllerInputRelay,
        forceTelemetry: Bool
    ) {
        inputQueue.async { [weak controller] in
            guard let controller,
                  let snapshot = makeSnapshot(from: controller) else {
                inputRelay.receiveGameController(.disconnected, forceTelemetry: forceTelemetry)
                return
            }
            inputRelay.receiveGameController(snapshot, forceTelemetry: forceTelemetry)
        }
    }

    private func publishTelemetry(_ snapshot: ControllerSnapshot) {
        self.snapshot = snapshot
        onSnapshot?(snapshot)
    }

    nonisolated private static func makeSnapshot(from controller: GCController) -> ControllerSnapshot? {
        guard let gamepad = controller.extendedGamepad else { return nil }

        var pressed = Set<ControllerControlID>()
        var values: [ControllerControlID: Double] = [:]

        func capture(_ control: ControllerControlID, input: GCControllerButtonInput?) {
            guard let input else { return }
            values[control] = Double(input.value)
            if input.isPressed { pressed.insert(control) }
        }

        capture(.buttonSouth, input: gamepad.buttonA)
        capture(.buttonEast, input: gamepad.buttonB)
        capture(.buttonWest, input: gamepad.buttonX)
        capture(.buttonNorth, input: gamepad.buttonY)
        capture(.leftShoulder, input: gamepad.leftShoulder)
        capture(.rightShoulder, input: gamepad.rightShoulder)
        capture(.leftTrigger, input: gamepad.leftTrigger)
        capture(.rightTrigger, input: gamepad.rightTrigger)
        capture(.leftThumbstickButton, input: gamepad.leftThumbstickButton)
        capture(.rightThumbstickButton, input: gamepad.rightThumbstickButton)
        capture(.menu, input: gamepad.buttonMenu)
        capture(.options, input: gamepad.buttonOptions)
        capture(.home, input: gamepad.buttonHome)
        if let dualSense = gamepad as? GCDualSenseGamepad {
            capture(.touchpadButton, input: dualSense.touchpadButton)
        } else if let dualShock = gamepad as? GCDualShockGamepad {
            capture(.touchpadButton, input: dualShock.touchpadButton)
        }

        values[.dpadUp] = Double(gamepad.dpad.up.value)
        values[.dpadDown] = Double(gamepad.dpad.down.value)
        values[.dpadLeft] = Double(gamepad.dpad.left.value)
        values[.dpadRight] = Double(gamepad.dpad.right.value)
        if gamepad.dpad.up.isPressed { pressed.insert(.dpadUp) }
        if gamepad.dpad.down.isPressed { pressed.insert(.dpadDown) }
        if gamepad.dpad.left.isPressed { pressed.insert(.dpadLeft) }
        if gamepad.dpad.right.isPressed { pressed.insert(.dpadRight) }

        let leftStick = StickSnapshot(
            x: Double(gamepad.leftThumbstick.xAxis.value),
            y: Double(gamepad.leftThumbstick.yAxis.value),
            pressed: gamepad.leftThumbstickButton?.isPressed ?? false
        )
        let rightStick = StickSnapshot(
            x: Double(gamepad.rightThumbstick.xAxis.value),
            y: Double(gamepad.rightThumbstick.yAxis.value),
            pressed: gamepad.rightThumbstickButton?.isPressed ?? false
        )
        values[.leftThumbstick] = min(1, hypot(leftStick.x, leftStick.y))
        values[.rightThumbstick] = min(1, hypot(rightStick.x, rightStick.y))

        let battery = controller.battery
        let family: ControllerFamily
        if gamepad is GCDualSenseGamepad || gamepad is GCDualShockGamepad {
            family = .playStation
        } else if gamepad is GCXboxGamepad {
            family = .xbox
        } else {
            family = .inferred(from: controller.vendorName)
        }
        return ControllerSnapshot(
            isConnected: true,
            controllerName: controller.vendorName,
            connectionSummary: controller.isAttachedToDevice ? "Attached" : nil,
            controllerFamily: family,
            batteryLevel: battery?.batteryLevel,
            batteryStateDescription: battery?.batteryState.vibeDescription,
            pressedControls: pressed,
            analogValues: values,
            leftStick: leftStick,
            rightStick: rightStick,
            lastUpdated: Date()
        )
    }
}

private extension GCDeviceBattery.State {
    var vibeDescription: String {
        switch self {
        case .charging:
            return "Charging"
        case .discharging:
            return "Battery"
        case .full:
            return "Full"
        case .unknown:
            return "Unknown"
        @unknown default:
            return "Unknown"
        }
    }
}
