import AppKit
import CoreGraphics
import Foundation
import simd

enum CursorActivityState: String, Sendable {
    case disabled
    case needsAccessibility
    case idle
    case moving
}

struct CursorDiagnostics: Sendable {
    var state: CursorActivityState
    var velocityX: Double
    var velocityY: Double
    var lastPostedAt: Date?
    var lastPostedLocation: CGPoint?
    var message: String

    static let initial = CursorDiagnostics(
        state: .idle,
        velocityX: 0,
        velocityY: 0,
        lastPostedAt: nil,
        lastPostedLocation: nil,
        message: "Waiting for stick input."
    )
}

@MainActor
final class CursorEngine: @unchecked Sendable {
    typealias DiagnosticsHandler = @MainActor @Sendable (CursorDiagnostics) -> Void
    typealias MovementInterceptor = @MainActor @Sendable (CGPoint, SIMD2<Double>) -> Bool
    typealias ZoomStepHandler = @MainActor @Sendable (StickZoomDirection) -> Void

    let universalControlInputBridge: UniversalControlInputBridge
    private nonisolated let motionLoop: CursorMotionLoop

    var isEnabled = true {
        didSet { motionLoop.setEnabled(isEnabled) }
    }
    var accessibilityTrusted = false {
        didSet { motionLoop.setAccessibilityTrusted(accessibilityTrusted) }
    }
    var suspendControllerMotion = false {
        didSet { motionLoop.setSuspended(suspendControllerMotion) }
    }
    var onDiagnostics: DiagnosticsHandler? {
        didSet { motionLoop.setDiagnosticsHandler(onDiagnostics) }
    }
    var movementInterceptor: MovementInterceptor? {
        didSet { motionLoop.setMovementInterceptor(movementInterceptor) }
    }
    var onZoomStep: ZoomStepHandler? {
        didSet { motionLoop.setZoomStepHandler(onZoomStep) }
    }

    var isDraggingLeftMouse: Bool {
        get { motionLoop.isDraggingLeftMouse }
    }

    init(universalControlInputBridge: UniversalControlInputBridge = UniversalControlInputBridge()) {
        self.universalControlInputBridge = universalControlInputBridge
        motionLoop = CursorMotionLoop(inputBridge: universalControlInputBridge)
    }

    deinit {
        motionLoop.stop()
    }

    /// Fast controller samples enter directly from the input queue and never
    /// wait for SwiftUI or the main run loop.
    nonisolated func updateInput(snapshot: ControllerSnapshot) {
        motionLoop.updateInput(snapshot: snapshot)
    }

    func updateConfiguration(_ cursorConfiguration: CursorConfiguration) {
        motionLoop.updateConfiguration(cursorConfiguration)
    }

    func beginLeftDrag() {
        motionLoop.beginLeftDrag()
    }

    func endLeftDrag() {
        motionLoop.endLeftDrag()
    }

    func releaseTransientState() {
        motionLoop.releaseTransientState()
    }

    func currentCursorPosition() -> CGPoint {
        motionLoop.currentCursorPosition()
    }

    func positionCursor(at point: CGPoint) {
        motionLoop.positionCursor(at: point)
    }

    func applyExternalDelta(_ delta: SIMD2<Double>) {
        motionLoop.applyExternalDelta(delta)
    }

    func performDiagnosticNudge() -> String {
        motionLoop.performDiagnosticNudge()
    }

    func performCrossEdgeSweep(_ direction: CrossEdgeDirection) -> String {
        motionLoop.performCrossEdgeSweep(direction)
    }
}

private final class MainActorMovementAccumulator: @unchecked Sendable {
    typealias Handler = @MainActor @Sendable (CGPoint, SIMD2<Double>) -> Bool
    typealias Fallback = @Sendable (SIMD2<Double>) -> Void

    private let lock = NSLock()
    private var handler: Handler?
    private var pendingLocation: CGPoint?
    private var pendingDelta = SIMD2<Double>.zero
    private var fallback: Fallback?
    private var deliveryScheduled = false

