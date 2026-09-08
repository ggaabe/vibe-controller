import CoreGraphics
import Foundation

/// Action state is protected by `stateLock`. Native input runs on `actionQueue`;
/// only UI notifications and the optional network-companion router use MainActor.
final class ActionEngine: @unchecked Sendable {
    private let stateLock = NSRecursiveLock()
    private let actionQueue: DispatchQueue
    private var realtimeProfile: ControllerProfile?
    private var realtimeApplication: String?
    private var nativeActionsEnabled = false
    private var configurationGeneration: UInt64 = 0
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

    private var enabled = true
    var isEnabled: Bool {
        get { stateLock.withLock { enabled } }
        set { stateLock.withLock {
            guard enabled != newValue else { return }
            enabled = newValue
            configurationGeneration &+= 1
            if !newValue { cancelAll() }
        } }
    }
    private var trusted = false
    var accessibilityTrusted: Bool {
        get { stateLock.withLock { trusted } }
        set { stateLock.withLock {
            guard trusted != newValue else { return }
            trusted = newValue
            configurationGeneration &+= 1
            if !newValue { cancelAll() }
        } }
    }
    private var suspended = false
    var suspendActionExecution: Bool {
        get { stateLock.withLock { suspended } }
        set { stateLock.withLock {
            guard suspended != newValue else { return }
            suspended = newValue
            configurationGeneration &+= 1
            if newValue { cancelAll() }
        } }
    }
    // Companion mode chooses local/remote routing on the main actor. Native
    // Universal Control does not need that routing and can write HID directly.
    private var backgroundScrollRepeats = true
    var allowsBackgroundScrollRepeats: Bool {
        get { stateLock.withLock { backgroundScrollRepeats } }
        set { stateLock.withLock {
            if backgroundScrollRepeats != newValue { heldScrollRepeater.stopAll() }
            backgroundScrollRepeats = newValue
        } }
    }
    @MainActor var onToggleCursorSpeeds: (() -> Void)?
    @MainActor var onCrossEdgeSweep: ((CrossEdgeDirection) -> Void)?
    @MainActor var onActionStatus: ((String) -> Void)?
    @MainActor var companionDispatch: ((CompanionControlEvent) -> Bool)?

    private let cursorEngine: CursorEngine
    private nonisolated let heldScrollRepeater: HeldScrollRepeater
    private let scrollOutput: HeldScrollRepeater.Output
    private let currentTime: () -> TimeInterval
    private let shortcutOutput: (@Sendable (ShortcutDescriptor, Bool) -> Void)?
    private let eventSource = CGEventSource(stateID: .combinedSessionState)
    private var previousPressedControls = Set<ControllerControlID>()
    private var activeStates: [ControllerControlID: ActiveControlState] = [:]
    private var armedModifierControls = Set<ControllerControlID>()
    private var consumedModifierControls = Set<ControllerControlID>()
    private var modifierPressOrder: [ControllerControlID] = []
    private var recentTaps: [ControllerControlID: RecentTap] = [:]

