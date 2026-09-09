import Combine
import Foundation
@preconcurrency import CoreHaptics
@preconcurrency import GameController

enum ControllerHapticStatus: Equatable, Sendable {
    case disconnected, unsupported, available, availableUSB, availableFullUSB, failed(String)
    var message: String {
        switch self {
        case .disconnected: "Connect a controller to test vibration."
        case .unsupported: "This controller connection does not expose vibration. Shortcuts still work."
        case .available: "Controller reports vibration support. Use Test vibration to verify."
        case .availableUSB: "Direct USB vibration is ready."
        case .availableFullUSB: "Vibration uses the full USB session. Use Test vibration to verify."
        case .failed(let message): "Vibration unavailable: \(message)"
        }
    }
    var canPlay: Bool {
        switch self {
        case .available, .availableUSB, .availableFullUSB, .failed: true // A preview can retry a stopped engine.
        default: false
        }
    }
}

/// UI preferences are local to this Mac; per-action patterns travel with profiles.
@MainActor
final class ControllerHaptics: ObservableObject {
    nonisolated let output = ControllerHapticOutput()
    private let defaults: UserDefaults
    @Published var isEnabled: Bool { didSet { savePreferences() } }
    @Published var strength: Double { didSet { savePreferences() } }
    @Published var connectionFeedback: Bool { didSet { savePreferences() } }
    @Published private(set) var status: ControllerHapticStatus = .disconnected

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Fresh installs inherit Gabe's saved setup; never overwrite a user's
        // explicit mute, strength, or connection-feedback preference on upgrade.
        isEnabled = defaults.object(forKey: "haptics.enabled") == nil
            ? true : defaults.bool(forKey: "haptics.enabled")
        strength = defaults.object(forKey: "haptics.strength") == nil
            ? 0.5 : min(1, max(0.1, defaults.double(forKey: "haptics.strength")))
        connectionFeedback = defaults.object(forKey: "haptics.connectionFeedback") == nil
            ? true : defaults.bool(forKey: "haptics.connectionFeedback")
        output.onStatus = { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self, self.status != status else { return }
                self.status = status
            }
        }
        configureOutput()
    }

    func attach(_ controller: GCController?) { output.attach(controller) }
    func preview(_ pattern: ControllerVibration) {
        guard isEnabled else { return }
        output.play(pattern, phase: .press)
        if pattern == .grabRelease {
            // Preview the release as well, without sending any keyboard/mouse action.
            output.previewRelease(after: 0.35)
        }
    }
    private func savePreferences() {
        defaults.set(isEnabled, forKey: "haptics.enabled")
        defaults.set(strength, forKey: "haptics.strength")
        defaults.set(connectionFeedback, forKey: "haptics.connectionFeedback")
        configureOutput()
    }
    private func configureOutput() {
        output.configure(enabled: isEnabled, strength: strength, connectionFeedback: connectionFeedback)
    }
}

/// Haptic output never runs on the action, motion, or UI queues. All patterns are
/// finite and stale requests are dropped rather than producing delayed rumble.
final class ControllerHapticOutput: @unchecked Sendable {
    var onStatus: (@Sendable (ControllerHapticStatus) -> Void)?
    private let queue = DispatchQueue(label: "com.vibe-controller.haptics", qos: .userInitiated)
    private var device: Device?
    private var engines: [GCHapticsLocality: CHHapticEngine] = [:]
    private let usbTransportFactory: @Sendable (GCController) -> (any USBHapticsTransport)?
    private var usbRumble: (any USBHapticsTransport)?
    private var fullUSBActive = false
    private var player: (any CHHapticPatternPlayer)?
    private var enabled = false
    private var strength: Float = 0.5
    private var connectionFeedback = true
    private var lastPattern: ControllerVibration = .none
    private var lastTime: TimeInterval = 0
    private var generation: UInt64 = 0
    private let requestLock = NSLock()
    private var requestGeneration: UInt64 = 0

