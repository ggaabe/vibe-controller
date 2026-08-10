import Foundation

/// Delivers only the newest pending value to the main actor. If the main
/// thread is busy, producers replace the pending telemetry instead of queuing
/// an ever-growing backlog of stale UI updates.
final class MainActorLatestValue<Value: Sendable>: @unchecked Sendable {
    typealias Handler = @MainActor @Sendable (Value) -> Void

    private let lock = NSLock()
    private var latestValue: Value?
    private var deliveryScheduled = false
    private var handler: Handler?

    @MainActor
    func setHandler(_ handler: Handler?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func submit(_ value: Value) {
        lock.lock()
        latestValue = value
        guard !deliveryScheduled else {
            lock.unlock()
            return
        }
        deliveryScheduled = true
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.lock.lock()
            let value = self.latestValue
            let handler = self.handler
            self.latestValue = nil
            self.deliveryScheduled = false
            self.lock.unlock()

            guard let value, let handler else { return }
            MainActor.assumeIsolated {
                handler(value)
            }
        }
    }
}
