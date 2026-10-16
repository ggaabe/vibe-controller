import Foundation

/// Joystick input can continue while every app window is hidden. Queue QoS
/// alone does not opt the process out of App Nap's timer and I/O throttling.
/// Keep the assertion scoped to actual movement, not to the app's lifetime.
/// Like held scrolling, this does not prevent display or system sleep.
final class CursorMotionActivity {
    static let options: ProcessInfo.ActivityOptions = [
        .userInitiatedAllowingIdleSystemSleep, .latencyCritical,
    ]

    private let begin: () -> NSObjectProtocol
    private let end: (NSObjectProtocol) -> Void
    private var token: NSObjectProtocol?

    var isActive: Bool { token != nil }

    init(
        begin: @escaping () -> NSObjectProtocol = {
            ProcessInfo.processInfo.beginActivity(
                options: CursorMotionActivity.options,
                reason: "Responding to controller cursor movement"
            )
        },
        end: @escaping (NSObjectProtocol) -> Void = { ProcessInfo.processInfo.endActivity($0) }
    ) {
        self.begin = begin
        self.end = end
    }

    func setActive(_ active: Bool) {
        if active, token == nil {
            token = begin()
        } else if !active, let token {
            self.token = nil
            end(token)
        }
    }

    deinit {
        if let token { end(token) }
    }
}

/// Measures output intervals, not controller-report rate (an unchanged held
/// stick need not send new reports). Idle time is deliberately excluded.
struct CursorOutputCadence {
    struct Report {
        var intervals: Int
        var duration: TimeInterval
        var longestGap: TimeInterval
        var lateIntervals: Int

        var frequency: Double { Double(intervals) / duration }
    }

    private var previousTime: TimeInterval?
    private var intervals = 0
    private var duration: TimeInterval = 0
    private var longestGap: TimeInterval = 0
    private var lateIntervals = 0

    mutating func record(at time: TimeInterval) -> Report? {
        defer { previousTime = time }
        guard let previousTime else { return nil }
        let gap = time - previousTime
        guard gap > 0 else { return nil }
        intervals += 1
        duration += gap
        longestGap = max(longestGap, gap)
        if gap > 1.0 / 40.0 { lateIntervals += 1 }
        guard duration >= 2 else { return nil }
        let report = Report(intervals: intervals, duration: duration,
                            longestGap: longestGap, lateIntervals: lateIntervals)
        reset()
        return report
    }

    mutating func reset() {
        self = CursorOutputCadence()
    }
}