    init(usbTransportFactory: @escaping @Sendable (GCController) -> (any USBHapticsTransport)? = { controller in
        guard controller.extendedGamepad is GCXboxGamepad else { return nil }
        return XboxUSBHapticsTransport.openIfAvailable()
    }) {
        self.usbTransportFactory = usbTransportFactory
    }

    private func invalidateRequests() {
        requestLock.withLock { requestGeneration &+= 1 }
    }

    private final class Device: @unchecked Sendable {
        let controller: GCController
        init(_ controller: GCController) { self.controller = controller }
    }

    func configure(enabled: Bool, strength: Double, connectionFeedback: Bool) {
        invalidateRequests()
        queue.async { [self] in
            self.enabled = enabled
            self.strength = Float(strength.isFinite ? min(1, max(0.1, strength)) : 0.5)
            self.connectionFeedback = connectionFeedback
            if !enabled { stopOnQueue() }
        }
    }

    func attach(_ controller: GCController?) {
        let next = controller.map(Device.init)
        queue.async { [self] in
            guard !fullUSBActive else { return }
            guard device?.controller !== next?.controller else { return }
            invalidateRequests()
            let epoch = requestLock.withLock { requestGeneration }
            stopOnQueue()
            engines.values.forEach { $0.stop(completionHandler: nil) }
            engines.removeAll()
            usbRumble = nil
            device = next
            guard let next else { onStatus?(.disconnected); return }
            usbRumble = usbTransportFactory(next.controller)
            if usbRumble != nil {
                onStatus?(.availableUSB)
                if connectionFeedback { playOnQueue(.doubleTap, phase: .press, epoch: epoch) }
                return
            }
            guard let haptics = next.controller.haptics, !haptics.supportedLocalities.isEmpty else {
                onStatus?(.unsupported); return
            }
            onStatus?(.available)
            if connectionFeedback { playOnQueue(.doubleTap, phase: .press, epoch: epoch) }
        }
    }

    func beginFullUSB(completion: @escaping @Sendable () -> Void) {
        invalidateRequests()
        queue.async { [self] in
            fullUSBActive = true
            stopOnQueue()
            engines.values.forEach { $0.stop(completionHandler: nil) }
            engines.removeAll(); usbRumble = nil; device = nil
            onStatus?(.disconnected)
            completion() // Apple's output handle is closed before capture.
        }
    }

    func setFullUSBTransport(_ transport: FullUSBWorker) {
        installFullUSBTransport(transport)
    }

    // Separate entry point lets tests verify routing without a GCController.
    func installFullUSBTransport(_ transport: any USBHapticsTransport & Sendable) {
        queue.async { [self] in
            guard fullUSBActive else { return }
            usbRumble = transport
            onStatus?(.availableFullUSB)
            if connectionFeedback {
                playOnQueue(.doubleTap, phase: .press, epoch: requestLock.withLock { requestGeneration })
            }
        }
    }

    func endFullUSB() {
        invalidateRequests()
        queue.async { [self] in
            stopOnQueue(); usbRumble = nil; device = nil; fullUSBActive = false
            onStatus?(.disconnected)
        }
    }

    func play(_ pattern: ControllerVibration, phase: ControllerVibration.Phase) {
        guard !pattern.pulses(for: phase).isEmpty else { return }
        let requested = ProcessInfo.processInfo.systemUptime
        let epoch = requestLock.withLock { requestGeneration }
        queue.async { [self] in
            guard ProcessInfo.processInfo.systemUptime - requested < 0.25 else { return }
            playOnQueue(pattern, phase: phase, epoch: epoch, expiresAt: requested + 0.25)
        }
    }

    func stop() {
        invalidateRequests()
        queue.async { [self] in stopOnQueue() }
    }

    func previewRelease(after delay: TimeInterval) {
        let epoch = requestLock.withLock { requestGeneration }
        queue.async { [self] in
            let expected = generation
            queue.asyncAfter(deadline: .now() + delay) { [self] in
                guard expected == generation else { return }
                playOnQueue(.grabRelease, phase: .release, epoch: epoch)
            }
        }
    }