    @MainActor
    func setHandler(_ handler: Handler?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    var hasHandler: Bool {
        lock.lock()
        defer { lock.unlock() }
        return handler != nil
    }

    func submit(location: CGPoint, delta: SIMD2<Double>, fallback: @escaping Fallback) {
        lock.lock()
        if pendingLocation == nil {
            pendingLocation = location
        }
        pendingDelta += delta
        self.fallback = fallback
        guard !deliveryScheduled else {
            lock.unlock()
            return
        }
        deliveryScheduled = true
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.lock.lock()
            let handler = self.handler
            let location = self.pendingLocation
            let delta = self.pendingDelta
            let fallback = self.fallback
            self.pendingLocation = nil
            self.pendingDelta = .zero
            self.fallback = nil
            self.deliveryScheduled = false
            self.lock.unlock()

            guard let location else { return }
            let handled = MainActor.assumeIsolated {
                handler?(location, delta) ?? false
            }
            if !handled {
                fallback?(delta)
            }
        }
    }
}

private final class CursorMotionLoop: @unchecked Sendable {
    private static let outputIntervalNanoseconds = 8_333_333
    private static let diagnosticsInterval = 1.0 / 15.0

    private let queue = DispatchQueue(
        label: "com.vibe-controller.cursor-motion",
        qos: .userInteractive,
        autoreleaseFrequency: .workItem
    )
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let inputBridge: UniversalControlInputBridge
    private let eventSource = CGEventSource(stateID: .combinedSessionState)
    private let diagnosticsDelivery = MainActorLatestValue<CursorDiagnostics>()
    private let movementAccumulator = MainActorMovementAccumulator()

    private var timer: DispatchSourceTimer?
    private var diagnosticTimer: DispatchSourceTimer?
    private var diagnosticReportsRemaining = 0
    private var lastTickTime = ProcessInfo.processInfo.systemUptime
    private var lastDiagnosticsTime = 0.0
    private var lastDiagnosticsState: CursorActivityState?
    private var lastDiagnosticsMessage: String?
    private var leftStick = StickSnapshot()
    private var rightStick = StickSnapshot()
    private var pressedControls = Set<ControllerControlID>()
    private var cursorConfiguration = ControllerProfile.gabesDefaults.cursor
    private var smoothedVelocity = SIMD2<Double>.zero
    private var primaryFlickBoost = 1.0
    private var primaryFlickTracker = FlickBoostTracker()
    private var zoomRepeater = StickZoomRepeater()
    private var zoomStepHandler: CursorEngine.ZoomStepHandler?
    private var crossEdgeSweep: CrossEdgeSweep?
    private var lastKnownCursorPosition: CGPoint?
    private var lastSyntheticCursorUpdateTime = 0.0
    private var enabled = true
    private var accessibilityTrusted = false
    private var suspended = false
    private var draggingLeftMouse = false

    init(inputBridge: UniversalControlInputBridge) {
        self.inputBridge = inputBridge
        lastKnownCursorPosition = CGEvent(source: nil)?.location ?? .zero
        queue.setSpecific(key: queueKey, value: 1)
        queue.async { [weak self] in
            self?.startTimer()
        }
    }

    deinit {
        timer?.cancel()
        diagnosticTimer?.cancel()
    }

    @MainActor
    func setDiagnosticsHandler(_ handler: CursorEngine.DiagnosticsHandler?) {
        diagnosticsDelivery.setHandler(handler)
    }

    @MainActor
    func setMovementInterceptor(_ interceptor: CursorEngine.MovementInterceptor?) {
        movementAccumulator.setHandler(interceptor)
    }

    @MainActor
    func setZoomStepHandler(_ handler: CursorEngine.ZoomStepHandler?) {
        queue.async { [weak self] in
            self?.zoomStepHandler = handler
        }
    }

