import CoreGraphics
import Foundation

@MainActor
final class ActionEngine {
    private static let zoomInShortcut = ShortcutDescriptor(
        keyCode: 24,
        modifiers: [.shift, .command]
    )
    private static let zoomOutShortcut = ShortcutDescriptor(
        keyCode: 27,
        modifiers: [.command]
    )

    private struct RecentTap {
        let mapping: ControllerActionMapping
        let sourceModifier: ControllerControlID?
        let timestamp: TimeInterval
    }

    /// Filters the sub-frame release/press chatter some USB gamepads emit for
    /// a single physical tap without making normal double-taps feel sluggish.
    private static let duplicateTapInterval: TimeInterval = 0.08

    var isEnabled = true
    var accessibilityTrusted = false
    var suspendActionExecution = false
    var onToggleCursorSpeeds: (() -> Void)?
    var onCrossEdgeSweep: ((CrossEdgeDirection) -> Void)?
    var onActionStatus: ((String) -> Void)?
    var companionDispatch: ((CompanionControlEvent) -> Bool)?

    private let cursorEngine: CursorEngine
    private let currentTime: () -> TimeInterval
    private let eventSource = CGEventSource(stateID: .combinedSessionState)
    private var previousPressedControls = Set<ControllerControlID>()
    private var activeStates: [ControllerControlID: ActiveControlState] = [:]
    private var armedModifierControls = Set<ControllerControlID>()
    private var consumedModifierControls = Set<ControllerControlID>()
    private var modifierPressOrder: [ControllerControlID] = []
    private var recentTaps: [ControllerControlID: RecentTap] = [:]

    init(
        cursorEngine: CursorEngine,
        currentTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.cursorEngine = cursorEngine
        self.currentTime = currentTime
    }

