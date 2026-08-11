import AppKit
import Combine
import Foundation
import SwiftUI

enum ControllerMappingLayer: Hashable, Identifiable {
    case base
    case modifier(ControllerControlID)

    var id: String {
        switch self {
        case .base:
            return "base"
        case .modifier(let control):
            return "modifier-\(control.rawValue)"
        }
    }

    var displayName: String {
        switch self {
        case .base:
            return "Default"
        case .modifier(let control):
            return "\(control.displayName) held"
        }
    }
}

enum ControllerSheetSelection: Identifiable {
    case mapping(ControllerControlID, ControllerMappingLayer)
    case stick(StickSide)

    var id: String {
        switch self {
        case .mapping(let control, let layer):
            return "mapping-\(layer.id)-\(control.rawValue)"
        case .stick(let side):
            return "stick-\(side.rawValue)"
        }
    }
}

enum AppStatusBadgeState {
    case ready
    case needsAccessibility
    case noController

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .needsAccessibility:
            return "Needs Accessibility"
        case .noController:
            return "No Controller"
        }
    }

    var color: Color {
        switch self {
        case .ready:
            return .green
        case .needsAccessibility:
            return .orange
        case .noController:
            return .secondary
        }
    }
}

enum StickRoleChoice: String, CaseIterable, Identifiable {
    case off
    case primary
    case precision

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .primary:
            return "Primary Cursor"
        case .precision:
            return "Precision Cursor"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var document: ProfileDocument
    @Published private(set) var activeProfileID: String
    @Published private(set) var controllerSnapshot: ControllerSnapshot
    @Published private(set) var accessibilityTrusted: Bool
    @Published private(set) var isRuntimeEnabled: Bool
    @Published private(set) var isAppFrontmost: Bool
    private(set) var controllerInputEvents: Int = 0
    private(set) var lastControllerActivityAt: Date?
    @Published private(set) var cursorDiagnostics: CursorDiagnostics = .initial
    @Published private(set) var lastActionStatus = "Idle"
    @Published private(set) var companionMode: CompanionMode
    @Published private(set) var companionEdge: CompanionEdge
    @Published private(set) var discoveredCompanionPeers: [CompanionPeer] = []
    @Published private(set) var selectedCompanionPeerID: String?
    @Published private(set) var companionConnectionState: CompanionConnectionState = .off
    @Published private(set) var isRoutingToCompanion = false
    @Published private(set) var companionRemoteBuildSummary = "Waiting for peer metadata"
    @Published private(set) var companionHandoffDebug = "No handoff activity yet."
    @Published private(set) var virtualHardwareSetupPhase: VirtualHardwareSetupPhase = .checking
    @Published private(set) var selectedMappingLayer: ControllerMappingLayer = .base
    @Published var presentedSheet: ControllerSheetSelection?
    @Published var lastErrorMessage: String?

    let controllerManager: ControllerManager
    let permissionManager: PermissionManager
    let companionManager: CompanionManager

    private let profileStore: ProfileStore
    private let cursorEngine: CursorEngine
    private let actionEngine: ActionEngine
    private let userDefaults = UserDefaults.standard
    private var lastLocalHandoffRestorePoint: CGPoint?
    private var cancellables = Set<AnyCancellable>()
    private var automaticSetupTimer: Timer?
    private var driverActivationProcess: Process?
    private var didAutomaticallyRequestAccessibility = false
    private var didAutomaticallyOpenSupportInstaller = false
    private var didAutomaticallyRequestDriverActivation = false
    private var driverStatusWaitStartedAt: Date?

