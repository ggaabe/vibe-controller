import CoreGraphics
import Foundation

@MainActor
final class ActionEngine {
    var isEnabled = true
    var accessibilityTrusted = false
    var suspendActionExecution = false
    var onToggleCursorSpeeds: (() -> Void)?
    var companionDispatch: ((CompanionControlEvent) -> Bool)?

    private let cursorEngine: CursorEngine
    private let eventSource = CGEventSource(stateID: .combinedSessionState)
    private var previousPressedControls = Set<ControllerControlID>()
    private var activeStates: [ControllerControlID: ActiveControlState] = [:]

    init(cursorEngine: CursorEngine) {
        self.cursorEngine = cursorEngine
    }

    func process(snapshot: ControllerSnapshot, profile: ControllerProfile) {
        let actuatedControls = Set(
            profile.mappings.keys.filter { isControlActuated($0, snapshot: snapshot) }
        )

        guard isEnabled, accessibilityTrusted else {
            cancelAll()
            previousPressedControls = actuatedControls
            return
        }

        guard !suspendActionExecution else {
            cancelAll()
            previousPressedControls = actuatedControls
            return
        }

        for (control, mapping) in profile.mappings where mapping.actionType != .none {
            let isPressed = actuatedControls.contains(control)
            let wasPressed = previousPressedControls.contains(control)

            if isPressed && !wasPressed {
                handlePress(for: control, mapping: mapping)
            } else if !isPressed && wasPressed {
                handleRelease(for: control, mapping: mapping)
            }
        }

        previousPressedControls = actuatedControls
    }

    func cancelAll() {
        for (control, state) in activeStates {
            state.timer?.cancel()
            if state.isHoldingShortcut, let shortcut = state.shortcut {
                postShortcutUp(shortcut)
            }
            if state.isDragging {
                cursorEngine.endLeftDrag()
            }
            activeStates[control] = nil
        }
        previousPressedControls.removeAll()
    }

    private func isControlActuated(_ control: ControllerControlID, snapshot: ControllerSnapshot) -> Bool {
        switch control {
        case .leftTrigger, .rightTrigger:
            return snapshot.value(for: control) >= 0.18
        default:
            return snapshot.pressedControls.contains(control)
        }
    }

    private func handlePress(for control: ControllerControlID, mapping: ControllerActionMapping) {
        switch mapping.triggerMode {
        case .tap:
            fireDiscreteAction(mapping)
        case .holdWhilePressed:
            beginHoldAction(for: control, mapping: mapping)
        case .repeatWhileHeld:
            beginRepeatingAction(for: control, mapping: mapping)
        case .toggle:
            toggleAction(for: control, mapping: mapping)
        }
    }

    private func handleRelease(for control: ControllerControlID, mapping: ControllerActionMapping) {
        switch mapping.triggerMode {
        case .tap, .toggle:
            break
        case .holdWhilePressed:
            endHoldAction(for: control)
        case .repeatWhileHeld:
            activeStates[control]?.timer?.cancel()
            activeStates[control]?.timer = nil
        }
    }

    private func beginHoldAction(for control: ControllerControlID, mapping: ControllerActionMapping) {
        switch mapping.actionType {
        case .keyboardShortcut:
            guard let shortcut = mapping.shortcut else { return }
            if dispatchToCompanion(.shortcut(shortcut, phase: .down)) {
                activeStates[control] = ActiveControlState(
                    shortcut: shortcut,
                    isHoldingShortcut: true,
                    isDragging: false,
                    isToggledOn: false,
                    timer: nil
                )
                return
            }
            postShortcutDown(shortcut)
            activeStates[control] = ActiveControlState(
                shortcut: shortcut,
                isHoldingShortcut: true,
                isDragging: false,
                isToggledOn: false,
                timer: nil
            )
        case .leftMouseHold:
            if dispatchToCompanion(.mouse(button: .left, phase: .down)) {
                activeStates[control] = ActiveControlState(
                    shortcut: nil,
                    isHoldingShortcut: false,
                    isDragging: true,
                    isToggledOn: false,
                    timer: nil
                )
                return
            }
            cursorEngine.beginLeftDrag()
            activeStates[control] = ActiveControlState(
                shortcut: nil,
                isHoldingShortcut: false,
                isDragging: true,
                isToggledOn: false,
                timer: nil
            )
        default:
            fireDiscreteAction(mapping)
        }
    }