    func process(snapshot: ControllerSnapshot, profile: ControllerProfile) {
        let actuatedControls = Set(
            ControllerControlID.mappingControls.filter { isControlActuated($0, snapshot: snapshot) }
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

        let newlyReleased = previousPressedControls.subtracting(actuatedControls)
        for control in ControllerControlID.mappingControls where newlyReleased.contains(control) {
            if armedModifierControls.contains(control) {
                releaseModifier(control, profile: profile)
            } else {
                handleRelease(for: control)
            }
        }

        let newlyPressed = actuatedControls.subtracting(previousPressedControls)
        var modifierControls = profile.modifierLayers.map(\.modifierControl)
        if profile.cursor.zoomGestureEnabled,
           !modifierControls.contains(.buttonSouth) {
            modifierControls.append(.buttonSouth)
        }
        var handledPresses = Set<ControllerControlID>()

        // Arm modifiers before resolving other buttons so a single controller
        // snapshot containing both sides of a chord still activates the layer.
        for modifierControl in modifierControls where newlyPressed.contains(modifierControl) {
            if let activeModifier = activeModifierControl(in: actuatedControls) {
                press(
                    modifierControl,
                    profile: profile,
                    modifierControl: activeModifier
                )
            } else {
                armModifier(modifierControl)
            }
            handledPresses.insert(modifierControl)
        }

        if profile.cursor.zoomGestureEnabled,
           actuatedControls.contains(.buttonSouth),
           let direction = CursorMath.zoomGestureSample(stick: snapshot.leftStick)?.direction {
            consumedModifierControls.insert(.buttonSouth)
            onActionStatus?("A + Left Stick: \(direction.displayName)")
        }

        for control in ControllerControlID.mappingControls
        where newlyPressed.contains(control) && !handledPresses.contains(control) {
            press(
                control,
                profile: profile,
                modifierControl: activeModifierControl(in: actuatedControls)
            )
        }

        previousPressedControls = actuatedControls
    }

    func performZoomStep(_ direction: StickZoomDirection) {
        guard isEnabled, accessibilityTrusted, !suspendActionExecution else { return }
        let shortcut = direction == .zoomIn
            ? Self.zoomInShortcut
            : Self.zoomOutShortcut
        if dispatchToCompanion(.shortcut(shortcut, phase: .tap)) {
            return
        }
        postShortcutTap(shortcut)
    }

    func cancelAll() {
        for control in Array(activeStates.keys) {
            finishActiveState(for: control)
        }
        armedModifierControls.removeAll()
        consumedModifierControls.removeAll()
        modifierPressOrder.removeAll()
        previousPressedControls.removeAll()
        recentTaps.removeAll()
    }

    private func isControlActuated(_ control: ControllerControlID, snapshot: ControllerSnapshot) -> Bool {
        switch control {
        case .leftTrigger, .rightTrigger:
            return snapshot.value(for: control) >= 0.18
        default:
            return snapshot.pressedControls.contains(control)
        }
    }

    private func armModifier(_ control: ControllerControlID) {
        armedModifierControls.insert(control)
        modifierPressOrder.removeAll(where: { $0 == control })
        modifierPressOrder.append(control)
    }

    private func activeModifierControl(
        in actuatedControls: Set<ControllerControlID>
    ) -> ControllerControlID? {
        modifierPressOrder.reversed().first {
            armedModifierControls.contains($0) && actuatedControls.contains($0)
        }
    }

    private func press(
        _ control: ControllerControlID,
        profile: ControllerProfile,
        modifierControl: ControllerControlID?
    ) {
        if let modifierControl {
            consumedModifierControls.insert(modifierControl)
        }
        let mapping = profile.effectiveMapping(
            for: control,
            modifierControl: modifierControl
        )
        if mapping.triggerMode == .tap,
           suppressDuplicateTap(
               for: control,
               mapping: mapping,
               sourceModifier: modifierControl
           ) {
            return
        }
        handlePress(
            for: control,
            mapping: mapping,
            sourceModifier: modifierControl
        )
    }

    private func suppressDuplicateTap(
        for control: ControllerControlID,
        mapping: ControllerActionMapping,
        sourceModifier: ControllerControlID?
    ) -> Bool {
        let now = currentTime()
        defer {
            recentTaps[control] = RecentTap(
                mapping: mapping,
                sourceModifier: sourceModifier,
                timestamp: now
            )
        }
        guard let previous = recentTaps[control],
              previous.mapping == mapping,
              previous.sourceModifier == sourceModifier else {
            return false
        }
        let elapsed = now - previous.timestamp
        return elapsed >= 0 && elapsed < Self.duplicateTapInterval
    }

    private func releaseModifier(
        _ control: ControllerControlID,
        profile: ControllerProfile
    ) {
        armedModifierControls.remove(control)
        modifierPressOrder.removeAll(where: { $0 == control })

        let wasConsumed = consumedModifierControls.remove(control) != nil
        if wasConsumed {
            let activeControls = activeStates.compactMap { activeControl, state in
                state.sourceModifier == control && !state.isToggledOn
                    ? activeControl
                    : nil
            }
            for activeControl in activeControls {
                finishActiveState(for: activeControl)
            }
            return
        }

        // A modifier remains dual-purpose: releasing it without using a chord
        // performs its normal action once. This deliberately treats the normal
        // mapping as a tap so a layer modifier can never leave a held key down.
        fireModifierTapAction(profile.effectiveMapping(for: control, modifierControl: nil))
    }

    private func fireModifierTapAction(_ mapping: ControllerActionMapping) {
        if mapping.actionType == .leftMouseHold {
            postMouseClick(button: .left)
            return
        }
        fireDiscreteAction(mapping)
    }

    private func handlePress(
        for control: ControllerControlID,
        mapping: ControllerActionMapping,
        sourceModifier: ControllerControlID?
    ) {
        switch mapping.triggerMode {
        case .tap:
            fireDiscreteAction(mapping)
        case .holdWhilePressed:
            beginHoldAction(
                for: control,
                mapping: mapping,
                sourceModifier: sourceModifier
            )
        case .repeatWhileHeld:
            beginRepeatingAction(
                for: control,
                mapping: mapping,
                sourceModifier: sourceModifier
            )
        case .toggle:
            toggleAction(
                for: control,
                mapping: mapping,
                sourceModifier: sourceModifier
            )
        }
    }

    private func handleRelease(for control: ControllerControlID) {
        guard let state = activeStates[control] else { return }
        switch state.triggerMode {
        case .tap, .toggle:
            break
        case .holdWhilePressed, .repeatWhileHeld:
            finishActiveState(for: control)
        }
    }

    private func beginHoldAction(
        for control: ControllerControlID,
        mapping: ControllerActionMapping,
        sourceModifier: ControllerControlID?
    ) {
        switch mapping.actionType {
        case .keyboardShortcut:
            guard let shortcut = mapping.shortcut else { return }
            if dispatchToCompanion(.shortcut(shortcut, phase: .down)) {
                activeStates[control] = ActiveControlState(
                    triggerMode: mapping.triggerMode,
                    sourceModifier: sourceModifier,
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
                triggerMode: mapping.triggerMode,
                sourceModifier: sourceModifier,
                shortcut: shortcut,
                isHoldingShortcut: true,
                isDragging: false,
                isToggledOn: false,
                timer: nil
            )
        case .leftMouseHold:
            if dispatchToCompanion(.mouse(button: .left, phase: .down)) {
                activeStates[control] = ActiveControlState(
                    triggerMode: mapping.triggerMode,
                    sourceModifier: sourceModifier,
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
                triggerMode: mapping.triggerMode,
                sourceModifier: sourceModifier,
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

    private func finishActiveState(for control: ControllerControlID) {
        guard let state = activeStates[control] else { return }
        state.timer?.cancel()
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

    private func beginRepeatingAction(
        for control: ControllerControlID,
        mapping: ControllerActionMapping,
        sourceModifier: ControllerControlID?
    ) {
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
            triggerMode: mapping.triggerMode,
            sourceModifier: sourceModifier,
            shortcut: nil,
            isHoldingShortcut: false,
            isDragging: false,
            isToggledOn: false,
            timer: timer
        )
        fireDiscreteAction(mapping)
    }

    private func toggleAction(
        for control: ControllerControlID,
        mapping: ControllerActionMapping,
        sourceModifier: ControllerControlID?
    ) {
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
                    triggerMode: mapping.triggerMode,
                    sourceModifier: sourceModifier,
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
                triggerMode: mapping.triggerMode,
                sourceModifier: sourceModifier,
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
                    triggerMode: mapping.triggerMode,
                    sourceModifier: sourceModifier,
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
                triggerMode: mapping.triggerMode,
                sourceModifier: sourceModifier,
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
            if dispatchToCompanion(.scroll(vertical: -1, horizontal: 0)) {
                return
            }
            postScroll(vertical: -1, horizontal: 0)
        case .scrollDown:
            if dispatchToCompanion(.scroll(vertical: 1, horizontal: 0)) {
                return
            }
            postScroll(vertical: 1, horizontal: 0)
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
        case .crossEdgeLeft:
            onCrossEdgeSweep?(.left)
        case .crossEdgeRight:
            onCrossEdgeSweep?(.right)
        case .crossEdgeUp:
            onCrossEdgeSweep?(.up)
        case .crossEdgeDown:
            onCrossEdgeSweep?(.down)
        case .toggleCursorSpeeds:
            onToggleCursorSpeeds?()
        }
    }

    private func postShortcutTap(_ shortcut: ShortcutDescriptor) {
        postShortcutDown(shortcut)
        postShortcutUp(shortcut)
    }

    private func postShortcutDown(_ shortcut: ShortcutDescriptor) {
        if cursorEngine.universalControlInputBridge.postShortcutDown(
            keyCode: shortcut.keyCode,
            flags: shortcut.eventFlags
        ) {
            return
        }

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
        if cursorEngine.universalControlInputBridge.postShortcutUp(
            keyCode: shortcut.keyCode,
            flags: shortcut.eventFlags
        ) {
            return
        }

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
        if cursorEngine.universalControlInputBridge.postMouseButton(button, isDown: true) {
            _ = cursorEngine.universalControlInputBridge.postMouseButton(button, isDown: false)
            return
        }

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
        if cursorEngine.universalControlInputBridge.isAvailable {
            var completed = true
            for clickState in [1, 2] {
                guard cursorEngine.universalControlInputBridge.postMouseButton(
                    .left,
                    isDown: true,
                    clickCount: clickState
                ) else {
                    completed = false
                    break
                }
                guard cursorEngine.universalControlInputBridge.postMouseButton(
                    .left,
                    isDown: false,
                    clickCount: clickState
                ) else {
                    completed = false
                    break
                }
            }
            if completed {
                return
            }
        }

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
        if cursorEngine.universalControlInputBridge.postScroll(
            vertical: vertical,
            horizontal: horizontal
        ) {
            return
        }

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

    func performDiagnosticLeftClick() -> String {
        guard isEnabled else { return "Runtime is disabled." }
        guard accessibilityTrusted else { return "Accessibility permission is not granted." }
        postMouseClick(button: .left)
        return "Sent a test left click."
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
        let directionLabel = direction == .left ? "left" : "right"
        let hardwareShortcut = ShortcutDescriptor(
            keyCode: UInt16(keyCode),
            modifiers: [.control]
        )

        if cursorEngine.universalControlInputBridge.postShortcutDown(
            keyCode: hardwareShortcut.keyCode,
            flags: hardwareShortcut.eventFlags
        ) {
            _ = cursorEngine.universalControlInputBridge.postShortcutUp(
                keyCode: hardwareShortcut.keyCode,
                flags: hardwareShortcut.eventFlags
            )
            onActionStatus?("Switched Space \(directionLabel) through the hardware input path.")
            return
        }

        var scriptFailureMessage: String?
        let scriptSource = """
        tell application "System Events"
            key code \(keyCode) using control down
        end tell
        """

        if let script = NSAppleScript(source: scriptSource) {
            var scriptError: NSDictionary?
            script.executeAndReturnError(&scriptError)
            if scriptError == nil {
                onActionStatus?("Switched Space \(directionLabel) via System Events.")
                return
            }

            scriptFailureMessage = scriptError?[NSAppleScript.errorMessage] as? String ?? "unknown AppleScript error"
        }

        postShortcutTap(hardwareShortcut)

        let fallbackLabel = "Control-\(direction == .left ? "Left" : "Right")"
        if hasEnabledSystemShortcut(keyCode: keyCode, requiredFlags: [.maskControl]) {
            if let scriptFailureMessage {
                onActionStatus?("System Events failed for Space \(directionLabel): \(scriptFailureMessage). Sent \(fallbackLabel) fallback.")
            } else {
                onActionStatus?("Sent \(fallbackLabel) for Space \(directionLabel).")
            }
        } else {
            let base = "Sent \(fallbackLabel), but this Mac does not have a matching Mission Control keyboard shortcut enabled."
            if let scriptFailureMessage {
                onActionStatus?("System Events failed for Space \(directionLabel): \(scriptFailureMessage). \(base)")
            } else {
                onActionStatus?("\(base) Assign one in Keyboard Shortcuts > Mission Control.")
            }
        }
    }

    private func hasEnabledSystemShortcut(keyCode: Int, requiredFlags: CGEventFlags) -> Bool {
        guard let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let symbolicHotKeys = domain["AppleSymbolicHotKeys"] as? [String: Any] else {
            return false
        }

        for value in symbolicHotKeys.values {
            guard let entry = value as? [String: Any],
                  shortcutEntryIsEnabled(entry),
                  let parameters = shortcutParameters(from: entry),
                  parameters.count >= 3,
                  numericValue(parameters[1]) == keyCode else {
                continue
            }

            let modifierFlags = CGEventFlags(rawValue: UInt64(numericValue(parameters[2]) ?? 0))
            if modifierFlags.contains(requiredFlags) {
                return true
            }
        }

        return false
    }

    private func shortcutEntryIsEnabled(_ entry: [String: Any]) -> Bool {
        if let enabled = entry["enabled"] as? Int {
            return enabled != 0
        }
        if let enabled = entry["enabled"] as? Bool {
            return enabled
        }
        if let enabled = entry["enabled"] as? NSNumber {
            return enabled.intValue != 0
        }
        return false
    }

    private func shortcutParameters(from entry: [String: Any]) -> [Any]? {
        guard let value = entry["value"] as? [String: Any],
              (value["type"] as? String) == "standard",
              let parameters = value["parameters"] as? [Any] else {
            return nil
        }
        return parameters
    }

    private func numericValue(_ value: Any) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let intValue = value as? Int {
            return intValue
        }
        return nil
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
    var triggerMode: TriggerMode
    var sourceModifier: ControllerControlID?
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