    init(
        profileStore: ProfileStore = ProfileStore(),
        controllerManager: ControllerManager = ControllerManager(),
        permissionManager: PermissionManager = PermissionManager(),
        companionManager: CompanionManager = CompanionManager(),
        cursorEngine: CursorEngine = CursorEngine()
    ) {
        self.profileStore = profileStore
        self.controllerManager = controllerManager
        self.permissionManager = permissionManager
        self.companionManager = companionManager
        self.cursorEngine = cursorEngine
        self.actionEngine = ActionEngine(cursorEngine: cursorEngine)

        let loadedDocument = (try? profileStore.loadOrCreate()) ?? ProfileDocument.defaultDocument
        self.document = loadedDocument
        self.activeProfileID = profileStore.effectiveActiveProfileID(for: loadedDocument)
        self.controllerSnapshot = controllerManager.snapshot
        self.accessibilityTrusted = permissionManager.accessibilityTrusted
        self.isRuntimeEnabled = profileStore.loadEnabledState()
        self.isAppFrontmost = NSApp.isActive
        self.companionMode = CompanionMode(rawValue: userDefaults.string(forKey: Self.companionModeKey) ?? "") ?? .off
        self.companionEdge = CompanionEdge(rawValue: userDefaults.string(forKey: Self.companionEdgeKey) ?? "") ?? .right
        self.selectedCompanionPeerID = userDefaults.string(forKey: Self.selectedPeerKey)

        cursorEngine.isEnabled = isRuntimeEnabled
        cursorEngine.accessibilityTrusted = accessibilityTrusted
        actionEngine.isEnabled = isRuntimeEnabled
        actionEngine.accessibilityTrusted = accessibilityTrusted
        actionEngine.onToggleCursorSpeeds = { [weak self] in
            self?.toggleCursorSpeeds()
        }
        actionEngine.onCrossEdgeSweep = { [weak self] direction in
            guard let self else { return }
            self.lastActionStatus = self.cursorEngine.performCrossEdgeSweep(direction)
        }
        actionEngine.onActionStatus = { [weak self] message in
            self?.lastActionStatus = message
        }
        actionEngine.companionDispatch = { [weak self] event in
            self?.dispatchCompanionEvent(event) ?? false
        }
        cursorEngine.onDiagnostics = { [weak self] diagnostics in
            self?.cursorDiagnostics = diagnostics
        }
        cursorEngine.universalControlInputBridge.onStatusChange = { [weak self] in
            self?.objectWillChange.send()
            self?.advanceAutomaticSetup()
        }
        controllerManager.onSnapshot = { [weak self] snapshot in
            self?.handleControllerSnapshot(snapshot)
        }
        controllerManager.onActionSnapshot = { [weak self] snapshot in
            self?.handleControllerActions(snapshot)
        }
        controllerManager.onRealtimeSnapshot = { [weak cursorEngine] snapshot in
            cursorEngine?.updateInput(snapshot: snapshot)
        }
        companionManager.onMessage = { [weak self] message in
            self?.handleCompanionMessage(message)
        }

        permissionManager.$accessibilityTrusted
            .receive(on: RunLoop.main)
            .sink { [weak self] trusted in
                self?.handlePermissionChange(trusted)
            }
            .store(in: &cancellables)

        companionManager.$discoveredPeers
            .receive(on: RunLoop.main)
            .sink { [weak self] peers in
                self?.discoveredCompanionPeers = peers
                if self?.selectedCompanionPeerID == nil, let first = peers.first {
                    self?.selectCompanionPeer(first.id)
                } else if let selected = self?.selectedCompanionPeerID,
                          peers.contains(where: { $0.id == selected }) == false {
                    self?.selectCompanionPeer(peers.first?.id)
                }
            }
            .store(in: &cancellables)

        companionManager.$connectionState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.companionConnectionState = state
                self?.syncMovementInterceptor()
                if case .connected = state {
                    return
                }
                self?.isRoutingToCompanion = false
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.shutdown()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.isAppFrontmost = true
                self?.syncCursorConfiguration()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.isAppFrontmost = false
                self?.syncCursorConfiguration()
            }
            .store(in: &cancellables)

