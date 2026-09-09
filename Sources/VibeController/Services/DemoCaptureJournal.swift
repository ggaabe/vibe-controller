import CoreMedia
import Foundation

enum DemoCaptureClock {
    static var now: Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }
}

/// Caps analog telemetry, but never intentionally throttles a button/trigger edge.
struct DemoInputGate {
    private var lastEdges: Set<ControllerControlID>?
    private var connected: Bool?
    private var lastTime = -Double.infinity

    mutating func accepts(_ snapshot: ControllerSnapshot, at time: Double) -> Bool {
        var edges = snapshot.pressedControls
        if snapshot.value(for: .leftTrigger) >= 0.18 { edges.insert(.leftTrigger) }
        if snapshot.value(for: .rightTrigger) >= 0.18 { edges.insert(.rightTrigger) }
        if snapshot.leftStick.pressed { edges.insert(.leftThumbstickButton) }
        if snapshot.rightStick.pressed { edges.insert(.rightThumbstickButton) }
        let changed = edges != lastEdges || connected != snapshot.isConnected
        guard changed || time - lastTime >= 1.0 / 60 else { return false }
        lastEdges = edges
        connected = snapshot.isConnected
        lastTime = time
        return true
    }
}

struct DemoCaptureEvent: Codable, Sendable {
    var kind: String
    var time: Double
    var label: String?
    var control: String?
    var modifier: String?
    var actionType: String?
    var triggerMode: String?
    var connected: Bool?
    var family: String?
    var pressed: [String]?
    var values: [String: Double]?
}

struct DemoJournalResult: Sendable {
    var written: Int
    var dropped: Int
    var error: String?
}

/// All encoding and file writes happen on this utility queue. Admission is
/// bounded so a slow disk cannot build an unbounded backlog in controller input.
final class DemoCaptureJournal: @unchecked Sendable {
    let startHostTime: Double
    private let queue: DispatchQueue
    private let lock = NSLock()
    private let file: FileHandle
    private let capacity: Int
    private var pending = 0
    private var dropped = 0
    private var closed = false
    private var written = 0 // queue-confined
    private var writeError: String? // queue-confined

    init(url: URL, startHostTime: Double, capacity: Int = 2048,
         queue: DispatchQueue = DispatchQueue(label: "com.vibe-controller.demo-journal", qos: .utility)) throws {
        self.startHostTime = startHostTime
        self.capacity = capacity
        self.queue = queue
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        file = try FileHandle(forWritingTo: url)
    }

    func submit(_ makeEvent: @escaping @Sendable () -> DemoCaptureEvent) {
        lock.withLock {
            guard !closed else { return }
            guard pending < capacity else { dropped += 1; return }
            pending += 1
            queue.async { [self] in
                defer { lock.withLock { pending -= 1 } }
                guard writeError == nil else { return }
                do {
                    var data = try JSONEncoder().encode(makeEvent())
                    data.append(0x0a)
                    try file.write(contentsOf: data)
                    written += 1
                } catch { writeError = error.localizedDescription }
            }
        }
    }

    func finish() async -> DemoJournalResult {
        await withCheckedContinuation { continuation in
            lock.withLock {
                closed = true
                queue.async { [self] in
                    do { try file.synchronize(); try file.close() }
                    catch { writeError = writeError ?? error.localizedDescription }
                    continuation.resume(returning: DemoJournalResult(
                        written: written, dropped: lock.withLock { dropped }, error: writeError
                    ))
                }
            }
        }
    }
}

/// Always present, inert when not recording. The existing motion and action
/// callbacks keep ownership of their real-time paths; capture only observes.
final class DemoCaptureEventSink: @unchecked Sendable {
    private let lock = NSLock()
    private var journal: DemoCaptureJournal?
    private var gate = DemoInputGate()

    func attach(_ journal: DemoCaptureJournal) {
        lock.withLock { self.journal = journal; gate = DemoInputGate() }
    }

    func detach() { lock.withLock { journal = nil } }

    func input(_ snapshot: ControllerSnapshot) {
        lock.withLock {
            guard let journal else { return }
            let hostTime = DemoCaptureClock.now
            guard gate.accepts(snapshot, at: hostTime) else { return }
            journal.submit {
                DemoCaptureEvent(kind: "controller_input", time: hostTime - journal.startHostTime,
                    connected: snapshot.isConnected, family: snapshot.controllerFamily.rawValue,
                    pressed: snapshot.pressedControls.map(\.rawValue).sorted(), values: [
                        "leftX": snapshot.leftStick.x, "leftY": snapshot.leftStick.y,
                        "rightX": snapshot.rightStick.x, "rightY": snapshot.rightStick.y,
                        "leftStickPressed": snapshot.leftStick.pressed ? 1 : 0,
                        "rightStickPressed": snapshot.rightStick.pressed ? 1 : 0,
                        "leftTrigger": snapshot.value(for: .leftTrigger),
                        "rightTrigger": snapshot.value(for: .rightTrigger)
                    ])
            }
        }
    }

    /// Mapping accepted by the action engine, NOT proof of delivery or visible
    /// response. In particular, a remote Mac's foreground app is not observable.
    func action(_ mapping: ControllerActionMapping, control: ControllerControlID,
                modifier: ControllerControlID?, phase: String = "press") {
        let hostTime = DemoCaptureClock.now
        lock.withLock {
            guard let journal else { return }
            journal.submit {
                DemoCaptureEvent(kind: "resolved_action", time: hostTime - journal.startHostTime,
                    label: "\(phase): \(mapping.summary)", control: control.rawValue,
                    modifier: modifier?.rawValue, actionType: mapping.actionType.rawValue,
                    triggerMode: mapping.triggerMode.rawValue)
            }
        }
    }

    func marker(_ label: String) {
        let hostTime = DemoCaptureClock.now
        lock.withLock {
            guard let journal else { return }
            journal.submit { DemoCaptureEvent(kind: "marker", time: hostTime - journal.startHostTime, label: label) }
        }
    }
}
