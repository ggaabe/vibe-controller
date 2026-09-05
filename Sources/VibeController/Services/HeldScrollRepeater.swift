import Foundation

/// Keep background input responsive only while the user is holding a repeat
/// action. Unlike a permanent App Nap opt-out, this still lets an idle app nap
/// and does not prevent the Mac from sleeping.
final class ControllerRepeatActivity {
    private let token = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep,
        reason: "Repeating a held controller action"
    )

    deinit {
        ProcessInfo.processInfo.endActivity(token)
    }
}

/// Native wheel reports must not wait for SwiftUI layout or main-run-loop
/// tracking. All mutable state and output are confined to this input queue.
final class HeldScrollRepeater: @unchecked Sendable {
    typealias Output = @Sendable (Int32, Int32) -> Void

    private struct Session {
        var id: UUID
        var timer: DispatchSourceTimer
        var modifier: ControllerControlID?
    }

    private let queue = DispatchQueue(
        label: "com.vibe-controller.held-scroll",
        qos: .userInteractive
    )
    private let queueKey = DispatchSpecificKey<Bool>()
    private let output: Output
    private var sessions: [ControllerControlID: Session] = [:]
    private var activity: ControllerRepeatActivity?
    private var latestInput: ControllerSnapshot?

    init(output: @escaping Output) {
        self.output = output
        queue.setSpecific(key: queueKey, value: true)
    }

    deinit {
        for session in sessions.values { session.timer.cancel() }
    }

    func start(
        control: ControllerControlID,
        modifier: ControllerControlID?,
        vertical: Int32,
        horizontal: Int32,
        delay: TimeInterval,
        interval: TimeInterval
    ) {
        sync {
            stopOnQueue(control)
            // The release may already have reached the input queue while the
            // main actor was still resolving an earlier press.
            if let latestInput, !isHeld(control, modifier: modifier, in: latestInput) {
                return
            }
            if activity == nil { activity = ControllerRepeatActivity() }
            let id = UUID()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now() + max(0.01, delay),
                repeating: max(0.01, interval),
                leeway: .milliseconds(1)
            )
            timer.setEventHandler { [weak self] in
                guard let self, self.sessions[control]?.id == id else { return }
                self.output(vertical, horizontal)
            }
            sessions[control] = Session(id: id, timer: timer, modifier: modifier)
            timer.resume()
        }
    }

    func stop(_ control: ControllerControlID) {
        sync { stopOnQueue(control) }
    }

    func stopAll() {
        sync {
            for control in Array(sessions.keys) { stopOnQueue(control) }
        }
    }

    /// Release/cable removal also bypasses the UI, preventing runaway scroll
    /// during a slow layout or an open menu.
    func updateInput(_ snapshot: ControllerSnapshot) {
        queue.async { [weak self] in
            guard let self else { return }
            self.latestInput = snapshot
            for (control, session) in Array(self.sessions) {
                if !self.isHeld(control, modifier: session.modifier, in: snapshot) {
                    self.stopOnQueue(control)
                }
            }
        }
    }

    private func isHeld(
        _ control: ControllerControlID,
        modifier: ControllerControlID?,
        in snapshot: ControllerSnapshot
    ) -> Bool {
        func actuated(_ control: ControllerControlID) -> Bool {
            switch control {
            case .leftTrigger, .rightTrigger: return snapshot.value(for: control) >= 0.18
            default: return snapshot.pressedControls.contains(control)
            }
        }
        return snapshot.isConnected && actuated(control) && (modifier.map(actuated) ?? true)
    }

    private func stopOnQueue(_ control: ControllerControlID) {
        sessions.removeValue(forKey: control)?.timer.cancel()
        if sessions.isEmpty { activity = nil }
    }

    private func sync(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) == true {
            work()
        } else {
            queue.sync(execute: work)
        }
    }
}
