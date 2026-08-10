import Foundation

private struct ControllerActionState: Equatable, Sendable {
    var isConnected: Bool
    var pressedControls: Set<ControllerControlID>
    var leftTriggerActive: Bool
    var rightTriggerActive: Bool
}

extension ControllerSnapshot {
    func hasSameInputPayload(as other: ControllerSnapshot) -> Bool {
        isConnected == other.isConnected &&
            controllerName == other.controllerName &&
            connectionSummary == other.connectionSummary &&
            batteryLevel == other.batteryLevel &&
            batteryStateDescription == other.batteryStateDescription &&
            pressedControls == other.pressedControls &&
            analogValues == other.analogValues &&
            leftStick == other.leftStick &&
            rightStick == other.rightStick
    }

    fileprivate var actionState: ControllerActionState {
        ControllerActionState(
            isConnected: isConnected,
            pressedControls: pressedControls,
            leftTriggerActive: value(for: .leftTrigger) >= 0.18,
            rightTriggerActive: value(for: .rightTrigger) >= 0.18
        )
    }
}

/// Fans controller input into a lossless action stream, a real-time motion
/// stream, and a coalesced UI stream. Every mutation occurs on `inputQueue`.
final class ControllerInputRelay: @unchecked Sendable {
    typealias RealtimeHandler = @Sendable (ControllerSnapshot) -> Void
    typealias MainHandler = @MainActor @Sendable (ControllerSnapshot) -> Void

    private static let telemetryIntervalNanoseconds = 66_666_667

    let inputQueue: DispatchQueue
    private let telemetryDelivery = MainActorLatestValue<ControllerSnapshot>()
    private var telemetryTimer: DispatchSourceTimer?
    private var realtimeHandler: RealtimeHandler?
    private var actionHandler: MainHandler?
    private var latestSnapshot = ControllerSnapshot.disconnected
    private var lastTelemetrySnapshot: ControllerSnapshot?
    private var lastActionState: ControllerActionState?
    private var latestGameControllerSnapshot = ControllerSnapshot.disconnected
    private var rawUSBConnected = false
    private var rawUSBName: String?
    private var latestRawUSBState: XboxUSBInputState?

    init(inputQueue: DispatchQueue) {
        self.inputQueue = inputQueue
        inputQueue.async { [weak self] in
            self?.startTelemetryTimer()
        }
    }

    deinit {
        telemetryTimer?.cancel()
    }

    @MainActor
    func setTelemetryHandler(_ handler: MainHandler?) {
        telemetryDelivery.setHandler(handler)
    }

    func setRealtimeHandler(_ handler: RealtimeHandler?) {
        inputQueue.async { [weak self] in
            self?.realtimeHandler = handler
        }
    }

    func setActionHandler(_ handler: MainHandler?) {
        inputQueue.async { [weak self] in
            self?.actionHandler = handler
        }
    }

    func receiveGameController(_ snapshot: ControllerSnapshot, forceTelemetry: Bool = false) {
        inputQueue.async { [weak self] in
            guard let self else { return }
            self.latestGameControllerSnapshot = snapshot
            guard !self.rawUSBConnected else { return }
            self.publish(snapshot, forceTelemetry: forceTelemetry)
        }
    }

    func setRawUSBConnection(isConnected: Bool, name: String?) {
        inputQueue.async { [weak self] in
            guard let self else { return }
            self.rawUSBConnected = isConnected
            self.rawUSBName = isConnected ? name : nil
            if isConnected {
                if let latestRawUSBState {
                    self.publish(self.rawSnapshot(from: latestRawUSBState), forceTelemetry: true)
                }
            } else {
                self.latestRawUSBState = nil
                self.publish(self.latestGameControllerSnapshot, forceTelemetry: true)
            }
        }
    }

    func receiveRawUSB(_ state: XboxUSBInputState) {
        inputQueue.async { [weak self] in
            guard let self else { return }
            self.latestRawUSBState = state
            self.rawUSBConnected = true
            self.publish(self.rawSnapshot(from: state))
        }
    }

    private func rawSnapshot(from state: XboxUSBInputState) -> ControllerSnapshot {
        ControllerSnapshot(
            isConnected: true,
            controllerName: rawUSBName
                ?? latestGameControllerSnapshot.controllerName
                ?? "Xbox Controller",
            connectionSummary: "USB • Direct HID",
            batteryLevel: latestGameControllerSnapshot.batteryLevel,
            batteryStateDescription: latestGameControllerSnapshot.batteryStateDescription,
            pressedControls: state.pressedControls,
            analogValues: state.analogValues,
            leftStick: state.leftStick,
            rightStick: state.rightStick,
            lastUpdated: latestSnapshot.lastUpdated
        )
    }

    private func publish(_ candidate: ControllerSnapshot, forceTelemetry: Bool = false) {
        guard forceTelemetry || !candidate.hasSameInputPayload(as: latestSnapshot) else { return }

        var snapshot = candidate
        snapshot.lastUpdated = Date()
        latestSnapshot = snapshot
        realtimeHandler?(snapshot)

        let actionState = snapshot.actionState
        if actionState != lastActionState {
            lastActionState = actionState
            if let actionHandler {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        actionHandler(snapshot)
                    }
                }
            }
            submitTelemetryIfNeeded(force: true)
        } else if forceTelemetry {
            submitTelemetryIfNeeded(force: true)
        }
    }

    private func startTelemetryTimer() {
        let timer = DispatchSource.makeTimerSource(queue: inputQueue)
        timer.schedule(
            deadline: .now(),
            repeating: .nanoseconds(Self.telemetryIntervalNanoseconds),
            leeway: .milliseconds(5)
        )
        timer.setEventHandler { [weak self] in
            self?.submitTelemetryIfNeeded(force: false)
        }
        telemetryTimer = timer
        timer.resume()
    }

    private func submitTelemetryIfNeeded(force: Bool) {
        if !force,
           let lastTelemetrySnapshot,
           latestSnapshot.hasSameInputPayload(as: lastTelemetrySnapshot) {
            return
        }
        lastTelemetrySnapshot = latestSnapshot
        telemetryDelivery.submit(latestSnapshot)
    }
}
