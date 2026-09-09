import AppKit
import Combine
import Darwin
import Foundation
import Security

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
    @Published private(set) var isEnabled = false
    @Published private(set) var isReady = false
    @Published private(set) var receivedReports = 0
    @Published private(set) var sharePresses = 0
    @Published private(set) var message = "Includes Share and vibration on Xbox Series USB controllers."
    private let worker: FullUSBWorker
    private let output: ControllerHapticOutput
    private let relay: ControllerInputRelay
    var onStopped: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

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
                self.onStopped?()
            }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak worker] _ in worker?.requestStop() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.stop() } })
    }

    func start() {
        guard !isEnabled else { return }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/VibeXboxUSBSession")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            message = "Full USB requires the packaged, signed app. Rebuild the app bundle to include its USB helper."
            return
        }
        isEnabled = true; isReady = false
        receivedReports = 0; sharePresses = 0
        message = "Approve the administrator prompt to connect. This app temporarily takes exclusive control of the Xbox USB device."
        relay.setFullUSBActive(true)
        output.beginFullUSB { [worker] in worker.start(helper: helper) }
    }

    func stop() {
        guard isEnabled else { return }
        isReady = false
        message = "Stopping vibration and returning the controller to macOS…"
        // Release held keyboard/mouse state immediately, not after USB cleanup.
        relay.clearFullUSBInput()
        output.stop()
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
    private var listener: Int32 = -1
    private var socket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var readSource: DispatchSourceRead?
    private var timer: DispatchSourceTimer?
    private var authorization: Process?
    private var directory: URL?
    private var decoder = FullUSBWire.Decoder()
    private var state = XboxUSBInputState()
    private var active = false
    private var ready = false
    private var closing = false
    private var lastFrame = 0.0
    private var started = 0.0
    private var endMessage = "USB session ended. Reconnect if normal USB vibration is silent."
    private var generation = UUID()
    private var reports = 0
    private var shares = 0

    func start(helper: URL) {
        queue.async { [self] in
            guard !active else { return }
            active = true; ready = false; closing = false
            generation = UUID(); let epoch = generation
            decoder = FullUSBWire.Decoder(); state = XboxUSBInputState()
            reports = 0; shares = 0
            started = ProcessInfo.processInfo.systemUptime
            endMessage = "USB session ended. Reconnect if normal USB vibration is silent."
            do {
                // /tmp keeps sockaddr_un below its 104-byte path limit. mkdir is
                // atomic and fails on a pre-existing path; permissions are 0700.
                let dir = URL(fileURLWithPath: "/tmp/vibe-usb-\(UUID().uuidString)")
                guard mkdir(dir.path, 0o700) == 0 else { throw FullUSBWire.Failure.disconnected }
                directory = dir
                let path = dir.appendingPathComponent("session.sock").path
                listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
                guard listener >= 0 else { throw FullUSBWire.Failure.disconnected }
                var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
                let bytes = Array(path.utf8CString)
                guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw FullUSBWire.Failure.invalidFrame }
                withUnsafeMutableBytes(of: &address.sun_path) { raw in
                    raw.copyBytes(from: bytes.map { UInt8(bitPattern: $0) })
                }
                let bound = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                guard bound == 0, chmod(path, 0o600) == 0, listen(listener, 1) == 0 else {
                    throw FullUSBWire.Failure.disconnected
                }
                guard fcntl(listener, F_SETFL, O_NONBLOCK) == 0 else { throw FullUSBWire.Failure.disconnected }
                let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
                source.setEventHandler { [weak self] in self?.acceptConnection() }
                acceptSource = source; source.resume()
                let heartbeat = DispatchSource.makeTimerSource(queue: queue)
                heartbeat.schedule(deadline: .now() + 0.5, repeating: 0.5)
                heartbeat.setEventHandler { [weak self] in self?.tick() }
                timer = heartbeat; heartbeat.resume()

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                let command = "exec \(Self.shellQuote(helper.path)) --socket \(Self.shellQuote(path))"
                process.arguments = ["-e", "do shell script \(Self.appleScriptQuote(command)) with administrator privileges"]
                let errors = Pipe(); process.standardError = errors
                process.standardOutput = FileHandle.nullDevice
                process.terminationHandler = { [weak self] process in
                    // osascript only returns a short error here; USB input goes
                    // through the socket, never through a buffered script pipe.
                    let data = errors.fileHandleForReading.readDataToEndOfFile()
                    let detail = String(decoding: data.prefix(1024), as: UTF8.self)
                    self?.queue.async { [weak self] in
                        guard let self, self.active, self.generation == epoch else { return }
                        if self.socket < 0 {
                            self.finish(process.terminationStatus == 0 ? self.endMessage :
                                (detail.contains("-128") ? "USB authorization cancelled. Normal controller input is unchanged." :
                                 "USB session could not start. \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"))
                        }
                    }
                }
                authorization = process
                try process.run()
            } catch { finish("Could not start the USB session: \(error.localizedDescription)") }
        }
    }

    private static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private static func appleScriptQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func acceptConnection() {
        let fd = accept(listener, nil, nil)
        guard fd >= 0 else { return }
        guard socket < 0, Self.authorizedHelper(fd) else { close(fd); return }
        socket = fd
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { finish("Could not configure USB connection."); return }
        lastFrame = ProcessInfo.processInfo.systemUptime
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readFrames() }
        readSource = source; source.resume()
        try? sendCommand([0, 0, 0, 0, 0, 0, 0, 0])
    }

    private static func authorizedHelper(_ fd: Int32) -> Bool {
        var uid: uid_t = 1, gid: gid_t = 1, pid: pid_t = 0
        var size = socklen_t(MemoryLayout.size(ofValue: pid))
        guard getpeereid(fd, &uid, &gid) == 0, uid == 0,
              getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 1 else { return false }
        var code: SecCode?, own: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &code) == errSecSuccess,
              let code, SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess,
              SecCodeCopySelf([], &own) == errSecSuccess, let own else { return false }
        var info: CFDictionary?, ownInfo: CFDictionary?
        var staticCode: SecStaticCode?, ownStaticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyStaticCode(own, [], &ownStaticCode) == errSecSuccess, let ownStaticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              SecCodeCopySigningInformation(ownStaticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &ownInfo) == errSecSuccess,
              let info = info as? [String: Any], let ownInfo = ownInfo as? [String: Any],
              info[kSecCodeInfoIdentifier as String] as? String == "com.vibe-controller.xbox-usb-session",
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String,
              team == ownInfo[kSecCodeInfoTeamIdentifier as String] as? String else { return false }
        return true
    }

    private func readFrames() {
        var bytes = [UInt8](repeating: 0, count: 4096)
        // Bound work per dispatch so heartbeats and stop cannot be starved.
        for _ in 0..<16 {
            let count = recv(socket, &bytes, bytes.count, 0)
            if count == 0 { finish(endMessage); return }
            if count < 0 {
                if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR { finish(endMessage) }
                return
            }
            do {
                for frame in try decoder.append(Array(bytes.prefix(count))) {
                    lastFrame = ProcessInfo.processInfo.systemUptime
                    switch frame.kind {
                    case 1:
                        if !ready && !closing { ready = true; onReady?() }
                    case 2:
                        guard ready, !closing, let id = frame.payload.first,
                              let next = XboxUSBReportParser.parse(reportID: Int(id), bytes: frame.payload,
                                  previous: state, supportsShareButton: true) else { continue }
                        if next.pressedControls.contains(.share), !state.pressedControls.contains(.share) { shares += 1 }
                        reports += 1
                        state = next; onInput?(next)
                    case 3, 4: endMessage = String(decoding: frame.payload, as: UTF8.self)
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
            if now - lastFrame > 5 { finish("USB session timed out. Reconnect the controller before retrying."); return }
            if !closing { try? sendCommand([0, 0, 0, 0, 0, 0, 0, 0]) }
        } else if now - started > 120 { finish("USB authorization timed out. You can try again.") }
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
        acceptSource?.cancel(); acceptSource = nil
        if socket >= 0 { shutdown(socket, SHUT_RDWR); close(socket); socket = -1 }
        if listener >= 0 { close(listener); listener = -1 }
        if let directory {
            // Only these two paths were created by this session.
            unlink(directory.appendingPathComponent("session.sock").path)
            rmdir(directory.path)
        }
        directory = nil
        if let authorization, authorization.isRunning { authorization.terminate() }
        authorization = nil
        onTelemetry?(reports, shares)
        onEnded?(message)
    }
}