    func setEnabled(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.enabled = enabled
            self.lastTickTime = ProcessInfo.processInfo.systemUptime
            if !enabled {
                self.smoothedVelocity = .zero
                self.crossEdgeSweep = nil
                self.resetFlickState()
                self.zoomRepeater.reset()
                self.endLeftDragOnQueue()
            }
        }
    }

    func setAccessibilityTrusted(_ trusted: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.accessibilityTrusted = trusted
            self.lastTickTime = ProcessInfo.processInfo.systemUptime
            if !trusted {
                self.smoothedVelocity = .zero
                self.crossEdgeSweep = nil
                self.resetFlickState()
                self.zoomRepeater.reset()
                self.endLeftDragOnQueue()
            }
        }
    }

    func setSuspended(_ suspended: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.suspended = suspended
            self.lastTickTime = ProcessInfo.processInfo.systemUptime
            if suspended {
                self.smoothedVelocity = .zero
                self.crossEdgeSweep = nil
                self.resetFlickState()
                self.zoomRepeater.reset()
            }
        }
    }

    func updateInput(snapshot: ControllerSnapshot) {
        queue.async { [weak self] in
            guard let self else { return }
            self.leftStick = snapshot.leftStick
            self.rightStick = snapshot.rightStick
            self.pressedControls = snapshot.pressedControls
            if self.cursorConfiguration.zoomGestureEnabled,
               snapshot.pressedControls.contains(.buttonSouth),
               CursorMath.zoomGestureSample(stick: snapshot.leftStick) != nil {
                self.resetFlickState()
            } else {
                self.recordPrimaryStickChange(at: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    func updateConfiguration(_ configuration: CursorConfiguration) {
        queue.async { [weak self] in
            guard let self else { return }
            self.cursorConfiguration = configuration
            self.resetFlickState()
            self.zoomRepeater.reset()
            self.recordPrimaryStickChange(at: ProcessInfo.processInfo.systemUptime)
        }
    }

    var isDraggingLeftMouse: Bool {
        syncOnQueue { draggingLeftMouse }
    }

    func beginLeftDrag() {
        syncOnQueue {
            guard accessibilityTrusted, !draggingLeftMouse else { return }
            if inputBridge.postMouseButton(.left, isDown: true) {
                draggingLeftMouse = true
                return
            }
            let location = currentCursorPositionOnQueue()
            postMouseEvent(type: .leftMouseDown, location: location, button: .left)
            draggingLeftMouse = true
        }
    }

    func endLeftDrag() {
        syncOnQueue {
            endLeftDragOnQueue()
        }
    }

    func releaseTransientState() {
        syncOnQueue {
            endLeftDragOnQueue()
            smoothedVelocity = .zero
            crossEdgeSweep = nil
            leftStick = StickSnapshot()
            rightStick = StickSnapshot()
            pressedControls.removeAll()
            resetFlickState()
            zoomRepeater.reset()
            recordPrimaryStickChange(at: ProcessInfo.processInfo.systemUptime)
            lastTickTime = ProcessInfo.processInfo.systemUptime
        }
    }

    func currentCursorPosition() -> CGPoint {
        syncOnQueue {
            currentCursorPositionOnQueue()
        }
    }

    func positionCursor(at point: CGPoint) {
        syncOnQueue {
            guard enabled, accessibilityTrusted else { return }
            let target = clampedToVisibleScreens(point)
            recordSyntheticCursorPosition(target)
            let type: CGEventType = draggingLeftMouse ? .leftMouseDragged : .mouseMoved
            let warpResult = CGWarpMouseCursorPosition(target)
            postMouseEvent(type: type, location: target, button: .left)
            publishDiagnostics(
                state: .moving,
                velocity: .zero,
                location: target,
                message: warpResult == .success
                    ? "Positioning cursor for companion handoff."
                    : "Cursor warp failed: \(warpResult.rawValue)"
            )
        }
    }

    func applyExternalDelta(_ delta: SIMD2<Double>) {
        queue.async { [weak self] in
            guard let self, self.enabled, self.accessibilityTrusted else { return }
            self.moveCursor(by: delta, allowInterception: false)
        }
    }

    func performDiagnosticNudge() -> String {
        syncOnQueue {
            guard enabled else {
                publishDiagnostics(
                    state: .disabled,
                    velocity: .zero,
                    location: nil,
                    message: "Runtime disabled."
                )
                return "Runtime is disabled."
            }
            guard accessibilityTrusted else {
                publishDiagnostics(
                    state: .needsAccessibility,
                    velocity: .zero,
                    location: nil,
                    message: "Grant Accessibility to move the cursor."
                )
                return "Accessibility permission is not granted."
            }

            diagnosticTimer?.cancel()
            diagnosticReportsRemaining = 720
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now(),
                repeating: .nanoseconds(Self.outputIntervalNanoseconds),
                leeway: .microseconds(500)
            )
            timer.setEventHandler { [weak self] in
                self?.diagnosticTick()
            }
            diagnosticTimer = timer
            timer.resume()
            return "Running a six-second cross-Mac cursor sweep."
        }
    }

    func performCrossEdgeSweep(_ direction: CrossEdgeDirection) -> String {
        syncOnQueue {
            guard enabled else {
                publishDiagnostics(
                    state: .disabled,
                    velocity: .zero,
                    location: nil,
                    message: "Runtime disabled."
                )
                return "Runtime is disabled."
            }
            guard accessibilityTrusted else {
                publishDiagnostics(
                    state: .needsAccessibility,
                    velocity: .zero,
                    location: nil,
                    message: "Grant Accessibility to move the cursor."
                )
                return "Accessibility permission is not granted."
            }
            guard !suspended else {
                publishDiagnostics(
                    state: .idle,
                    velocity: .zero,
                    location: nil,
                    message: "Controller cursor control is suspended while Vibe Controller is frontmost."
                )
                return "Cursor control is suspended while Vibe Controller is frontmost."
            }
            guard inputBridge.isVirtualPointingReady else {
                publishDiagnostics(
                    state: .idle,
                    velocity: .zero,
                    location: nil,
                    message: "Virtual Hardware Support is required for edge crossing."
                )
                return "Virtual Hardware Support must be ready before crossing a Universal Control edge."
            }

            diagnosticTimer?.cancel()
            diagnosticTimer = nil
            diagnosticReportsRemaining = 0
            crossEdgeSweep = CrossEdgeSweep(direction: direction)
            smoothedVelocity = .zero
            resetFlickState()
            zoomRepeater.reset()
            lastTickTime = ProcessInfo.processInfo.systemUptime
            publishDiagnostics(
                state: .moving,
                velocity: direction.motionVector * CrossEdgeSweep.speed,
                location: nil,
                message: "Crossing the " + direction.displayName.lowercased()
                    + " Universal Control edge."
            )
            return "Crossing the " + direction.displayName.lowercased()
                + " Universal Control edge."
        }
    }

    func stop() {
        syncOnQueue {
            timer?.cancel()
            timer = nil
            diagnosticTimer?.cancel()
            diagnosticTimer = nil
            crossEdgeSweep = nil
            endLeftDragOnQueue()
        }
    }

    private func startTimer() {
        lastTickTime = ProcessInfo.processInfo.systemUptime
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now(),
            repeating: .nanoseconds(Self.outputIntervalNanoseconds),
            leeway: .microseconds(500)
        )
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let deltaTime = CursorMath.elapsedDuration(from: lastTickTime, to: now)
        lastTickTime = now
        guard deltaTime > 0 else { return }

        guard enabled, accessibilityTrusted else {
            smoothedVelocity = .zero
            crossEdgeSweep = nil
            resetFlickState()
            zoomRepeater.reset()
            if !accessibilityTrusted {
                endLeftDragOnQueue()
            }
            publishDiagnostics(
                state: enabled ? .needsAccessibility : .disabled,
                velocity: .zero,
                location: nil,
                message: enabled ? "Grant Accessibility to move the cursor." : "Runtime disabled."
            )
            return
        }

        guard !suspended else {
            smoothedVelocity = .zero
            crossEdgeSweep = nil
            resetFlickState()
            zoomRepeater.reset()
            publishDiagnostics(
                state: .idle,
                velocity: .zero,
                location: nil,
                message: "Controller cursor control is suspended while Vibe Controller is frontmost."
            )
            return
        }

        if var sweep = crossEdgeSweep {
            let velocity = sweep.direction.motionVector * CrossEdgeSweep.speed
            let frameDelta = sweep.nextDelta(elapsedTime: deltaTime)
            crossEdgeSweep = sweep.isComplete ? nil : sweep
            smoothedVelocity = velocity
            moveCursor(
                by: frameDelta,
                allowInterception: false,
                virtualOnly: true
            )
            if sweep.isComplete {
                smoothedVelocity = .zero
                publishDiagnostics(
                    state: .idle,
                    velocity: .zero,
                    location: nil,
                    message: "Completed the " + sweep.direction.displayName.lowercased()
                        + " edge crossing."
                )
            }
            return
        }

        if let zoomStep = zoomRepeater.update(
            stick: leftStick,
            modifierPressed: pressedControls.contains(.buttonSouth),
            enabled: cursorConfiguration.zoomGestureEnabled,
            at: now
        ) {
            deliverZoomStep(zoomStep)
        }
        let suppressLeftStick = zoomRepeater.isActive

        primaryFlickBoost = CursorMath.decayedFlickBoost(
            primaryFlickBoost,
            elapsedTime: deltaTime
        )
        let primaryVelocity = suppressLeftStick
            && cursorConfiguration.primaryStick.stickSide == .left
            ? .zero
            : velocity(
                for: cursorConfiguration.primaryStick,
                speed: cursorConfiguration.primarySpeed,
                speedMultiplier: primaryFlickBoost
            )
        let precisionVelocity = suppressLeftStick
            && cursorConfiguration.precisionStick.stickSide == .left
            ? .zero
            : velocity(
                for: cursorConfiguration.precisionStick,
                speed: cursorConfiguration.precisionSpeed
            )

        var combinedVelocity = primaryVelocity + precisionVelocity
        let activeMaxSpeed = max(
            cursorConfiguration.primaryStick == .off
                ? 0
                : cursorConfiguration.primarySpeed * primaryFlickBoost,
            cursorConfiguration.precisionStick == .off ? 0 : cursorConfiguration.precisionSpeed
        )
        if activeMaxSpeed > 0 {
            combinedVelocity = CursorMath.clampMagnitude(combinedVelocity, maxLength: activeMaxSpeed)
        }
        smoothedVelocity = suppressLeftStick
            ? combinedVelocity
            : CursorMath.blend(
                current: smoothedVelocity,
                target: combinedVelocity,
                smoothing: cursorConfiguration.smoothing,
                elapsedTime: deltaTime
            )

        guard simd_length(smoothedVelocity) >= 0.01 else {
            smoothedVelocity = .zero
            publishDiagnostics(
                state: .idle,
                velocity: smoothedVelocity,
                location: nil,
                message: suppressLeftStick
                    ? "A + left stick zoom is active."
                    : "Stick input is below the active threshold."
            )
            return
        }

        let frameDelta = smoothedVelocity * deltaTime
        moveCursor(by: frameDelta, allowInterception: true)
    }

    private func deliverZoomStep(_ direction: StickZoomDirection) {
        guard let zoomStepHandler else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                zoomStepHandler(direction)
            }
        }
    }

    private func velocity(
        for assignment: StickAssignment,
        speed: Double,
        speedMultiplier: Double = 1
    ) -> SIMD2<Double> {
        guard let stickSide = assignment.stickSide else { return .zero }
        let stick = stickSide == .left ? leftStick : rightStick

        let adjusted = CursorMath.adjustedVector(
            x: stick.x,
            y: stick.y,
            deadZone: cursorConfiguration.deadZone,
            responseCurve: cursorConfiguration.responseCurve
        )
        guard adjusted != .zero else { return .zero }

        let invertX = stickSide == .left
            ? cursorConfiguration.invertPrimaryX
            : cursorConfiguration.invertPrecisionX
        let invertY = stickSide == .left
            ? cursorConfiguration.invertPrimaryY
            : cursorConfiguration.invertPrecisionY

        var direction = SIMD2<Double>(adjusted.x, -adjusted.y)
        if invertX { direction.x *= -1 }
        if invertY { direction.y *= -1 }
        direction.x *= cursorConfiguration.horizontalSpeedMultiplier
        direction.y *= cursorConfiguration.verticalSpeedMultiplier

        var velocity = direction * speed * speedMultiplier
        if cursorConfiguration.accelerationEnabled {
            let magnitude = simd_length(adjusted)
            velocity *= (1.0 + (magnitude * magnitude * 0.35))
        }
        return velocity
    }

    private func recordPrimaryStickChange(at currentTime: Double) {
        guard cursorConfiguration.flickBoostEnabled else {
            resetFlickState()
            return
        }
        guard let stickSide = cursorConfiguration.primaryStick.stickSide else {
            resetFlickState()
            return
        }

        let stick = stickSide == .left ? leftStick : rightStick
        let current = SIMD2<Double>(stick.x, stick.y)
        if simd_length(current) <= cursorConfiguration.deadZone {
            primaryFlickBoost = 1
        }
        let detectedBoost = primaryFlickTracker.update(vector: current, at: currentTime)
        primaryFlickBoost = max(primaryFlickBoost, detectedBoost)
    }

    private func resetFlickState() {
        primaryFlickBoost = 1
        primaryFlickTracker.reset()
    }

    private func moveCursor(
        by delta: SIMD2<Double>,
        allowInterception: Bool,
        virtualOnly: Bool = false
    ) {
        if allowInterception, movementAccumulator.hasHandler {
            let currentPosition = currentCursorPositionOnQueue()
            movementAccumulator.submit(
                location: currentPosition,
                delta: delta,
                fallback: { [weak self] accumulatedDelta in
                    self?.queue.async { [weak self] in
                        self?.moveCursor(by: accumulatedDelta, allowInterception: false)
                    }
                }
            )
            publishDiagnostics(
                state: .moving,
                velocity: smoothedVelocity,
                location: currentPosition,
                message: "Routing cursor movement through the companion path."
            )
            return
        }

        if virtualOnly {
            guard inputBridge.postVirtualRelativePointer(delta: delta) else {
                crossEdgeSweep = nil
                smoothedVelocity = .zero
                publishDiagnostics(
                    state: .idle,
                    velocity: .zero,
                    location: nil,
                    message: "Virtual Hardware Support stopped before the edge crossing completed."
                )
                return
            }
            publishDiagnostics(
                state: .moving,
                velocity: smoothedVelocity,
                location: nil,
                message: "Posting edge-crossing movement through virtual hardware."
            )
            return
        }

        if inputBridge.postRelativePointer(delta: delta) {
            publishDiagnostics(
                state: .moving,
                velocity: smoothedVelocity,
                location: nil,
                message: inputBridge.isVirtualPointingReady
                    ? "Posting virtual hardware movement through Universal Control."
                    : "Posting legacy relative movement on this Mac."
            )
            return
        }

        let currentPosition = currentCursorPositionOnQueue()
        let unclamped = CGPoint(x: currentPosition.x + delta.x, y: currentPosition.y + delta.y)
        let target = clampedToVisibleScreens(unclamped)
        recordSyntheticCursorPosition(target)
        let type: CGEventType = draggingLeftMouse ? .leftMouseDragged : .mouseMoved
        let warpResult = CGWarpMouseCursorPosition(target)
        postMouseEvent(type: type, location: target, button: .left)
        publishDiagnostics(
            state: .moving,
            velocity: smoothedVelocity,
            location: target,
            message: warpResult == .success
                ? "Posting cursor movement."
                : "Cursor warp failed: \(warpResult.rawValue)"
        )
    }

    private func endLeftDragOnQueue() {
        guard draggingLeftMouse else { return }
        if inputBridge.postMouseButton(.left, isDown: false) {
            draggingLeftMouse = false
            return
        }
        let location = currentCursorPositionOnQueue()
        postMouseEvent(type: .leftMouseUp, location: location, button: .left)
        draggingLeftMouse = false
    }

    private func currentCursorPositionOnQueue() -> CGPoint {
        synchronizeCursorPositionFromSystemIfNeeded()
        return lastKnownCursorPosition ?? .zero
    }

    private func clampedToVisibleScreens(_ point: CGPoint) -> CGPoint {
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displays, &displayCount)
        let union = displays.reduce(into: CGRect.null) { result, displayID in
            result = result.union(CGDisplayBounds(displayID))
        }
        guard !union.isNull else { return point }
        return CGPoint(
            x: min(max(point.x, union.minX), union.maxX - 1),
            y: min(max(point.y, union.minY), union.maxY - 1)
        )
    }

    private func postMouseEvent(type: CGEventType, location: CGPoint, button: CGMouseButton) {
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func recordSyntheticCursorPosition(_ point: CGPoint) {
        lastKnownCursorPosition = point
        lastSyntheticCursorUpdateTime = ProcessInfo.processInfo.systemUptime
    }

    private func synchronizeCursorPositionFromSystemIfNeeded() {
        guard let systemLocation = CGEvent(source: nil)?.location else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let recentlyMovedSynthhetically = (now - lastSyntheticCursorUpdateTime) < 0.15
        if lastKnownCursorPosition == nil || !recentlyMovedSynthhetically {
            lastKnownCursorPosition = systemLocation
        }
    }

    private func diagnosticTick() {
        guard diagnosticReportsRemaining > 0 else {
            diagnosticTimer?.cancel()
            diagnosticTimer = nil
            publishDiagnostics(
                state: .idle,
                velocity: .zero,
                location: nil,
                message: "Completed the six-second cross-Mac cursor sweep."
            )
            return
        }
        moveCursor(by: SIMD2<Double>(3, 0), allowInterception: true)
        diagnosticReportsRemaining -= 1
    }

    private func publishDiagnostics(
        state: CursorActivityState,
        velocity: SIMD2<Double>,
        location: CGPoint?,
        message: String
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        guard state != lastDiagnosticsState || message != lastDiagnosticsMessage else {
            return
        }
        guard lastDiagnosticsTime == 0 || now - lastDiagnosticsTime >= Self.diagnosticsInterval else {
            return
        }
        lastDiagnosticsTime = now
        lastDiagnosticsState = state
        lastDiagnosticsMessage = message
        diagnosticsDelivery.submit(
            CursorDiagnostics(
                state: state,
                velocityX: velocity.x,
                velocityY: velocity.y,
                lastPostedAt: state == .moving ? Date() : nil,
                lastPostedLocation: location,
                message: message
            )
        )
    }

    private func syncOnQueue<T>(_ operation: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return operation()
        }
        return queue.sync(execute: operation)
    }
}