    @MainActor init(
        cursorEngine: CursorEngine,
        currentTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        scrollOutput: HeldScrollRepeater.Output? = nil,
        shortcutOutput: (@Sendable (ShortcutDescriptor, Bool) -> Void)? = nil,
        actionQueue: DispatchQueue? = nil
    ) {
        self.cursorEngine = cursorEngine
        self.currentTime = currentTime
        self.shortcutOutput = shortcutOutput
        self.actionQueue = actionQueue ?? DispatchQueue(
            label: "com.vibe-controller.controller-actions",
            qos: .userInteractive,
            autoreleaseFrequency: .workItem
        )
        let bridge = cursorEngine.universalControlInputBridge
        let output: HeldScrollRepeater.Output = scrollOutput ?? { vertical, horizontal in
            if bridge.postScroll(vertical: vertical, horizontal: horizontal) { return }
            let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 2,
                wheel1: vertical,
                wheel2: horizontal,
                wheel3: 0
            )
            event?.post(tap: .cghidEventTap)
        }
        self.scrollOutput = output
        self.heldScrollRepeater = HeldScrollRepeater(output: output)
    }

    nonisolated func updateRealtimeInput(snapshot: ControllerSnapshot) {
        heldScrollRepeater.updateInput(snapshot)
    }

    func configureRealtimeActions(
        profile: ControllerProfile,
        applicationBundleIdentifier: String?,
        enabled: Bool
    ) {
        stateLock.withLock {
            guard realtimeProfile != profile || realtimeApplication != applicationBundleIdentifier ||
                    nativeActionsEnabled != enabled else { return }
            cancelAll()
            realtimeProfile = profile
            realtimeApplication = applicationBundleIdentifier
            nativeActionsEnabled = enabled
        }
    }

    /// Returns true when the native action queue owns this edge. Returning false
    /// leaves legacy companion routing on MainActor, without double execution.
    func receiveRealtimeActions(_ snapshot: ControllerSnapshot) -> Bool {
        stateLock.withLock {
            guard nativeActionsEnabled, let profile = realtimeProfile else { return false }
            let generation = configurationGeneration
            let application = realtimeApplication
            actionQueue.async { [weak self] in
                guard let self else { return }
                self.stateLock.withLock {
                    guard generation == self.configurationGeneration, self.nativeActionsEnabled else { return }
                    if snapshot.isConnected {
                        self.process(snapshot: snapshot, profile: profile, applicationBundleIdentifier: application)
                    } else {
                        self.resetActionState()
                        self.cursorEngine.releaseTransientState()
                    }
                }
            }
            return true
        }
    }

    private func notifyMain(_ operation: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { operation() }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { operation() } }
        }
    }

    private func reportStatus(_ message: String) {
        notifyMain { [weak self] in self?.onActionStatus?(message) }
    }

    private func crossEdge(_ direction: CrossEdgeDirection) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { onCrossEdgeSweep?(direction) }
        } else {
            reportStatus(cursorEngine.performCrossEdgeSweep(direction))
        }
    }

    func process(
        snapshot: ControllerSnapshot,
        profile: ControllerProfile,
        applicationBundleIdentifier: String? = nil
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }
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
                releaseModifier(
                    control,
                    profile: profile,
                    applicationBundleIdentifier: applicationBundleIdentifier
                )
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
                    modifierControl: activeModifier,
                    applicationBundleIdentifier: applicationBundleIdentifier
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
            reportStatus("A + Left Stick: \(direction.displayName)")
        }

        for control in ControllerControlID.mappingControls
        where newlyPressed.contains(control) && !handledPresses.contains(control) {
            press(
                control,
                profile: profile,
                modifierControl: activeModifierControl(in: actuatedControls),
                applicationBundleIdentifier: applicationBundleIdentifier
            )
        }

        previousPressedControls = actuatedControls
    }

    func performZoomStep(_ direction: StickZoomDirection) {
        stateLock.lock()
        defer { stateLock.unlock() }
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
        stateLock.lock()
        defer { stateLock.unlock() }
        configurationGeneration &+= 1
        resetActionState()
    }

    /// Called while holding stateLock. Input disconnects reset state without
    /// invalidating a subsequent reconnect already queued in the same stream.
    private func resetActionState() {
        heldScrollRepeater.stopAll()
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
        modifierControl: ControllerControlID?,
        applicationBundleIdentifier: String?
    ) {
        if let modifierControl {
            consumedModifierControls.insert(modifierControl)
        }
        let mapping = profile.effectiveMapping(
            for: control,
            modifierControl: modifierControl,
            applicationBundleIdentifier: applicationBundleIdentifier
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
        profile: ControllerProfile,
        applicationBundleIdentifier: String?
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
        fireModifierTapAction(
            profile.effectiveMapping(
                for: control,
                modifierControl: nil,
                applicationBundleIdentifier: applicationBundleIdentifier
            )
        )
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
        heldScrollRepeater.stop(control)
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
        heldScrollRepeater.stop(control)
        var firedInitialScroll = false
        if let delta = mapping.actionType.scrollDelta, allowsBackgroundScrollRepeats {
            firedInitialScroll = true
            let forwarded = dispatchToCompanion(.scroll(vertical: delta.vertical, horizontal: delta.horizontal))
            if !forwarded {
                postScroll(vertical: delta.vertical, horizontal: delta.horizontal)
                activeStates[control] = ActiveControlState(
                    triggerMode: mapping.triggerMode,
                    sourceModifier: sourceModifier,
                    shortcut: nil,
                    isHoldingShortcut: false,
                    isDragging: false,
                    isToggledOn: false,
                    timer: nil
                )
                heldScrollRepeater.start(
                    control: control,
                    modifier: sourceModifier,
                    vertical: delta.vertical,
                    horizontal: delta.horizontal,
                    delay: mapping.repeatDelay,
                    interval: mapping.repeatInterval
                )
                return
            }
        }
        let repeatID = UUID()
        let timer = DispatchSource.makeTimerSource(queue: nativeActionsEnabled ? actionQueue : .main)
        timer.schedule(
            deadline: .now() + max(0.01, mapping.repeatDelay),
            repeating: max(0.01, mapping.repeatInterval)
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.stateLock.withLock {
                guard self.activeStates[control]?.repeatID == repeatID else { return }
                self.fireDiscreteAction(mapping)
            }
        }
        timer.resume()
        activeStates[control] = ActiveControlState(
            triggerMode: mapping.triggerMode,
            sourceModifier: sourceModifier,
            shortcut: nil,
            isHoldingShortcut: false,
            isDragging: false,
            isToggledOn: false,
            timer: timer,
            repeatActivity: ControllerRepeatActivity(),
            repeatID: repeatID
        )
        if !firedInitialScroll { fireDiscreteAction(mapping) }
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
            crossEdge(.left)
        case .crossEdgeRight:
            crossEdge(.right)
        case .crossEdgeUp:
            crossEdge(.up)
        case .crossEdgeDown:
            crossEdge(.down)
        case .toggleCursorSpeeds:
            notifyMain { [weak self] in self?.onToggleCursorSpeeds?() }
        }
    }

    private func postShortcutTap(_ shortcut: ShortcutDescriptor) {
        postShortcutDown(shortcut)
        postShortcutUp(shortcut)
    }

    private func postShortcutDown(_ shortcut: ShortcutDescriptor) {
        if let shortcutOutput { shortcutOutput(shortcut, true); return }
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
        if let shortcutOutput { shortcutOutput(shortcut, false); return }
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
        scrollOutput(vertical, horizontal)
    }

    func performCompanionEvent(_ event: CompanionControlEvent) {
        stateLock.lock()
        defer { stateLock.unlock() }
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
        stateLock.lock()
        defer { stateLock.unlock() }
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
        // Native actions never synchronously wait for the UI-owned network router.
        guard Thread.isMainThread else { return false }
        return MainActor.assumeIsolated {
            companionDispatch?(CompanionControlEvent(payload: payload)) ?? false
        }
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
            reportStatus("Switched Space \(directionLabel) through the hardware input path.")
            return
        }

        // Never block the input queue on a synchronous System Events AppleEvent.
        postShortcutTap(hardwareShortcut)

        let fallbackLabel = "Control-\(direction == .left ? "Left" : "Right")"
        if hasEnabledSystemShortcut(keyCode: keyCode, requiredFlags: [.maskControl]) {
            reportStatus("Sent \(fallbackLabel) for Space \(directionLabel).")
        } else {
            let base = "Sent \(fallbackLabel), but this Mac does not have a matching Mission Control keyboard shortcut enabled."
            reportStatus("\(base) Assign one in Keyboard Shortcuts > Mission Control.")
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
    var repeatActivity: ControllerRepeatActivity? = nil
    var repeatID: UUID? = nil
}

private extension ActionType {
    var scrollDelta: (vertical: Int32, horizontal: Int32)? {
        switch self {
        case .scrollUp: return (-1, 0)
        case .scrollDown: return (1, 0)
        case .scrollLeft: return (0, -1)
        case .scrollRight: return (0, 1)
        default: return nil
        }
    }
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
