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
final class CursorEngine {
    private var timer: DispatchSourceTimer?
    private var lastTickTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var leftStick = StickSnapshot()
    private var rightStick = StickSnapshot()
    private var cursorConfiguration = ControllerProfile.desktopControl.cursor
    private var smoothedVelocity = SIMD2<Double>.zero
    private let eventSource = CGEventSource(stateID: .combinedSessionState)

    private(set) var isDraggingLeftMouse = false
    var isEnabled = true
    var accessibilityTrusted = false
    var suspendControllerMotion = false
    var onDiagnostics: ((CursorDiagnostics) -> Void)?

    init() {
        startTimer()
    }

    deinit {
        timer?.cancel()
    }

    func update(snapshot: ControllerSnapshot, cursorConfiguration: CursorConfiguration) {
        self.leftStick = snapshot.leftStick
        self.rightStick = snapshot.rightStick
        self.cursorConfiguration = cursorConfiguration
    }

    func beginLeftDrag() {
        guard accessibilityTrusted, !isDraggingLeftMouse else { return }
        let location = currentCursorPosition()
        postMouseEvent(type: .leftMouseDown, location: location, button: .left)
        isDraggingLeftMouse = true
    }

    func endLeftDrag() {
        guard isDraggingLeftMouse else { return }
        let location = currentCursorPosition()
        postMouseEvent(type: .leftMouseUp, location: location, button: .left)
        isDraggingLeftMouse = false
    }

    func releaseTransientState() {
        endLeftDrag()
        smoothedVelocity = .zero
    }

    func currentCursorPosition() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    private func tick() {
        let now = CFAbsoluteTimeGetCurrent()
        let deltaTime = max(1.0 / 240.0, min(now - lastTickTime, 1.0 / 30.0))
        lastTickTime = now

        guard isEnabled, accessibilityTrusted else {
            smoothedVelocity = .zero
            if !accessibilityTrusted {
                endLeftDrag()
            }
            publishDiagnostics(
                state: isEnabled ? .needsAccessibility : .disabled,
                velocity: .zero,
                location: nil,
                message: isEnabled ? "Grant Accessibility to move the cursor." : "Runtime disabled."
            )
            return
        }

        guard !suspendControllerMotion else {
            smoothedVelocity = .zero
            publishDiagnostics(
                state: .idle,
                velocity: .zero,
                location: nil,
                message: "Controller cursor control is suspended while Vibe Controller is frontmost."
            )
            return
        }

        let primaryVelocity = velocity(for: cursorConfiguration.primaryStick, speed: cursorConfiguration.primarySpeed)
        let precisionVelocity = velocity(for: cursorConfiguration.precisionStick, speed: cursorConfiguration.precisionSpeed)

        var combinedVelocity = primaryVelocity + precisionVelocity
        let activeMaxSpeed = max(
            cursorConfiguration.primaryStick == .off ? 0 : cursorConfiguration.primarySpeed,
            cursorConfiguration.precisionStick == .off ? 0 : cursorConfiguration.precisionSpeed
        )
        if activeMaxSpeed > 0 {
            combinedVelocity = CursorMath.clampMagnitude(combinedVelocity, maxLength: activeMaxSpeed)
        }
        smoothedVelocity = CursorMath.blend(
            current: smoothedVelocity,
            target: combinedVelocity,
            smoothing: cursorConfiguration.smoothing
        )

        let frameDelta = smoothedVelocity * deltaTime
        guard simd_length(frameDelta) >= 0.05 else {
            publishDiagnostics(
                state: .idle,
                velocity: smoothedVelocity,
                location: nil,
                message: "Stick input is below the active threshold."
            )
            return
        }

        moveCursor(by: frameDelta)
    }

    private func velocity(for assignment: StickAssignment, speed: Double) -> SIMD2<Double> {
        guard let stickSide = assignment.stickSide else { return .zero }
        let stick = stickSide == .left ? leftStick : rightStick

        let adjusted = CursorMath.adjustedVector(
            x: stick.x,
            y: stick.y,
            deadZone: cursorConfiguration.deadZone,
            responseCurve: cursorConfiguration.responseCurve
        )
        guard adjusted != .zero else { return .zero }

        let invertX = stickSide == .left ? cursorConfiguration.invertPrimaryX : cursorConfiguration.invertPrecisionX
        let invertY = stickSide == .left ? cursorConfiguration.invertPrimaryY : cursorConfiguration.invertPrecisionY

        // Game Controller stick Y and Quartz cursor Y do not share the same
        // "up" direction, so normalize to desktop-style cursor motion first.
        var direction = SIMD2<Double>(adjusted.x, -adjusted.y)
        if invertX {
            direction.x *= -1
        }
        if invertY {
            direction.y *= -1
        }

        direction.x *= cursorConfiguration.horizontalSpeedMultiplier
        direction.y *= cursorConfiguration.verticalSpeedMultiplier

        var velocity = direction * speed
        if cursorConfiguration.accelerationEnabled {
            let magnitude = simd_length(adjusted)
            velocity *= (1.0 + (magnitude * magnitude * 0.35))
        }

        return velocity
    }

    private func moveCursor(by delta: SIMD2<Double>) {
        let currentPosition = currentCursorPosition()
        let unclamped = CGPoint(x: currentPosition.x + delta.x, y: currentPosition.y + delta.y)
        let target = clampedToVisibleScreens(unclamped)
        let type: CGEventType = isDraggingLeftMouse ? .leftMouseDragged : .mouseMoved
        let warpResult = CGWarpMouseCursorPosition(target)
        postMouseEvent(type: type, location: target, button: .left)
        publishDiagnostics(
            state: .moving,
            velocity: smoothedVelocity,
            location: target,
            message: warpResult == .success ? "Posting cursor movement." : "Cursor warp failed: \(warpResult.rawValue)"
        )
    }

    private func clampedToVisibleScreens(_ point: CGPoint) -> CGPoint {
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displays, &displayCount)
        let union = displays.reduce(into: CGRect.null) { result, displayID in
            result = result.union(CGDisplayBounds(displayID))
        }
        guard union.isNull == false else { return point }
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
        ) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }

    func performDiagnosticNudge() -> String {
        guard isEnabled else {
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

        moveCursor(by: SIMD2<Double>(140, 90))
        return "Sent a test cursor nudge."
    }

    private func publishDiagnostics(
        state: CursorActivityState,
        velocity: SIMD2<Double>,
        location: CGPoint?,
        message: String
    ) {
        onDiagnostics?(
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
}
