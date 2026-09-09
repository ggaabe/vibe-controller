import CoreGraphics
import Foundation

struct DemoFollowDisplay: Sendable {
    var id: UInt32
    var bounds: CGRect // Quartz global coordinates, including negative Y above the main screen.
}

struct DemoDisplayChange: Codable, Equatable, Sendable {
    var time: Double // Session-relative host-clock seconds.
    var displayID: UInt32
}

struct DemoDisplayFollowState {
    var displays: [DemoFollowDisplay]
    var settlingTime = 0.12
    private(set) var current: UInt32?
    private var candidate: UInt32?
    private var candidateSince = 0.0

    init(displays: [DemoFollowDisplay], settlingTime: Double = 0.12) {
        self.displays = displays
        self.settlingTime = settlingTime
    }

    mutating func observe(point: CGPoint?, time: Double) -> DemoDisplayChange? {
        let target = point.flatMap { point in
            // Retain the current source in mirrored/overlapping arrangements.
            displays.first { $0.id == current && $0.bounds.contains(point) }
                ?? displays.first { $0.bounds.contains(point) }
        }?.id
        if current == nil {
            guard let initial = target ?? displays.first?.id else { return nil }
            current = initial
            return DemoDisplayChange(time: time, displayID: initial)
        }
        guard let target, target != current else { candidate = nil; return nil }
        if candidate != target {
            candidate = target
            candidateSince = time
            return nil
        }
        guard time - candidateSince >= settlingTime else { return nil }
        current = target
        candidate = nil
        // Backdate the edit to the first stable observation, not the later
        // confirmation. A quick excursion at a display boundary makes no cut.
        return DemoDisplayChange(time: candidateSince, displayID: target)
    }
}

/// Observes the real system pointer; does not intercept input or guess the
/// destination from an LB/RB shortcut. Only exists during an explicit take.
final class DemoDisplayFollowMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.vibe-controller.demo-follow", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var state: DemoDisplayFollowState
    private var changes: [DemoDisplayChange] = []
    private let journal: DemoCaptureJournal
    private let onChange: @Sendable (UInt32) -> Void

    init(displays: [DemoFollowDisplay], journal: DemoCaptureJournal,
         onChange: @escaping @Sendable (UInt32) -> Void) {
        state = DemoDisplayFollowState(displays: displays)
        self.journal = journal
        self.onChange = onChange
    }

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(5))
            timer.setEventHandler { [weak self] in self?.sample() }
            self.timer = timer
            timer.resume()
        }
    }

    private func sample() {
        guard changes.count < 100_000 else { return } // Bounded even for an accidentally very long take.
        // Refresh geometry as display arrangements/resolutions change.
        state.displays = state.displays.map { DemoFollowDisplay(id: $0.id, bounds: CGDisplayBounds($0.id)) }
        let point = CGEvent(source: nil)?.location
        if let change = state.observe(point: point, time: DemoCaptureClock.now - journal.startHostTime) {
            changes.append(change)
            journal.submit {
                DemoCaptureEvent(kind: "display_changed", time: change.time,
                    label: "Follow local display \(change.displayID)", values: ["displayID": Double(change.displayID)])
            }
            onChange(change.displayID)
        }
    }

    func stop() async -> [DemoDisplayChange] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                timer?.cancel()
                timer = nil
                continuation.resume(returning: changes)
            }
        }
    }

    deinit { timer?.cancel() }
}

struct DemoFollowSegment: Codable, Equatable, Sendable {
    var displayID: UInt32
    var file: String
    var sessionStart: Double
    var duration: Double
    var sourceStart: Double
}

struct DemoFollowPlan: Codable, Sendable {
    var schemaVersion = 1
    var sessionOrigin: Double
    var duration: Double
    var segments: [DemoFollowSegment]

    static func make(displays: [DemoDisplayResult], changes: [DemoDisplayChange]) throws -> DemoFollowPlan {
        let sources = displays.filter { $0.frames > 0 && $0.firstFrameSessionTime?.isFinite == true
            && $0.duration.isFinite && $0.duration > 0 && $0.error == nil }
        guard sources.count == displays.count, !sources.isEmpty else {
            throw DemoCaptureError.message("A source recording is incomplete. The originals were preserved; the follow-cursor movie was skipped.")
        }
        let start = sources.compactMap(\.firstFrameSessionTime).max()!
        let end = sources.map { $0.firstFrameSessionTime! + $0.duration }.min()!
        guard end - start >= 1.0 / 30 else { throw DemoCaptureError.message("The take is too short for a follow-cursor movie.") }
        let knownIDs = Set(sources.map(\.displayID))
        let sorted = changes.filter { $0.time.isFinite && knownIDs.contains($0.displayID) }
            .sorted { $0.time < $1.time }
        var active = sorted.last(where: { $0.time <= start })?.displayID
            ?? sorted.first?.displayID ?? sources[0].displayID
        var cursor = start
        var segments: [DemoFollowSegment] = []
        func append(until: Double) {
            guard until > cursor, let source = sources.first(where: { $0.displayID == active }) else { return }
            segments.append(DemoFollowSegment(displayID: active, file: source.file,
                sessionStart: cursor, duration: until - cursor, sourceStart: cursor - source.firstFrameSessionTime!))
        }
        for change in sorted where change.time > start && change.time < end {
            guard change.displayID != active else { continue }
            append(until: change.time)
            cursor = change.time
            active = change.displayID
        }
        append(until: end)
        return DemoFollowPlan(sessionOrigin: start, duration: end - start, segments: segments)
    }
}
