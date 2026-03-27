import AppKit
import Combine
import Foundation
import SwiftUI

enum ControllerSheetSelection: Identifiable {
    case mapping(ControllerControlID)
    case stick(StickSide)

    var id: String {
        switch self {
        case .mapping(let control):
            return "mapping-\(control.rawValue)"
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
    @Published private(set) var controllerInputEvents: Int = 0
    @Published private(set) var lastControllerActivityAt: Date?
    @Published private(set) var cursorDiagnostics: CursorDiagnostics = .initial
    @Published var presentedSheet: ControllerSheetSelection?
    @Published var lastErrorMessage: String?

    let controllerManager: ControllerManager
    let permissionManager: PermissionManager

    private let profileStore: ProfileStore
    private let cursorEngine: CursorEngine
    private let actionEngine: ActionEngine
    private var cancellables = Set<AnyCancellable>()

    init(
        profileStore: ProfileStore = ProfileStore(),
        controllerManager: ControllerManager = ControllerManager(),
        permissionManager: PermissionManager = PermissionManager(),
        cursorEngine: CursorEngine = CursorEngine()
    ) {
        self.profileStore = profileStore
        self.controllerManager = controllerManager
        self.permissionManager = permissionManager
        self.cursorEngine = cursorEngine
        self.actionEngine = ActionEngine(cursorEngine: cursorEngine)

        let loadedDocument = (try? profileStore.loadOrCreate()) ?? ProfileDocument.defaultDocument
        self.document = loadedDocument
        self.activeProfileID = profileStore.effectiveActiveProfileID(for: loadedDocument)
        self.controllerSnapshot = controllerManager.snapshot
        self.accessibilityTrusted = permissionManager.accessibilityTrusted
        self.isRuntimeEnabled = profileStore.loadEnabledState()
        self.isAppFrontmost = NSApp.isActive

        cursorEngine.isEnabled = isRuntimeEnabled
        cursorEngine.accessibilityTrusted = accessibilityTrusted
        actionEngine.isEnabled = isRuntimeEnabled
        actionEngine.accessibilityTrusted = accessibilityTrusted
        actionEngine.onToggleCursorSpeeds = { [weak self] in
            self?.toggleCursorSpeeds()
        }
        cursorEngine.onDiagnostics = { [weak self] diagnostics in
            self?.cursorDiagnostics = diagnostics
        }

        controllerManager.onSnapshot = { [weak self] snapshot in
            self?.handleControllerSnapshot(snapshot)
        }

        permissionManager.$accessibilityTrusted
            .receive(on: RunLoop.main)
            .sink { [weak self] trusted in
                self?.handlePermissionChange(trusted)
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
        syncCursorConfiguration()
        if controllerSnapshot.isConnected {
            actionEngine.process(snapshot: controllerSnapshot, profile: activeProfile)
        }
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

    func selectProfile(_ profileID: String) {
        guard document.profiles.contains(where: { $0.id == profileID }) else { return }
        activeProfileID = profileID
        document.activeProfileId = profileID
        profileStore.setActiveProfileID(profileID)
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
        permissionManager.requestAccessibilityPrompt()
    }

    func resetActiveProfileToDefaults() {
        updateActiveProfile { profile in
            let defaults = ControllerProfile.desktopControl
            profile.cursor = defaults.cursor
            profile.mappings = defaults.mappings
        }
    }

    func presentMapping(for control: ControllerControlID) {
        presentedSheet = .mapping(control)
    }

    func presentStickSheet(for side: StickSide) {
        presentedSheet = .stick(side)
    }

    func mapping(for control: ControllerControlID) -> ControllerActionMapping {
        activeProfile.mappings[control] ?? ControllerActionMapping()
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
        return mapping(for: control).summary
    }

    func saveMapping(_ mapping: ControllerActionMapping, for control: ControllerControlID) {
        updateActiveProfile { profile in
            if mapping.actionType == .none {
                profile.mappings.removeValue(forKey: control)
            } else {
                profile.mappings[control] = mapping
            }
        }
    }

    func duplicateAssignments(for shortcut: ShortcutDescriptor, excluding control: ControllerControlID) -> [ControllerControlID] {
        activeProfile.mappings.compactMap { entry in
            guard entry.key != control,
                  entry.value.actionType == .keyboardShortcut,
                  entry.value.shortcut?.duplicateKey == shortcut.duplicateKey else {
                return nil
            }
            return entry.key
        }
    }

    func importProfile(from url: URL) {
        do {
            let updated = try profileStore.importProfile(from: url, into: document)
            document = updated
            activeProfileID = updated.activeProfileId
            profileStore.setActiveProfileID(activeProfileID)
            persistDocument()
            syncCursorConfiguration()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func testCursorNudge() {
        lastErrorMessage = cursorEngine.performDiagnosticNudge()
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
        controllerSnapshot = snapshot
        if didChange && snapshot.isConnected {
            controllerInputEvents += 1
            lastControllerActivityAt = snapshot.lastUpdated
        }
        syncCursorConfiguration()
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
    }

    private func syncCursorConfiguration() {
        cursorEngine.isEnabled = isRuntimeEnabled
        actionEngine.isEnabled = isRuntimeEnabled
        cursorEngine.accessibilityTrusted = accessibilityTrusted
        actionEngine.accessibilityTrusted = accessibilityTrusted
        cursorEngine.suspendControllerMotion = false
        actionEngine.suspendActionExecution = false
        cursorEngine.update(snapshot: controllerSnapshot, cursorConfiguration: activeProfile.cursor)
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

    private func shutdown() {
        actionEngine.cancelAll()
        cursorEngine.releaseTransientState()
    }
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
