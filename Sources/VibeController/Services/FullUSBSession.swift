import AppKit
import Combine
import Darwin
import Foundation
import ServiceManagement
import FullUSBServiceClient
import OSLog

enum FullUSBWire {
    struct Frame: Equatable { let kind: UInt8; let payload: [UInt8] }
    enum Failure: Error { case invalidFrame, disconnected }
    struct Decoder {
        private var pending: [UInt8] = []
        mutating func append(_ bytes: [UInt8]) throws -> [Frame] {
            guard bytes.count <= 4096, pending.count < 72 else { throw Failure.invalidFrame }
            pending.append(contentsOf: bytes)
            var frames: [Frame] = []
            while pending.count >= 72 {
                let kind = pending[0], length = Int(pending[1])
                guard (1...5).contains(kind), length <= 64,
                      pending[2..<8].allSatisfy({ $0 == 0 }),
                      pending[(8 + length)..<72].allSatisfy({ $0 == 0 }),
                      (kind != 1 && kind != 5) || length == 0,
                      kind != 2 || length > 0 else { throw Failure.invalidFrame }
                frames.append(Frame(kind: kind, payload: Array(pending[8..<(8 + length)])))
                pending.removeFirst(72)
            }
            return frames
        }
    }
    static func rumble(left: Double, right: Double, duration: Double) -> [UInt8] {
        let report = XboxUSBRumbleReport.make(left: left, right: right, duration: duration, sequence: 1)
        return [1, report[8], report[9], report[10], 0, 0, 0, 0]
    }
}

/// Explicit per-launch opt-in. A session is not a new Universal Control mode:
/// its snapshots still enter the existing motion and shortcut engines.
@MainActor
final class FullUSBSession: ObservableObject {
    var isAvailable: Bool { FullUSBAvailability.isAvailable }
    @Published private(set) var isEnabled = false
    @Published private(set) var isReady = false
    @Published private(set) var receivedReports = 0
    @Published private(set) var sharePresses = 0
    @Published private(set) var message = "Includes Share and vibration on Xbox Series USB controllers."
    @Published private(set) var helperStatus: FullUSBHelperStatus = .notRegistered
    @Published private(set) var hasAttemptedSession = false
    @Published private(set) var isRemovingHelper = false
    private let worker: FullUSBWorker
    private let output: ControllerHapticOutput
    private let relay: ControllerInputRelay
    var onStopped: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var sessionRequest = UUID()
    private var didStartWorker = false
    private var serviceName: String { (Bundle.main.bundleIdentifier ?? "") + ".usb-service" }
    private var service: SMAppService { .daemon(plistName: serviceName + ".plist") }