        persistDocument()
        companionManager.setMode(companionMode)
        syncMovementInterceptor()
        syncCursorConfiguration()
        if controllerSnapshot.isConnected {
            actionEngine.process(snapshot: controllerSnapshot, profile: activeProfile)
        }
        startAutomaticSetupMonitoring()
    }

    var activeProfile: ControllerProfile {
        document.profiles.first(where: { $0.id == activeProfileID }) ?? document.profiles[0]
    }

    var availableProfiles: [ControllerProfile] {
        document.profiles
    }

    var statusBadgeState: AppStatusBadgeState {
        if !accessibilityTrusted {
            return .needsAccessibility
        }
        if !controllerSnapshot.isConnected {
            return .noController
        }
        return .ready
    }

    var batterySummary: String? {
        guard let batteryLevel = controllerSnapshot.batteryLevel else { return nil }
        let percentage = Int((batteryLevel * 100).rounded())
        if let state = controllerSnapshot.batteryStateDescription {
            return "\(percentage)% \(state)"
        }
        return "\(percentage)%"
    }

    var runtimeStatusText: String {
        isRuntimeEnabled ? "Enabled" : "Disabled"
    }

    var listeningStatusText: String {
        guard controllerSnapshot.isConnected else {
            return "No controller"
        }
        guard let lastControllerActivityAt else {
            return "Listening"
        }
        if Date().timeIntervalSince(lastControllerActivityAt) < 1.5 {
            return "Receiving input"
        }
        return "Listening"
    }

    var liveInputSummary: String {
        let left = controllerSnapshot.leftStick
        let right = controllerSnapshot.rightStick
        let pressed = controllerSnapshot.pressedControls.map(\.displayName).sorted().joined(separator: ", ")
        let pressedSummary = pressed.isEmpty ? "none" : pressed
        return String(
            format: "L %.2f %.2f   R %.2f %.2f   Pressed: %@",
            left.x,
            left.y,
            right.x,
            right.y,
            pressedSummary
        )
    }

    var companionStatusText: String {
        if companionMode == .off {
            return cursorEngine.universalControlInputBridge.isVirtualHardwareReady
                ? "Virtual hardware ready"
                : "Virtual hardware setup required"
        }
        if isRoutingToCompanion {
            return "Routing to remote Mac"
        }
        return companionConnectionState.summary
    }

    var nativeUniversalControlStatusText: String {
        cursorEngine.universalControlInputBridge.initializationMessage
    }

    var virtualHardwareReady: Bool {
        cursorEngine.universalControlInputBridge.isVirtualHardwareReady
    }

    var virtualHardwareInstallerAvailable: Bool {
        virtualHardwareInstallerURL != nil
    }

    var virtualHardwareDriverInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: Self.virtualHardwareManagerPath)
    }

    var virtualHardwareSupportInstalled: Bool {
        PrivilegedVirtualHIDBridge.isInstalledSecurely && virtualHardwareDriverInstalled
    }

    var virtualHardwareSetupTitle: String {
        virtualHardwareSetupPhase.title
    }

    var virtualHardwareSetupDetail: String {
        virtualHardwareSetupPhase.detail
    }

    var virtualHardwareSetupStepLabel: String? {
        virtualHardwareSetupPhase.stepNumber.map { "Step \($0) of 3" }
    }

    func openVirtualHardwareInstaller() {
        didAutomaticallyOpenSupportInstaller = true
        guard let url = virtualHardwareInstallerURL else {
            lastErrorMessage = "The Virtual Hardware Support installer is not bundled with this build."
            return
        }
        NSWorkspace.shared.open(url)
        lastActionStatus = "Opened the Virtual Hardware Support installer."
    }

    func activateVirtualHardwareDriver() {
        didAutomaticallyRequestDriverActivation = true
        requestVirtualHardwareDriverActivation(openSettings: true)
    }

    func openDriverExtensionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
        lastActionStatus = "Opened Driver Extension settings. Select Karabiner and enable its Driver Extension."
    }

    func refreshVirtualHardwareSupport() {
        advanceAutomaticSetup()
    }

    func retryAutomaticSetup() {
        didAutomaticallyRequestAccessibility = false
        didAutomaticallyOpenSupportInstaller = false
        didAutomaticallyRequestDriverActivation = false
        advanceAutomaticSetup()
    }

    func setCompanionMode(_ mode: CompanionMode) {
        guard companionMode != mode else { return }
        companionMode = mode
        userDefaults.set(mode.rawValue, forKey: Self.companionModeKey)
        isRoutingToCompanion = false
        companionRemoteBuildSummary = "Waiting for peer metadata"
        companionHandoffDebug = "No handoff activity yet."
        companionManager.setMode(mode)
        refreshCompanionState()
    }

    func setCompanionEdge(_ edge: CompanionEdge) {
        companionEdge = edge
        userDefaults.set(edge.rawValue, forKey: Self.companionEdgeKey)
    }

    func selectCompanionPeer(_ peerID: String?) {
        selectedCompanionPeerID = peerID
        userDefaults.set(peerID, forKey: Self.selectedPeerKey)
    }

    func connectSelectedCompanionPeer() {
        guard companionMode == .controller else { return }
        if let selectedCompanionPeerID {
            companionManager.connect(to: selectedCompanionPeerID)
        }
        refreshCompanionState()
    }

    func disconnectCompanion() {
        isRoutingToCompanion = false
        companionRemoteBuildSummary = "Waiting for peer metadata"
        companionHandoffDebug = "Disconnected."
        companionManager.disconnect()
        refreshCompanionState()
    }

    func forceCompanionHandoff() {
        guard companionMode == .controller else { return }
        guard case .connected = companionConnectionState else {
            companionHandoffDebug = "[Controller] cannot force handoff: not connected."
            return
        }
        let currentLocation = cursorEngine.currentCursorPosition()
        let bounds = visibleDesktopBounds()
        lastLocalHandoffRestorePoint = restorePointForLocalMac(from: currentLocation, in: bounds)
        isRoutingToCompanion = true
        companionHandoffDebug = "[Controller] forced handoff from \(Int(currentLocation.x)), \(Int(currentLocation.y))"
        companionManager.send(
            .handoffStart(
                edge: companionEdge,
                normalizedPosition: normalizedPosition(for: currentLocation, in: bounds, edge: companionEdge)
            )
        )
    }

    func forceReturnLocal() {
        guard companionMode == .controller else { return }
        if isRoutingToCompanion {
            companionManager.send(.handoffBack)
        }
        isRoutingToCompanion = false
        if let restorePoint = lastLocalHandoffRestorePoint {
            companionHandoffDebug = "[Controller] forced local return at \(Int(restorePoint.x)), \(Int(restorePoint.y))"
            cursorEngine.positionCursor(at: restorePoint)
        } else {
            companionHandoffDebug = "[Controller] forced local return with no restore point."
        }
    }

    func selectProfile(_ profileID: String) {
        guard document.profiles.contains(where: { $0.id == profileID }) else { return }
        activeProfileID = profileID
        document.activeProfileId = profileID
        profileStore.setActiveProfileID(profileID)
        selectedMappingLayer = .base
        persistDocument()
        syncCursorConfiguration()
    }

    func setRuntimeEnabled(_ enabled: Bool) {
        guard enabled != isRuntimeEnabled else { return }
        isRuntimeEnabled = enabled
        profileStore.setEnabledState(enabled)
        cursorEngine.isEnabled = enabled
        actionEngine.isEnabled = enabled
        if !enabled {
            shutdown()
        } else {
            syncCursorConfiguration()
            actionEngine.process(snapshot: controllerSnapshot, profile: activeProfile)
        }
    }

    func requestAccessibilitySetup() {
        didAutomaticallyRequestAccessibility = true
        permissionManager.requestAccessibilityPrompt()
        if !permissionManager.accessibilityTrusted {
            permissionManager.openAccessibilitySettings()
        }
    }

    func resetActiveProfileToDefaults() {
        updateActiveProfile { profile in
            let defaults = ControllerProfile.gabesDefaults
            profile.cursor = defaults.cursor
            profile.mappings = defaults.mappings
            profile.modifierLayers = defaults.modifierLayers
        }
        selectedMappingLayer = .base
    }

    func presentMapping(for control: ControllerControlID) {
        let editingLayer: ControllerMappingLayer
        if case .modifier(let modifierControl) = selectedMappingLayer,
           modifierControl == control {
            editingLayer = .base
        } else {
            editingLayer = selectedMappingLayer
        }
        presentedSheet = .mapping(control, editingLayer)
    }

    func presentStickSheet(for side: StickSide) {
        presentedSheet = .stick(side)
    }

    var mappingLayers: [ControllerMappingLayer] {
        [.base] + activeProfile.modifierLayers.map { .modifier($0.modifierControl) }
    }

    var availableModifierControls: [ControllerControlID] {
        let existing = Set(activeProfile.modifierLayers.map(\.modifierControl))
        return ControllerControlID.mappingControls.filter { !existing.contains($0) }
    }

    var selectedModifierControl: ControllerControlID? {
        guard case .modifier(let control) = selectedMappingLayer else { return nil }
        return control
    }

    var mappingLayerDetail: String {
        switch selectedMappingLayer {
        case .base:
            return "Normal controller actions"
        case .modifier(let control):
            return "Overrides used while \(control.displayName) is held"
        }
    }

    func selectMappingLayer(_ layer: ControllerMappingLayer) {
        guard mappingLayers.contains(layer) else { return }
        selectedMappingLayer = layer
    }

    func addModifierLayer(_ modifierControl: ControllerControlID) {
        guard modifierControl.isMappingEligible,
              activeProfile.modifierLayer(for: modifierControl) == nil else {
            return
        }
        updateActiveProfile { profile in
            profile.modifierLayers.append(
                ControllerModifierLayer(modifierControl: modifierControl)
            )
        }
        selectedMappingLayer = .modifier(modifierControl)
    }

    func removeModifierLayer(_ modifierControl: ControllerControlID) {
        if selectedModifierControl == modifierControl {
            selectedMappingLayer = .base
        }
        updateActiveProfile { profile in
            profile.modifierLayers.removeAll {
                $0.modifierControl == modifierControl
            }
        }
    }

    func mapping(
        for control: ControllerControlID,
        in layer: ControllerMappingLayer
    ) -> ControllerActionMapping {
        switch layer {
        case .base:
            return activeProfile.effectiveMapping(for: control, modifierControl: nil)
        case .modifier(let modifierControl):
            return activeProfile.effectiveMapping(
                for: control,
                modifierControl: modifierControl
            )
        }
    }

    func hasMappingOverride(
        for control: ControllerControlID,
        in layer: ControllerMappingLayer
    ) -> Bool {
        guard case .modifier(let modifierControl) = layer else { return false }
        return activeProfile.modifierLayer(for: modifierControl)?.mappings[control] != nil
    }

    func mapping(for control: ControllerControlID) -> ControllerActionMapping {
        mapping(for: control, in: selectedMappingLayer)
    }

    func mappingSummary(for control: ControllerControlID) -> String {
        if control.isStickRoleControl {
            guard let stickSide = control.stickSide else { return "Off" }
            switch roleChoice(for: stickSide) {
            case .primary:
                return "Primary Cursor"
            case .precision:
                return "Precision Cursor"
            case .off:
                return "Off"
            }
        }
        switch selectedMappingLayer {
        case .base:
            return mapping(for: control, in: .base).summary
        case .modifier(let modifierControl):
            if control == modifierControl {
                return "Layer Modifier"
            }
            let summary = mapping(for: control, in: selectedMappingLayer).summary
            return hasMappingOverride(for: control, in: selectedMappingLayer)
                ? summary
                : "Default · \(summary)"
        }
    }

    func saveMapping(
        _ mapping: ControllerActionMapping,
        for control: ControllerControlID,
        in layer: ControllerMappingLayer
    ) {
        updateActiveProfile { profile in
            switch layer {
            case .base:
                if mapping.actionType == .none {
                    profile.mappings.removeValue(forKey: control)
                } else {
                    profile.mappings[control] = mapping
                }
            case .modifier(let modifierControl):
                guard let index = profile.modifierLayers.firstIndex(where: {
                    $0.modifierControl == modifierControl
                }) else { return }
                // None is a meaningful layer override: it suppresses the
                // default action while this modifier is held.
                profile.modifierLayers[index].mappings[control] = mapping
            }
        }
    }

    func clearMappingOverride(
        for control: ControllerControlID,
        in layer: ControllerMappingLayer
    ) {
        guard case .modifier(let modifierControl) = layer else { return }
        updateActiveProfile { profile in
            guard let index = profile.modifierLayers.firstIndex(where: {
                $0.modifierControl == modifierControl
            }) else { return }
            profile.modifierLayers[index].mappings.removeValue(forKey: control)
        }
    }

    func duplicateAssignments(
        for shortcut: ShortcutDescriptor,
        excluding control: ControllerControlID,
        in layer: ControllerMappingLayer
    ) -> [ControllerControlID] {
        ControllerControlID.mappingControls.compactMap { candidate in
            let candidateMapping = mapping(for: candidate, in: layer)
            guard candidate != control,
                  candidateMapping.actionType == .keyboardShortcut,
                  candidateMapping.shortcut?.duplicateKey == shortcut.duplicateKey else {
                return nil
            }
            return candidate
        }
    }

    func importProfile(from url: URL) {
        do {
            let updated = try profileStore.importProfile(from: url, into: document)
            document = updated
            activeProfileID = updated.activeProfileId
            selectedMappingLayer = .base
            profileStore.setActiveProfileID(activeProfileID)
            persistDocument()
            syncCursorConfiguration()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func testCursorNudge() {
        lastActionStatus = cursorEngine.performDiagnosticNudge()
    }

    func testLeftClick() {
        lastActionStatus = actionEngine.performDiagnosticLeftClick()
    }

    func captureRemoteProof() {
        guard virtualHardwareReady else {
            lastErrorMessage = "Virtual hardware must be ready before capturing a remote proof."
            return
        }

        let bounds = visibleDesktopBounds()
        cursorEngine.positionCursor(
            at: CGPoint(x: bounds.minX + min(600, bounds.width * 0.35), y: bounds.minY + min(320, bounds.height * 0.35))
        )
        lastActionStatus = cursorEngine.performDiagnosticNudge()

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(6.2))
            _ = self.actionEngine.performDiagnosticLeftClick()
            try? await Task.sleep(for: .milliseconds(500))

            let bridge = self.cursorEngine.universalControlInputBridge
            let command = CGEventFlags.maskCommand
            _ = bridge.postShortcutDown(keyCode: 49, flags: command)
            _ = bridge.postShortcutUp(keyCode: 49, flags: command)
            try? await Task.sleep(for: .milliseconds(700))

            let screenshotFlags: CGEventFlags = [.maskControl, .maskShift, .maskCommand]
            _ = bridge.postShortcutDown(keyCode: 20, flags: screenshotFlags)
            _ = bridge.postShortcutUp(keyCode: 20, flags: screenshotFlags)
            self.lastActionStatus = "Requested a screenshot from the active Universal Control Mac."

            try? await Task.sleep(for: .seconds(1))
            _ = bridge.postShortcutDown(keyCode: 53, flags: [])
            _ = bridge.postShortcutUp(keyCode: 53, flags: [])
        }
    }

    func cursorBinding<Value>(_ keyPath: WritableKeyPath<CursorConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { self.activeProfile.cursor[keyPath: keyPath] },
            set: { newValue in
                self.updateActiveProfile { profile in
                    profile.cursor[keyPath: keyPath] = newValue
                }
            }
        )
    }

    func primaryStickBinding() -> Binding<StickAssignment> {
        Binding(
            get: { self.activeProfile.cursor.primaryStick },
            set: { newValue in
                self.updateActiveProfile { profile in
                    profile.cursor.primaryStick = newValue
                    if newValue != .off, profile.cursor.precisionStick == newValue {
                        profile.cursor.precisionStick = newValue == .left ? .right : .left
                    }
                }
            }
        )
    }

    func precisionStickBinding() -> Binding<StickAssignment> {
        Binding(
            get: { self.activeProfile.cursor.precisionStick },
            set: { newValue in
                self.updateActiveProfile { profile in
                    profile.cursor.precisionStick = newValue
                    if newValue != .off, profile.cursor.primaryStick == newValue {
                        profile.cursor.primaryStick = newValue == .left ? .right : .left
                    }
                }
            }
        )
    }

    func roleChoice(for side: StickSide) -> StickRoleChoice {
        if activeProfile.cursor.primaryStick.stickSide == side {
            return .primary
        }
        if activeProfile.cursor.precisionStick.stickSide == side {
            return .precision
        }
        return .off
    }

    func assignStick(_ side: StickSide, role: StickRoleChoice) {
        updateActiveProfile { profile in
            let assignment: StickAssignment = side == .left ? .left : .right
            switch role {
            case .off:
                if profile.cursor.primaryStick == assignment {
                    profile.cursor.primaryStick = .off
                }
                if profile.cursor.precisionStick == assignment {
                    profile.cursor.precisionStick = .off
                }
            case .primary:
                profile.cursor.primaryStick = assignment
                if profile.cursor.precisionStick == assignment {
                    profile.cursor.precisionStick = assignment == .left ? .right : .left
                }
            case .precision:
                profile.cursor.precisionStick = assignment
                if profile.cursor.primaryStick == assignment {
                    profile.cursor.primaryStick = assignment == .left ? .right : .left
                }
            }
        }
    }

    private func updateActiveProfile(_ update: (inout ControllerProfile) -> Void) {
        guard let index = document.profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        var profile = document.profiles[index]
        update(&profile)
        document.profiles[index] = profile
        document.activeProfileId = activeProfileID
        persistDocument()
        syncCursorConfiguration()
    }

    private func handleControllerSnapshot(_ snapshot: ControllerSnapshot) {
        let didChange = snapshot.lastUpdated != controllerSnapshot.lastUpdated
        if didChange && snapshot.isConnected {
            controllerInputEvents += 1
            lastControllerActivityAt = snapshot.lastUpdated
        }
        controllerSnapshot = snapshot
    }

    private func handleControllerActions(_ snapshot: ControllerSnapshot) {
        if snapshot.isConnected {
            actionEngine.process(snapshot: snapshot, profile: activeProfile)
        } else {
            actionEngine.cancelAll()
            cursorEngine.releaseTransientState()
        }
    }

    private func handlePermissionChange(_ trusted: Bool) {
        accessibilityTrusted = trusted
        cursorEngine.accessibilityTrusted = trusted
        actionEngine.accessibilityTrusted = trusted
        if !trusted {
            actionEngine.cancelAll()
            cursorEngine.releaseTransientState()
        } else {
            syncCursorConfiguration()
        }
        advanceAutomaticSetup()
    }

    private func refreshCompanionState() {
        discoveredCompanionPeers = companionManager.discoveredPeers
        companionConnectionState = companionManager.connectionState
        syncMovementInterceptor()
    }

    private func syncMovementInterceptor() {
        guard companionMode == .controller,
              case .connected = companionConnectionState else {
            cursorEngine.movementInterceptor = nil
            return
        }
        cursorEngine.movementInterceptor = { [weak self] currentLocation, delta in
            self?.interceptCursorMovement(currentLocation: currentLocation, delta: delta) ?? false
        }
    }

    private func interceptCursorMovement(currentLocation: CGPoint, delta: SIMD2<Double>) -> Bool {
        guard companionMode == .controller else { return false }
        guard case .connected = companionConnectionState else { return false }
        let bounds = visibleDesktopBounds()
        let projectedLocation = projectedCursorLocation(from: currentLocation, delta: delta, in: bounds)
        let willBeginHandoff = shouldBeginRemoteHandoff(at: currentLocation, delta: delta, bounds: bounds)
        companionHandoffDebug = handoffDebugSummary(
            modeLabel: "Controller",
            label: isRoutingToCompanion ? "remote" : "local",
            location: currentLocation,
            projected: projectedLocation,
            bounds: bounds,
            triggered: willBeginHandoff
        )

        if isRoutingToCompanion {
            companionManager.send(.pointerDelta(dx: delta.x, dy: delta.y))
            return true
        }

        guard willBeginHandoff else {
            return false
        }

        lastLocalHandoffRestorePoint = restorePointForLocalMac(from: currentLocation, in: bounds)
        isRoutingToCompanion = true
        companionManager.send(
            .handoffStart(
                edge: companionEdge,
                normalizedPosition: normalizedPosition(for: projectedLocation, in: bounds, edge: companionEdge)
            )
        )
        companionManager.send(.pointerDelta(dx: delta.x, dy: delta.y))
        return true
    }

    private func dispatchCompanionEvent(_ event: CompanionControlEvent) -> Bool {
        guard companionMode == .controller, isRoutingToCompanion else { return false }
        switch event.payload {
        case .mouse(let button, let phase):
            companionManager.send(.mouse(button: button, phase: phase))
        case .scroll(let vertical, let horizontal):
            companionManager.send(.scroll(vertical: vertical, horizontal: horizontal))
        case .shortcut(let shortcut, let phase):
            companionManager.send(.shortcut(shortcut, phase: phase))
        case .spaceSwitch(let direction):
            companionManager.send(.spaceSwitch(direction))
        }
        return true
    }

    private func handleCompanionMessage(_ message: CompanionMessage) {
        switch message.type {
        case .hello:
            let name = message.name ?? "Unknown peer"
            let protocolSummary = message.protocolVersion.map { "protocol \($0)" } ?? "protocol ?"
            let buildSummary = message.buildVersion ?? "build unknown"
            companionRemoteBuildSummary = "\(name) • \(protocolSummary) • \(buildSummary)"
            refreshCompanionState()
        case .handoffStart:
            guard companionMode == .receiver,
                  let edge = message.edge,
                  let normalizedPosition = message.normalizedPosition else { return }
            let target = remoteEntryPoint(for: edge, normalizedPosition: normalizedPosition, in: visibleDesktopBounds())
            companionHandoffDebug = "[Receiver] entry: \(edge.displayName) at \(Int(target.x)), \(Int(target.y))"
            cursorEngine.positionCursor(at: target)
        case .pointerDelta:
            guard companionMode == .receiver,
                  let dx = message.dx,
                  let dy = message.dy else { return }
            let delta = SIMD2<Double>(dx, dy)
            if shouldReturnToLocal(delta: delta) {
                companionHandoffDebug = "[Receiver] return edge reached. Handing control back."
                companionManager.send(.handoffBack)
                return
            }
            cursorEngine.applyExternalDelta(delta)
        case .mouse:
            guard companionMode == .receiver,
                  let button = message.button,
                  let phase = message.phase else { return }
            actionEngine.performCompanionEvent(
                CompanionControlEvent(payload: .mouse(button: button, phase: phase))
            )
        case .scroll:
            guard companionMode == .receiver,
                  let vertical = message.vertical,
                  let horizontal = message.horizontal else { return }
            actionEngine.performCompanionEvent(
                CompanionControlEvent(payload: .scroll(vertical: vertical, horizontal: horizontal))
            )
        case .shortcut:
            guard companionMode == .receiver,
                  let shortcut = message.shortcut,
                  let phase = message.shortcutPhase else { return }
            actionEngine.performCompanionEvent(
                CompanionControlEvent(payload: .shortcut(shortcut, phase: phase))
            )
        case .spaceSwitch:
            guard companionMode == .receiver,
                  let direction = message.spaceSwitchDirection else { return }
            actionEngine.performCompanionEvent(
                CompanionControlEvent(payload: .spaceSwitch(direction))
            )
        case .handoffBack:
            isRoutingToCompanion = false
            if let restorePoint = lastLocalHandoffRestorePoint {
                companionHandoffDebug = "[Controller] returned locally at \(Int(restorePoint.x)), \(Int(restorePoint.y))"
                cursorEngine.positionCursor(at: restorePoint)
            }
        }
    }

    private func shouldBeginRemoteHandoff(at location: CGPoint, delta: SIMD2<Double>) -> Bool {
        shouldBeginRemoteHandoff(at: location, delta: delta, bounds: visibleDesktopBounds())
    }

    private func shouldBeginRemoteHandoff(at location: CGPoint, delta: SIMD2<Double>, bounds: CGRect) -> Bool {
        let threshold = 2.0
        let projectedLocation = projectedCursorLocation(from: location, delta: delta, in: bounds)
        switch companionEdge {
        case .left:
            return (location.x <= bounds.minX + threshold || projectedLocation.x <= bounds.minX + threshold) && delta.x < 0
        case .right:
            return (location.x >= bounds.maxX - threshold || projectedLocation.x >= bounds.maxX - threshold) && delta.x > 0
        case .top:
            return (location.y >= bounds.maxY - threshold || projectedLocation.y >= bounds.maxY - threshold) && delta.y > 0
        case .bottom:
            return (location.y <= bounds.minY + threshold || projectedLocation.y <= bounds.minY + threshold) && delta.y < 0
        }
    }

    private func shouldReturnToLocal(delta: SIMD2<Double>) -> Bool {
        let location = cursorEngine.currentCursorPosition()
        let bounds = visibleDesktopBounds()
        let threshold = 2.0
        let projectedLocation = projectedCursorLocation(from: location, delta: delta, in: bounds)
        switch companionEdge.opposite {
        case .left:
            return (location.x <= bounds.minX + threshold || projectedLocation.x <= bounds.minX + threshold) && delta.x < 0
        case .right:
            return (location.x >= bounds.maxX - threshold || projectedLocation.x >= bounds.maxX - threshold) && delta.x > 0
        case .top:
            return (location.y >= bounds.maxY - threshold || projectedLocation.y >= bounds.maxY - threshold) && delta.y > 0
        case .bottom:
            return (location.y <= bounds.minY + threshold || projectedLocation.y <= bounds.minY + threshold) && delta.y < 0
        }
    }

    private func visibleDesktopBounds() -> CGRect {
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displays, &displayCount)
        return displays.reduce(into: CGRect.null) { result, displayID in
            result = result.union(CGDisplayBounds(displayID))
        }
    }

    private func normalizedPosition(for location: CGPoint, in bounds: CGRect, edge: CompanionEdge) -> Double {
        guard bounds.isNull == false else { return 0.5 }
        switch edge {
        case .left, .right:
            let height = max(bounds.height, 1)
            return min(max((location.y - bounds.minY) / height, 0), 1)
        case .top, .bottom:
            let width = max(bounds.width, 1)
            return min(max((location.x - bounds.minX) / width, 0), 1)
        }
    }

    private func remoteEntryPoint(for edge: CompanionEdge, normalizedPosition: Double, in bounds: CGRect) -> CGPoint {
        let clampedNormalized = min(max(normalizedPosition, 0), 1)
        let inset = 8.0
        switch edge {
        case .left:
            return CGPoint(
                x: bounds.maxX - inset,
                y: bounds.minY + (bounds.height * clampedNormalized)
            )
        case .right:
            return CGPoint(
                x: bounds.minX + inset,
                y: bounds.minY + (bounds.height * clampedNormalized)
            )
        case .top:
            return CGPoint(
                x: bounds.minX + (bounds.width * clampedNormalized),
                y: bounds.minY + inset
            )
        case .bottom:
            return CGPoint(
                x: bounds.minX + (bounds.width * clampedNormalized),
                y: bounds.maxY - inset
            )
        }
    }

    private func restorePointForLocalMac(from location: CGPoint, in bounds: CGRect) -> CGPoint {
        let inset = 12.0
        switch companionEdge {
        case .left:
            return CGPoint(x: bounds.minX + inset, y: location.y)
        case .right:
            return CGPoint(x: bounds.maxX - inset, y: location.y)
        case .top:
            return CGPoint(x: location.x, y: bounds.maxY - inset)
        case .bottom:
            return CGPoint(x: location.x, y: bounds.minY + inset)
        }
    }

    private func projectedCursorLocation(from location: CGPoint, delta: SIMD2<Double>, in bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(location.x + delta.x, bounds.minX), bounds.maxX - 1),
            y: min(max(location.y + delta.y, bounds.minY), bounds.maxY - 1)
        )
    }

    private func handoffDebugSummary(
        modeLabel: String,
        label: String,
        location: CGPoint,
        projected: CGPoint,
        bounds: CGRect,
        triggered: Bool
    ) -> String {
        "[\(modeLabel)] \(label.capitalized) \(companionEdge.displayName) edge • x \(Int(location.x))→\(Int(projected.x)) y \(Int(location.y))→\(Int(projected.y)) • bounds \(Int(bounds.minX))...\(Int(bounds.maxX - 1)) / \(Int(bounds.minY))...\(Int(bounds.maxY - 1)) • trigger \(triggered ? "yes" : "no")"
    }

    private func startAutomaticSetupMonitoring() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advanceAutomaticSetup()
            }
        }
        automaticSetupTimer = timer
        RunLoop.main.add(timer, forMode: .common)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.advanceAutomaticSetup()
        }
    }

    private var virtualHardwareSetupSnapshot: VirtualHardwareSetupSnapshot {
        let bridge = cursorEngine.universalControlInputBridge
        return VirtualHardwareSetupSnapshot(
            accessibilityTrusted: accessibilityTrusted,
            helperInstalledSecurely: PrivilegedVirtualHIDBridge.isInstalledSecurely,
            driverManagerInstalled: virtualHardwareDriverInstalled,
            bundledInstallerAvailable: virtualHardwareInstallerAvailable,
            driverStatusKnown: bridge.hasReceivedVirtualHardwareDriverStatus,
            driverActivated: bridge.isVirtualHardwareDriverActivated,
            driverVersionMismatched: bridge.isVirtualHardwareDriverVersionMismatched,
            virtualHardwareReady: bridge.isVirtualHardwareReady
        )
    }

    private func advanceAutomaticSetup() {
        cursorEngine.universalControlInputBridge.refreshVirtualHardwareSupport()

        let nextPhase = virtualHardwareSetupSnapshot.phase
        let phaseChanged = virtualHardwareSetupPhase != nextPhase
        virtualHardwareSetupPhase = nextPhase
        if nextPhase != .checking {
            driverStatusWaitStartedAt = nil
        }

        switch nextPhase {
        case .checking:
            guard virtualHardwareSupportInstalled else { return }
            if driverStatusWaitStartedAt == nil {
                driverStatusWaitStartedAt = Date()
            } else if let startedAt = driverStatusWaitStartedAt,
                      Date().timeIntervalSince(startedAt) >= 3,
                      !didAutomaticallyRequestDriverActivation {
                didAutomaticallyRequestDriverActivation = true
                requestVirtualHardwareDriverActivation(openSettings: true)
            }

        case .needsAccessibility:
            guard !didAutomaticallyRequestAccessibility else { return }
            requestAccessibilitySetup()
            lastActionStatus = "Waiting for Accessibility approval."

        case .needsSupportInstall:
            guard !didAutomaticallyOpenSupportInstaller else { return }
            openVirtualHardwareInstaller()
            lastActionStatus = "Approve the one-time Virtual Hardware Support installer."

        case .missingBundledInstaller:
            if phaseChanged {
                lastErrorMessage = "This app build is missing its bundled Virtual Hardware Support installer."
            }

        case .driverVersionMismatch:
            guard !didAutomaticallyOpenSupportInstaller else { return }
            openVirtualHardwareInstaller()
            lastActionStatus = "Approve the bundled installer to update Virtual Hardware Support."

        case .needsDriverApproval:
            guard !didAutomaticallyRequestDriverActivation else { return }
            didAutomaticallyRequestDriverActivation = true
            requestVirtualHardwareDriverActivation(openSettings: true)

        case .startingVirtualHardware:
            if phaseChanged {
                lastActionStatus = "Starting the virtual mouse and keyboard…"
            }

        case .ready:
            if phaseChanged {
                lastErrorMessage = nil
                lastActionStatus = "Virtual mouse and keyboard ready for Universal Control."
            }
        }
    }

    private func requestVirtualHardwareDriverActivation(openSettings: Bool) {
        guard virtualHardwareDriverInstalled else {
            lastErrorMessage = "Install Virtual Hardware Support first."
            return
        }

        if driverActivationProcess?.isRunning == true {
            if openSettings {
                openDriverExtensionSettingsAfterRequest()
            }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.virtualHardwareManagerPath)
        process.arguments = ["activate"]
        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.driverActivationProcess = nil
                self.cursorEngine.universalControlInputBridge.refreshVirtualHardwareSupport()
                if process.terminationStatus != 0 && !self.virtualHardwareReady {
                    self.lastErrorMessage = "macOS did not activate the virtual hardware driver. Open Driver Extension settings and try again."
                }
                self.advanceAutomaticSetup()
            }
        }

        do {
            try process.run()
            driverActivationProcess = process
            lastActionStatus = "Requesting Driver Extension approval…"
            if openSettings {
                openDriverExtensionSettingsAfterRequest()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func openDriverExtensionSettingsAfterRequest() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !self.virtualHardwareReady else { return }
            self.openDriverExtensionSettings()
        }
    }

    private func syncCursorConfiguration() {
        cursorEngine.isEnabled = isRuntimeEnabled
        actionEngine.isEnabled = isRuntimeEnabled
        cursorEngine.accessibilityTrusted = accessibilityTrusted
        actionEngine.accessibilityTrusted = accessibilityTrusted
        cursorEngine.suspendControllerMotion = false
        actionEngine.suspendActionExecution = false
        cursorEngine.updateConfiguration(activeProfile.cursor)
    }

    private func persistDocument() {
        do {
            try profileStore.save(document)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func toggleCursorSpeeds() {
        updateActiveProfile { profile in
            let originalPrimary = profile.cursor.primarySpeed
            profile.cursor.primarySpeed = profile.cursor.precisionSpeed
            profile.cursor.precisionSpeed = originalPrimary
        }
    }

    private var virtualHardwareInstallerURL: URL? {
        if let bundled = Bundle.main.url(
            forResource: "VibeController-VirtualHardwareSupport",
            withExtension: "pkg"
        ) {
            return bundled
        }
        let developmentCopy = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("dist/VibeController-VirtualHardwareSupport.pkg")
        return FileManager.default.fileExists(atPath: developmentCopy.path) ? developmentCopy : nil
    }

    private func shutdown() {
        companionManager.disconnect()
        actionEngine.cancelAll()
        cursorEngine.releaseTransientState()
        lastLocalHandoffRestorePoint = nil
    }
}

private extension AppModel {
    static let virtualHardwareManagerPath = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
    static let companionModeKey = "companion.mode"
    static let companionEdgeKey = "companion.edge"
    static let selectedPeerKey = "companion.selectedPeer"
}

private extension ControllerControlID {
    var stickSide: StickSide? {
        switch self {
        case .leftThumbstick:
            return .left
        case .rightThumbstick:
            return .right
        default:
            return nil
        }
    }
}