    private func endHoldAction(for control: ControllerControlID) {
        guard let state = activeStates[control] else { return }
        if state.isHoldingShortcut, let shortcut = state.shortcut {
            if !dispatchToCompanion(.shortcut(shortcut, phase: .up)) {
                postShortcutUp(shortcut)
            }
        }
        if state.isDragging {
            if !dispatchToCompanion(.mouse(button: .left, phase: .up)) {
                cursorEngine.endLeftDrag()
            }
        }
        activeStates[control] = nil
    }

    private func beginRepeatingAction(for control: ControllerControlID, mapping: ControllerActionMapping) {
        activeStates[control]?.timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + max(0.01, mapping.repeatDelay),
            repeating: max(0.01, mapping.repeatInterval)
        )
        timer.setEventHandler { [weak self] in
            self?.fireDiscreteAction(mapping)
        }
        timer.resume()
        activeStates[control] = ActiveControlState(
            shortcut: nil,
            isHoldingShortcut: false,
            isDragging: false,
            isToggledOn: false,
            timer: timer
        )

        if !mapping.actionType.isContinuousRepeatPreferred {
            fireDiscreteAction(mapping)
        }
    }

    private func toggleAction(for control: ControllerControlID, mapping: ControllerActionMapping) {
        let isOn = activeStates[control]?.isToggledOn ?? false
        if isOn {
            if mapping.actionType == .leftMouseHold {
                if !dispatchToCompanion(.mouse(button: .left, phase: .up)) {
                    cursorEngine.endLeftDrag()
                }
            } else if mapping.actionType == .keyboardShortcut, let shortcut = activeStates[control]?.shortcut {
                if !dispatchToCompanion(.shortcut(shortcut, phase: .up)) {
                    postShortcutUp(shortcut)
                }
            }
            activeStates[control] = nil
            return
        }

        switch mapping.actionType {
        case .leftMouseHold:
            if dispatchToCompanion(.mouse(button: .left, phase: .down)) {
                activeStates[control] = ActiveControlState(
                    shortcut: nil,
                    isHoldingShortcut: false,
                    isDragging: true,
                    isToggledOn: true,
                    timer: nil
                )
                return
            }
            cursorEngine.beginLeftDrag()
            activeStates[control] = ActiveControlState(
                shortcut: nil,
                isHoldingShortcut: false,
                isDragging: true,
                isToggledOn: true,
                timer: nil
            )
        case .keyboardShortcut:
            guard let shortcut = mapping.shortcut else { return }
            if dispatchToCompanion(.shortcut(shortcut, phase: .down)) {
                activeStates[control] = ActiveControlState(
                    shortcut: shortcut,
                    isHoldingShortcut: true,
                    isDragging: false,
                    isToggledOn: true,
                    timer: nil
                )
                return
            }
            postShortcutDown(shortcut)
            activeStates[control] = ActiveControlState(
                shortcut: shortcut,
                isHoldingShortcut: true,
                isDragging: false,
                isToggledOn: true,
                timer: nil
            )
        default:
            fireDiscreteAction(mapping)
        }
    }

    private func fireDiscreteAction(_ mapping: ControllerActionMapping) {
        switch mapping.actionType {
        case .none:
            return
        case .keyboardShortcut:
            guard let shortcut = mapping.shortcut else { return }
            if dispatchToCompanion(.shortcut(shortcut, phase: .tap)) {
                return
            }
            postShortcutTap(shortcut)
        case .leftClick:
            if dispatchToCompanion(.mouse(button: .left, phase: .click)) {
                return
            }
            postMouseClick(button: .left)
        case .rightClick:
            if dispatchToCompanion(.mouse(button: .right, phase: .click)) {
                return
            }
            postMouseClick(button: .right)
        case .middleClick:
            if dispatchToCompanion(.mouse(button: .middle, phase: .click)) {
                return
            }
            postMouseClick(button: .center)
        case .leftMouseHold:
            if dispatchToCompanion(.mouse(button: .left, phase: .down)) {
                return
            }
            cursorEngine.beginLeftDrag()
        case .doubleClick:
            if dispatchToCompanion(.mouse(button: .left, phase: .doubleClick)) {
                return
            }
            postDoubleClick()
        case .scrollUp:
            if dispatchToCompanion(.scroll(vertical: 1, horizontal: 0)) {
                return
            }
            postScroll(vertical: 1, horizontal: 0)
        case .scrollDown:
            if dispatchToCompanion(.scroll(vertical: -1, horizontal: 0)) {
                return
            }
            postScroll(vertical: -1, horizontal: 0)
        case .scrollLeft:
            if dispatchToCompanion(.scroll(vertical: 0, horizontal: -1)) {
                return
            }
            postScroll(vertical: 0, horizontal: -1)
        case .scrollRight:
            if dispatchToCompanion(.scroll(vertical: 0, horizontal: 1)) {
                return
            }
            postScroll(vertical: 0, horizontal: 1)
        case .switchSpaceLeft:
            if dispatchToCompanion(.spaceSwitch(.left)) {
                return
            }
            triggerSpaceSwitch(.left)
        case .switchSpaceRight:
            if dispatchToCompanion(.spaceSwitch(.right)) {
                return
            }
            triggerSpaceSwitch(.right)
        case .toggleCursorSpeeds:
            onToggleCursorSpeeds?()
        }
    }

    private func postShortcutTap(_ shortcut: ShortcutDescriptor) {
        postShortcutDown(shortcut)
        postShortcutUp(shortcut)
    }

    private func postShortcutDown(_ shortcut: ShortcutDescriptor) {
        var activeFlags = CGEventFlags()
        for modifier in shortcut.orderedModifiers {
            activeFlags.insert(modifier.cgEventFlag)
            guard let event = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: modifier.keyCode,
                keyDown: true
            ) else { continue }
            event.flags = activeFlags
            event.post(tap: CGEventTapLocation.cghidEventTap)
        }

        guard let keyDown = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: CGKeyCode(shortcut.keyCode),
                keyDown: true
            ) else {
            return
        }
        keyDown.flags = shortcut.eventFlags
        keyDown.post(tap: CGEventTapLocation.cghidEventTap)
    }

    private func postShortcutUp(_ shortcut: ShortcutDescriptor) {
        guard let keyUp = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: CGKeyCode(shortcut.keyCode),
                keyDown: false
        ) else {
            return
        }
        keyUp.flags = shortcut.eventFlags
        keyUp.post(tap: CGEventTapLocation.cghidEventTap)

        var released = shortcut.orderedModifiers.cgEventFlags
        for modifier in shortcut.orderedModifiers.reversed() {
            released.remove(modifier.cgEventFlag)
            guard let event = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: modifier.keyCode,
                keyDown: false
            ) else { continue }
            event.flags = released
            event.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    private func postMouseClick(button: CGMouseButton) {
        let location = cursorEngine.currentCursorPosition()
        let downType: CGEventType
        let upType: CGEventType

        switch button {
        case .left:
            downType = .leftMouseDown
            upType = .leftMouseUp
        case .right:
            downType = .rightMouseDown
            upType = .rightMouseUp
        default:
            downType = .otherMouseDown
            upType = .otherMouseUp
        }

        if let down = CGEvent(mouseEventSource: eventSource, mouseType: downType, mouseCursorPosition: location, mouseButton: button),
           let up = CGEvent(mouseEventSource: eventSource, mouseType: upType, mouseCursorPosition: location, mouseButton: button) {
            down.post(tap: CGEventTapLocation.cghidEventTap)
            up.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    private func postDoubleClick() {
        let location = cursorEngine.currentCursorPosition()
        for clickState in [1, 2] {
            guard let down = CGEvent(
                mouseEventSource: eventSource,
                mouseType: .leftMouseDown,
                mouseCursorPosition: location,
                mouseButton: .left
            ), let up = CGEvent(
                mouseEventSource: eventSource,
                mouseType: .leftMouseUp,
                mouseCursorPosition: location,
                mouseButton: .left
            ) else {
                continue
            }
            down.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
            up.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
            down.post(tap: CGEventTapLocation.cghidEventTap)
            up.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    private func postScroll(vertical: Int32, horizontal: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .line,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        ) else {
            return
        }
        event.post(tap: CGEventTapLocation.cghidEventTap)
    }

    func performCompanionEvent(_ event: CompanionControlEvent) {
        guard isEnabled, accessibilityTrusted else { return }
        switch event.payload {
        case .mouse(let button, let phase):
            performCompanionMouse(button: button, phase: phase)
        case .scroll(let vertical, let horizontal):
            postScroll(vertical: vertical, horizontal: horizontal)
        case .shortcut(let shortcut, let phase):
            switch phase {
            case .tap:
                postShortcutTap(shortcut)
            case .down:
                postShortcutDown(shortcut)
            case .up:
                postShortcutUp(shortcut)
            }
        case .spaceSwitch(let direction):
            triggerSpaceSwitch(direction)
        }
    }

    private func performCompanionMouse(button: CompanionMouseButton, phase: CompanionMousePhase) {
        switch (button, phase) {
        case (.left, .down):
            cursorEngine.beginLeftDrag()
        case (.left, .up):
            cursorEngine.endLeftDrag()
        case (.left, .click):
            postMouseClick(button: .left)
        case (.right, .click):
            postMouseClick(button: .right)
        case (.middle, .click):
            postMouseClick(button: .center)
        case (.left, .doubleClick):
            postDoubleClick()
        case (.right, .doubleClick), (.middle, .doubleClick), (_, .down), (_, .up):
            break
        }
    }

    private func dispatchToCompanion(_ payload: CompanionControlEvent.Payload) -> Bool {
        companionDispatch?(CompanionControlEvent(payload: payload)) ?? false
    }

    private func triggerSpaceSwitch(_ direction: SpaceSwitchDirection) {
        let keyCode: Int = direction == .left ? 123 : 124
        let scriptSource = """
        tell application "System Events"
            key code \(keyCode) using control down
        end tell
        """

        if let script = NSAppleScript(source: scriptSource) {
            var scriptError: NSDictionary?
            script.executeAndReturnError(&scriptError)
            if scriptError == nil {
                return
            }
        }

        let fallback = ShortcutDescriptor(
            keyCode: UInt16(keyCode),
            modifiers: [.control]
        )
        postShortcutTap(fallback)
    }
}

private extension ShortcutDescriptor {
    var eventFlags: CGEventFlags {
        var flags = orderedModifiers.cgEventFlags
        if isFunctionKeyShortcut {
            flags.insert(.maskSecondaryFn)
        }
        return flags
    }
}

private struct ActiveControlState {
    var shortcut: ShortcutDescriptor?
    var isHoldingShortcut: Bool
    var isDragging: Bool
    var isToggledOn: Bool
    var timer: DispatchSourceTimer?
}

private extension KeyboardModifier {
    var cgEventFlag: CGEventFlags {
        switch self {
        case .control:
            return .maskControl
        case .option:
            return .maskAlternate
        case .shift:
            return .maskShift
        case .command:
            return .maskCommand
        }
    }
}

private extension Array where Element == KeyboardModifier {
    var cgEventFlags: CGEventFlags {
        reduce(into: CGEventFlags()) { flags, modifier in
            flags.insert(modifier.cgEventFlag)
        }
    }
}

private extension ActionType {
    var isContinuousRepeatPreferred: Bool {
        switch self {
        case .scrollUp, .scrollDown, .scrollLeft, .scrollRight:
            return true
        default:
            return false
        }
    }
}