    init(relay: ControllerInputRelay, output: ControllerHapticOutput) {
        self.relay = relay; self.output = output
        worker = FullUSBWorker()
        worker.onInput = { [weak relay] input in relay?.receiveFullUSB(input) }
        worker.onTelemetry = { [weak self] reports, shares in
            Task { @MainActor [weak self] in
                self?.receivedReports = reports; self?.sharePresses = shares
            }
        }
        worker.onReady = { [weak self, weak worker, output] in
            if let worker { output.setFullUSBTransport(worker) }
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled else { return }
                self.isReady = true
                self.message = "Full USB input active. Share, sticks, buttons, and vibration use the direct USB session."
            }
        }
        worker.onEnded = { [weak self, relay, output] message in
            relay.setFullUSBActive(false)
            output.endFullUSB()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isEnabled = false; self.isReady = false; self.message = message
                self.didStartWorker = false
                self.onStopped?()
            }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak worker] _ in worker?.requestStop() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.stop() } })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.refreshHelperApproval() } })
        refreshHelperApproval()
    }

    func refreshHelperApproval() {
        guard isAvailable else { helperStatus = .unavailable; return }
        let bundle = Bundle.main.bundleURL
        let packaged = FileManager.default.isExecutableFile(atPath: bundle.appendingPathComponent("Contents/Helpers/VibeUSBService").path)
            && FileManager.default.fileExists(atPath: bundle.appendingPathComponent("Contents/Library/LaunchDaemons/\(serviceName).plist").path)
        let previous = helperStatus
        helperStatus = FullUSBHelperStatus.resolve(service.status, isPackaged: packaged)
        if helperStatus == .enabled && previous == .requiresApproval && message == previous.detail {
            message = "USB helper approved. Choose Enable full USB when you are ready."
        }
    }

    func openHelperSettings() {
        guard isAvailable else { return }
        SMAppService.openSystemSettingsLoginItems()
    }

    func removeHelperApproval() async {
        guard isAvailable, !isEnabled, !isRemovingHelper else { return }
        hasAttemptedSession = true
        isRemovingHelper = true
        defer { isRemovingHelper = false; refreshHelperApproval() }
        do {
            try await service.unregister()
            message = "USB helper removed. Normal controller input and Universal Control are unchanged."
        } catch { message = "Could not remove the USB helper: \(error.localizedDescription)" }
    }

    func start() {
        guard isAvailable else { message = FullUSBAvailability.unavailableMessage; return }
        guard !isEnabled, !isRemovingHelper else { return }
        hasAttemptedSession = true
        refreshHelperApproval()
        if helperStatus == .unavailable { message = helperStatus.detail; return }
        if helperStatus == .notRegistered {
            do { try service.register(); refreshHelperApproval() }
            catch {
                refreshHelperApproval()
                if helperStatus == .requiresApproval {
                    message = helperStatus.detail
                    openHelperSettings()
                    return
                }
                if helperStatus != .enabled {
                    message = "USB helper setup failed: \(error.localizedDescription)"
                    return
                }
            }
        }
        guard helperStatus == .enabled else {
            message = helperStatus.detail
            if helperStatus == .requiresApproval { openHelperSettings() }
            return
        }
        isEnabled = true; isReady = false
        didStartWorker = false
        receivedReports = 0; sharePresses = 0
        message = "Connecting through the approved USB helper…"
        sessionRequest = UUID()
        let request = sessionRequest
        relay.setFullUSBActive(true)
        let name = serviceName
        output.beginFullUSB { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled, self.sessionRequest == request else { return }
                self.didStartWorker = true
                self.worker.start(serviceName: name)
            }
        }
    }

    func stop() {
        guard isEnabled else { return }
        sessionRequest = UUID()
        isReady = false
        message = "Stopping vibration and returning the controller to macOS…"
        // Release held keyboard/mouse state immediately, not after USB cleanup.
        relay.clearFullUSBInput()
        output.stop()
        if !didStartWorker {
            relay.setFullUSBActive(false)
            output.endFullUSB()
            isEnabled = false
            message = "Full USB cancelled. Normal controller input is available."
            onStopped?()
            return
        }
        worker.requestStop()
    }
}

/// All socket reads, heartbeat and haptic writes are serialized off the main
/// and motion queues. Bounded writes fail closed; nothing is replayed later.
final class FullUSBWorker: USBHapticsTransport, @unchecked Sendable {
    var onInput: (@Sendable (XboxUSBInputState) -> Void)?
    var onReady: (@Sendable () -> Void)?
    var onEnded: (@Sendable (String) -> Void)?
    var onTelemetry: (@Sendable (Int, Int) -> Void)?
    private let queue = DispatchQueue(label: "com.vibe-controller.full-usb", qos: .userInteractive)
    private var socket: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var timer: DispatchSourceTimer?
    private var decoder = FullUSBWire.Decoder()
    private var state = XboxUSBInputState()
    private var active = false
    private var ready = false
    private var closing = false
    private var lastFrame = 0.0
    private var started = 0.0
    private var outcome = FullUSBSessionOutcome()
    private let logger = Logger(subsystem: "com.vibe-controller.full-usb", category: "session")
    private var generation = UUID()
    private var reports = 0
    private var shares = 0

    func start(serviceName: String) {
        queue.async { [self] in
            guard FullUSBAvailability.isAvailable else {
                onEnded?(FullUSBAvailability.unavailableMessage)
                return
            }
            guard !active else { return }
            active = true; ready = false; closing = false
            generation = UUID(); let epoch = generation
            decoder = FullUSBWire.Decoder(); state = XboxUSBInputState()
            reports = 0; shares = 0
            started = ProcessInfo.processInfo.systemUptime
            outcome = FullUSBSessionOutcome()
            let heartbeat = DispatchSource.makeTimerSource(queue: queue)
            heartbeat.schedule(deadline: .now() + 0.5, repeating: 0.5)
            heartbeat.setEventHandler { [weak self] in self?.tick() }
            timer = heartbeat; heartbeat.resume()
            logger.info("Requesting session from approved USB service")
            VibeUSBRequestSession(serviceName) { [weak self] fd, error in
                let detail = error.map { String(cString: $0) } ?? "USB service failed."
                guard let self else { if fd >= 0 { close(fd) }; return }
                self.queue.async { [weak self] in
                    guard let self, self.active, self.generation == epoch, !self.closing else {
                        if fd >= 0 { close(fd) }
                        return
                    }
                    guard fd >= 0 else { self.finish(detail); return }
                    self.acceptSession(fd)
                }
            }
        }
    }

