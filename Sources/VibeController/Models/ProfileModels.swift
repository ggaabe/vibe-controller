import Foundation

enum ActionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case keyboardShortcut
    case leftClick
    case rightClick
    case middleClick
    case leftMouseHold
    case doubleClick
    case scrollUp
    case scrollDown
    case scrollLeft
    case scrollRight
    case toggleCursorSpeeds

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .keyboardShortcut:
            return "Keyboard Shortcut"
        case .leftClick:
            return "Left Click"
        case .rightClick:
            return "Right Click"
        case .middleClick:
            return "Middle Click"
        case .leftMouseHold:
            return "Left Mouse Hold (drag)"
        case .doubleClick:
            return "Double Click"
        case .scrollUp:
            return "Scroll Up"
        case .scrollDown:
            return "Scroll Down"
        case .scrollLeft:
            return "Scroll Left"
        case .scrollRight:
            return "Scroll Right"
        case .toggleCursorSpeeds:
            return "Toggle Cursor Speeds"
        }
    }

    var defaultTriggerMode: TriggerMode {
        switch self {
        case .keyboardShortcut:
            return .tap
        case .leftClick, .rightClick, .middleClick, .doubleClick:
            return .tap
        case .leftMouseHold:
            return .holdWhilePressed
        case .scrollUp, .scrollDown, .scrollLeft, .scrollRight:
            return .repeatWhileHeld
        case .toggleCursorSpeeds:
            return .tap
        case .none:
            return .tap
        }
    }

    var supportedTriggerModes: [TriggerMode] {
        switch self {
        case .none:
            return [.tap]
        case .keyboardShortcut:
            return [.tap, .holdWhilePressed, .repeatWhileHeld]
        case .leftMouseHold:
            return [.holdWhilePressed, .toggle]
        case .scrollUp, .scrollDown, .scrollLeft, .scrollRight:
            return [.tap, .repeatWhileHeld]
        case .toggleCursorSpeeds:
            return [.tap]
        case .leftClick, .rightClick, .middleClick, .doubleClick:
            return [.tap, .repeatWhileHeld]
        }
    }
}

enum TriggerMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case tap
    case holdWhilePressed
    case repeatWhileHeld
    case toggle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tap:
            return "Tap"
        case .holdWhilePressed:
            return "Hold while pressed"
        case .repeatWhileHeld:
            return "Repeat while held"
        case .toggle:
            return "Toggle"
        }
    }
}

struct ControllerActionMapping: Codable, Hashable, Sendable {
    var actionType: ActionType
    var shortcut: ShortcutDescriptor?
    var triggerMode: TriggerMode
    var repeatDelay: Double
    var repeatInterval: Double

    init(
        actionType: ActionType = .none,
        shortcut: ShortcutDescriptor? = nil,
        triggerMode: TriggerMode? = nil,
        repeatDelay: Double = 0.35,
        repeatInterval: Double = 0.08
    ) {
        self.actionType = actionType
        self.shortcut = shortcut
        self.triggerMode = triggerMode ?? actionType.defaultTriggerMode
        self.repeatDelay = repeatDelay
        self.repeatInterval = repeatInterval
    }

    var summary: String {
        switch actionType {
        case .none:
            return "No action"
        case .keyboardShortcut:
            return shortcut?.displayString ?? "Set shortcut"
        default:
            return actionType.displayName
        }
    }
}

struct CursorConfiguration: Codable, Hashable, Sendable {
    var primaryStick: StickAssignment
    var precisionStick: StickAssignment
    var primarySpeed: Double
    var precisionSpeed: Double
    var deadZone: Double
    var responseCurve: Double
    var smoothing: Double
    var accelerationEnabled: Bool
    var invertPrimaryX: Bool
    var invertPrimaryY: Bool
    var invertPrecisionX: Bool
    var invertPrecisionY: Bool
    var horizontalSpeedMultiplier: Double
    var verticalSpeedMultiplier: Double
}

struct ControllerProfile: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var cursor: CursorConfiguration
    var mappings: [ControllerControlID: ControllerActionMapping]

    init(
        id: String,
        name: String,
        cursor: CursorConfiguration,
        mappings: [ControllerControlID: ControllerActionMapping]
    ) {
        self.id = id
        self.name = name
        self.cursor = cursor
        self.mappings = mappings
    }
}

extension ControllerProfile: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case cursor
        case mappings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        cursor = try container.decode(CursorConfiguration.self, forKey: .cursor)
        let rawMappings = try container.decodeIfPresent([String: ControllerActionMapping].self, forKey: .mappings) ?? [:]
        mappings = Dictionary(
            uniqueKeysWithValues: rawMappings.compactMap { key, value in
                ControllerControlID(rawValue: key).map { ($0, value) }
            }
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(cursor, forKey: .cursor)
        let rawMappings = Dictionary(uniqueKeysWithValues: mappings.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawMappings, forKey: .mappings)
    }
}

struct ProfileDocument: Codable, Hashable, Sendable {
    var version: Int
    var profiles: [ControllerProfile]
    var activeProfileId: String
}

extension ControllerProfile {
    static let desktopControl = ControllerProfile(
        id: "desktop-control",
        name: "Desktop Control",
        cursor: CursorConfiguration(
            primaryStick: .left,
            precisionStick: .right,
            primarySpeed: 2200,
            precisionSpeed: 500,
            deadZone: 0.12,
            responseCurve: 1.8,
            smoothing: 0.5,
            accelerationEnabled: true,
            invertPrimaryX: false,
            invertPrimaryY: false,
            invertPrecisionX: false,
            invertPrecisionY: false,
            horizontalSpeedMultiplier: 1.0,
            verticalSpeedMultiplier: 1.0
        ),
        mappings: [
            .rightTrigger: ControllerActionMapping(actionType: .leftMouseHold, triggerMode: .holdWhilePressed),
            .rightShoulder: ControllerActionMapping(actionType: .leftClick, triggerMode: .tap),
            .leftTrigger: ControllerActionMapping(actionType: .rightClick, triggerMode: .tap),
            .buttonSouth: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: ShortcutDescriptor(keyCode: 36, modifiers: []),
                triggerMode: .tap
            ),
            .options: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: nil,
                triggerMode: .tap
            ),
            .buttonWest: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: ShortcutDescriptor(keyCode: 19, modifiers: [.command, .shift]),
                triggerMode: .tap
            ),
            .buttonNorth: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: ShortcutDescriptor(keyCode: 21, modifiers: [.command, .control, .shift]),
                triggerMode: .tap
            ),
            .dpadUp: ControllerActionMapping(actionType: .scrollUp, triggerMode: .repeatWhileHeld),
            .dpadDown: ControllerActionMapping(actionType: .scrollDown, triggerMode: .repeatWhileHeld),
            .leftThumbstickButton: ControllerActionMapping(actionType: .toggleCursorSpeeds, triggerMode: .tap),
            .rightThumbstickButton: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: ShortcutDescriptor(keyCode: 53, modifiers: []),
                triggerMode: .tap
            ),
        ]
    )
}

extension ProfileDocument {
    static let defaultDocument = ProfileDocument(
        version: 1,
        profiles: [.desktopControl],
        activeProfileId: ControllerProfile.desktopControl.id
    )
}
