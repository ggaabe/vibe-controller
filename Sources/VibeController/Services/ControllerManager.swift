import Foundation
import GameController

struct StickSnapshot: Equatable, Sendable {
    var x: Double = 0
    var y: Double = 0
    var pressed: Bool = false
}

struct ControllerSnapshot: Equatable, Sendable {
    var isConnected: Bool
    var controllerName: String?
    var connectionSummary: String?
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
    @Published private(set) var snapshot: ControllerSnapshot = .disconnected

    var onSnapshot: ((ControllerSnapshot) -> Void)?

    private var connectedController: GCController?
    private var notificationTokens: [NSObjectProtocol] = []
    private var pollingTimer: DispatchSourceTimer?
    private let xboxUSBReader: XboxUSBControllerReader
    private var rawUSBState: XboxUSBInputState?
    private var rawUSBControllerName: String?

    init() {
        xboxUSBReader = XboxUSBControllerReader()
        GCController.shouldMonitorBackgroundEvents = true
        registerNotifications()
        xboxUSBReader.onConnectionChanged = { [weak self] isConnected, name in
            guard let self else { return }
            self.rawUSBControllerName = isConnected ? name : nil
            if !isConnected {
                self.rawUSBState = nil
                self.refreshConnectedController()
            }
        }
        xboxUSBReader.onInput = { [weak self] state in
            self?.updateSnapshot(fromRawUSBState: state)
        }
        refreshConnectedController()
    }

    func refreshConnectedController() {
        let candidate = GCController.current ?? GCController.controllers().first(where: { $0.extendedGamepad != nil })
        guard candidate !== connectedController else {
            if let candidate {
                updateSnapshot(from: candidate)
            } else {
                setDisconnected()
            }
            return
        }

        detachCurrentController()
        guard let candidate else {
            setDisconnected()
            return
        }

        attach(controller: candidate)
    }

    private func registerNotifications() {
        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshConnectedController()
                }
            }
        )
        notificationTokens.append(
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshConnectedController()
                }
            }
        )
        notificationTokens.append(
            center.addObserver(forName: .GCControllerDidBecomeCurrent, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshConnectedController()
                }
            }
        )
        notificationTokens.append(
            center.addObserver(forName: .GCControllerDidStopBeingCurrent, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshConnectedController()
                }
            }
        )
    }

    private func attach(controller: GCController) {
        connectedController = controller
        controller.handlerQueue = .main
        controller.extendedGamepad?.valueChangedHandler = { [weak self] _, _ in
            Task { @MainActor in
                self?.updateSnapshot(from: controller)
            }
        }
        startPolling(controller: controller)
        updateSnapshot(from: controller, forcePublish: true)
    }

    private func detachCurrentController() {
        connectedController?.extendedGamepad?.valueChangedHandler = nil
        pollingTimer?.cancel()
        pollingTimer = nil
        connectedController = nil
    }

    private func setDisconnected() {
        snapshot = .disconnected
        onSnapshot?(snapshot)
    }

    private func startPolling(controller: GCController) {
        pollingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(4))
        timer.setEventHandler { [weak self] in
            guard let self, self.connectedController === controller else { return }
            self.updateSnapshot(from: controller)
        }
        pollingTimer = timer
        timer.resume()
    }

    private func updateSnapshot(from controller: GCController, forcePublish: Bool = false) {
        if rawUSBState != nil {
            return
        }

        guard let gamepad = controller.extendedGamepad else {
            setDisconnected()
            return
        }

        var pressed = Set<ControllerControlID>()
        var values: [ControllerControlID: Double] = [:]

        func capture(_ control: ControllerControlID, input: GCControllerButtonInput?) {
            guard let input else { return }
            values[control] = Double(input.value)
            if input.isPressed {
                pressed.insert(control)
            }
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
        var candidate = ControllerSnapshot(
            isConnected: true,
            controllerName: controller.vendorName,
            connectionSummary: controller.isAttachedToDevice ? "Attached" : nil,
            batteryLevel: battery?.batteryLevel,
            batteryStateDescription: battery?.batteryState.vibeDescription,
            pressedControls: pressed,
            analogValues: values,
            leftStick: leftStick,
            rightStick: rightStick,
            lastUpdated: snapshot.lastUpdated
        )
        if !forcePublish, candidate == snapshot {
            return
        }
        candidate.lastUpdated = Date()
        snapshot = candidate
        onSnapshot?(snapshot)
    }

    private func updateSnapshot(fromRawUSBState state: XboxUSBInputState) {
        rawUSBState = state

        let battery = connectedController?.battery
        var candidate = ControllerSnapshot(
            isConnected: true,
            controllerName: rawUSBControllerName ?? connectedController?.vendorName ?? "Xbox Controller",
            connectionSummary: "USB • Direct HID",
            batteryLevel: battery?.batteryLevel,
            batteryStateDescription: battery?.batteryState.vibeDescription,
            pressedControls: state.pressedControls,
            analogValues: state.analogValues,
            leftStick: state.leftStick,
            rightStick: state.rightStick,
            lastUpdated: snapshot.lastUpdated
        )
        guard candidate != snapshot else { return }
        candidate.lastUpdated = Date()
        snapshot = candidate
        onSnapshot?(snapshot)
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