    private func acceptSession(_ fd: Int32) {
        // The fd came from a root-domain XPC service whose signing requirement
        // was checked by XPC for this reply. No filesystem socket to impersonate.
        socket = fd
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { finish("Could not configure USB connection."); return }
        guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else { finish("Could not secure USB connection."); return }
        lastFrame = ProcessInfo.processInfo.systemUptime
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readFrames() }
        readSource = source; source.resume()
        try? sendCommand([0, 0, 0, 0, 0, 0, 0, 0])
    }

    private func readFrames() {
        var bytes = [UInt8](repeating: 0, count: 4096)
        // Bound work per dispatch so heartbeats and stop cannot be starved.
        for _ in 0..<16 {
            let count = recv(socket, &bytes, bytes.count, 0)
            if count == 0 { finish("USB session ended. Reconnect if normal USB vibration is silent."); return }
            if count < 0 {
                if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR { finish("USB connection closed.") }
                return
            }
            do {
                for frame in try decoder.append(Array(bytes.prefix(count))) {
                    lastFrame = ProcessInfo.processInfo.systemUptime
                    switch frame.kind {
                    case 1:
                        if !ready && !closing {
                            ready = true
                            // USB input is change-driven. Show the captured
                            // controller as connected even before a stick moves.
                            onInput?(state)
                            onReady?()
                        }
                    case 2:
                        guard ready, !closing, let id = frame.payload.first,
                              let next = XboxUSBReportParser.parse(reportID: Int(id), bytes: frame.payload,
                                  previous: state, supportsShareButton: true) else { continue }
                        if next.pressedControls.contains(.share), !state.pressedControls.contains(.share) { shares += 1 }
                        reports += 1
                        state = next; onInput?(next)
                    case 3, 4:
                        outcome.receive(kind: frame.kind, message: String(decoding: frame.payload, as: UTF8.self))
                    default: break
                    }
                }
            } catch { finish("Invalid USB helper response. Session stopped safely."); return }
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        onTelemetry?(reports, shares)
        if socket >= 0 {
            // Capturing/re-enumerating a USB device can take longer than an
            // ordinary input heartbeat. Do not kill a healthy startup at 5s.
            if now - lastFrame > (ready || closing ? 5 : 30) {
                finish("USB session timed out. Reconnect the controller before retrying."); return
            }
            if !closing { try? sendCommand([0, 0, 0, 0, 0, 0, 0, 0]) }
        } else if now - started > 12 { finish("USB service timed out. Check its approval in System Settings.") }
    }

    private func sendCommand(_ bytes: [UInt8]) throws {
        guard socket >= 0 else { throw FullUSBWire.Failure.disconnected }
        let sent = bytes.withUnsafeBytes { Darwin.send(socket, $0.baseAddress!, $0.count, 0) }
        guard sent == bytes.count else {
            finish("USB connection stopped responding. Reconnect the controller.")
            throw FullUSBWire.Failure.disconnected
        }
    }

    func play(_ pulse: ControllerVibration.Pulse, locality: ControllerVibration.Locality, strength: Float) throws {
        try queue.sync {
            guard ready, !closing else { throw FullUSBWire.Failure.disconnected }
            let intensity = Double(pulse.intensity * strength)
            try sendCommand(FullUSBWire.rumble(left: locality == .right ? 0 : intensity,
                right: locality == .left ? 0 : intensity, duration: pulse.duration))
        }
    }
    func stop() throws {
        try queue.sync { if ready && !closing { try sendCommand([1, 0, 0, 0, 0, 0, 0, 0]) } }
    }
    func requestStop() {
        queue.async { [self] in
            guard active, !closing else { return }
            closing = true; ready = false
            if socket >= 0 { try? sendCommand([2, 0, 0, 0, 0, 0, 0, 0]) }
            else { finish("Full USB disabled. Normal controller input is available.") }
        }
    }
    private func finish(_ message: String) {
        guard active else { return }
        active = false; ready = false
        timer?.cancel(); timer = nil
        readSource?.cancel(); readSource = nil
        if socket >= 0 { shutdown(socket, SHUT_RDWR); close(socket); socket = -1 }
        onTelemetry?(reports, shares)
        let result = outcome.ending(with: message)
        logger.notice("USB session ended: \(result, privacy: .public)")
        onEnded?(result)
    }
}