    private func stopOnQueue() {
        generation &+= 1
        try? usbRumble?.stop()
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        lastPattern = .none
    }

    private func playOnQueue(
        _ pattern: ControllerVibration, phase: ControllerVibration.Phase,
        epoch: UInt64, expiresAt: TimeInterval = .infinity
    ) {
        guard requestLock.withLock({ requestGeneration == epoch }),
              enabled else { return }
        let pulses = pattern.pulses(for: phase)
        guard !pulses.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if phase == .press, pattern == lastPattern, now - lastTime < 0.08 { return }
        if usbRumble != nil {
            playUSBOnQueue(pattern, pulses: pulses, epoch: epoch, expiresAt: expiresAt)
            return
        }
        guard let device, let haptics = device.controller.haptics else { return }
        let preferred: GCHapticsLocality
        switch pattern.locality {
        case .left: preferred = .leftHandle
        case .right: preferred = .rightHandle
        case .handles: preferred = .handles
        }
        let locality: GCHapticsLocality = haptics.supportedLocalities.contains(preferred) ? preferred : .default
        do {
            let engine: CHHapticEngine
            if let existing = engines[locality] {
                engine = existing
            } else {
                guard let created = haptics.createEngine(withLocality: locality) else {
                    onStatus?(.unsupported); return
                }
                created.playsHapticsOnly = true
                created.isAutoShutdownEnabled = true
                created.resetHandler = { [weak self, weak device] in
                    self?.queue.async { [weak self, weak device] in
                        guard let self, let device, self.device === device else { return }
                        self.stopOnQueue()
                        self.engines.removeAll()
                    }
                }
                engines[locality] = created
                engine = created
            }
            try engine.start()
            // Initial hardware-engine startup can be slow. Never play a stale
            // acknowledgement, or one cancelled while start() was in flight.
            guard requestLock.withLock({ requestGeneration == epoch }),
                  ProcessInfo.processInfo.systemUptime < expiresAt else { return }
            let events = pulses.map { pulse in
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: pulse.intensity * strength),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                ], relativeTime: pulse.time, duration: pulse.duration)
            }
            let next = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            stopOnQueue()
            player = next
            try next.start(atTime: CHHapticTimeImmediate)
            lastPattern = pattern
            lastTime = now
            onStatus?(.available)
        } catch {
            stopOnQueue()
            engines.removeAll()
            onStatus?(.failed(error.localizedDescription))
        }
    }

    private func playUSBOnQueue(
        _ pattern: ControllerVibration, pulses: [ControllerVibration.Pulse],
        epoch: UInt64, expiresAt: TimeInterval
    ) {
        guard ProcessInfo.processInfo.systemUptime < expiresAt else { return }
        stopOnQueue()
        let expected = generation
        let started = ProcessInfo.processInfo.systemUptime
        lastPattern = pattern
        lastTime = started
        for pulse in pulses {
            let play: @Sendable () -> Void = { [weak self] in
                guard let self, let transport = self.usbRumble, self.enabled, self.generation == expected,
                      self.requestLock.withLock({ self.requestGeneration == epoch }),
                      ProcessInfo.processInfo.systemUptime < started + pulse.time + 0.25 else { return }
                do {
                    try transport.play(pulse, locality: pattern.locality, strength: self.strength)
                    self.onStatus?(self.fullUSBActive ? .availableFullUSB : .availableUSB)
                } catch {
                    self.stopOnQueue()
                    self.onStatus?(.failed(error.localizedDescription))
                }
            }
            if pulse.time == 0 { play() }
            else { queue.asyncAfter(deadline: .now() + pulse.time, execute: play) }
        }
        let end = pulses.map { $0.time + $0.duration }.max() ?? 0
        queue.asyncAfter(deadline: .now() + end + 0.01) { [weak self] in
            guard let self, self.generation == expected else { return }
            // Keep this generation for the grab/release preview, but explicitly
            // stop the motors as well as relying on the finite hardware timer.
            try? self.usbRumble?.stop()
        }
    }
}
