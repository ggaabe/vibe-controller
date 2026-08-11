import Foundation

enum CrossEdgeDirection: String, Equatable, Sendable {
    case left
    case right
    case up
    case down

    var displayName: String { rawValue.capitalized }

    var motionVector: SIMD2<Double> {
        switch self {
        case .left:
            return SIMD2<Double>(-1, 0)
        case .right:
            return SIMD2<Double>(1, 0)
        case .up:
            return SIMD2<Double>(0, -1)
        case .down:
            return SIMD2<Double>(0, 1)
        }
    }
}

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
    case switchSpaceLeft
    case switchSpaceRight
    case crossEdgeLeft
    case crossEdgeRight
    case crossEdgeUp
    case crossEdgeDown
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
        case .switchSpaceLeft:
            return "Switch Space Left"
        case .switchSpaceRight:
            return "Switch Space Right"
        case .crossEdgeLeft:
            return "Cross Edge Left"
        case .crossEdgeRight:
            return "Cross Edge Right"
        case .crossEdgeUp:
            return "Cross Edge Up"
        case .crossEdgeDown:
            return "Cross Edge Down"
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
        case .switchSpaceLeft, .switchSpaceRight:
            return .tap
        case .crossEdgeLeft, .crossEdgeRight, .crossEdgeUp, .crossEdgeDown:
            return .tap
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
        case .switchSpaceLeft, .switchSpaceRight:
            return [.tap, .repeatWhileHeld]
        case .crossEdgeLeft, .crossEdgeRight, .crossEdgeUp, .crossEdgeDown,
             .toggleCursorSpeeds:
            return [.tap]
        case .leftClick, .rightClick, .middleClick, .doubleClick:
            return [.tap, .repeatWhileHeld]
        }
    }

    var crossEdgeDirection: CrossEdgeDirection? {
        switch self {
        case .crossEdgeLeft:
            return .left
        case .crossEdgeRight:
            return .right
        case .crossEdgeUp:
            return .up
        case .crossEdgeDown:
            return .down
        default:
            return nil
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

struct ControllerModifierLayer: Identifiable, Hashable, Sendable {
    var modifierControl: ControllerControlID
    var mappings: [ControllerControlID: ControllerActionMapping]

    var id: ControllerControlID { modifierControl }

    init(
        modifierControl: ControllerControlID,
        mappings: [ControllerControlID: ControllerActionMapping] = [:]
    ) {
        self.modifierControl = modifierControl
        self.mappings = mappings
    }
}

extension ControllerModifierLayer: Codable {
    private enum CodingKeys: String, CodingKey {
        case modifierControl
        case mappings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modifierControl = try container.decode(ControllerControlID.self, forKey: .modifierControl)
        let rawMappings = try container.decodeIfPresent(
            [String: ControllerActionMapping].self,
            forKey: .mappings
        ) ?? [:]
        mappings = Dictionary(
            uniqueKeysWithValues: rawMappings.compactMap { key, value in
                ControllerControlID(rawValue: key).map { ($0, value) }
            }
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modifierControl, forKey: .modifierControl)
        let rawMappings = Dictionary(uniqueKeysWithValues: mappings.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawMappings, forKey: .mappings)
    }
}

struct CursorConfiguration: Hashable, Sendable {
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
    var flickBoostEnabled: Bool

    init(
        primaryStick: StickAssignment,
        precisionStick: StickAssignment,
        primarySpeed: Double,
        precisionSpeed: Double,
        deadZone: Double,
        responseCurve: Double,
        smoothing: Double,
        accelerationEnabled: Bool,
        invertPrimaryX: Bool,
        invertPrimaryY: Bool,
        invertPrecisionX: Bool,
        invertPrecisionY: Bool,
        horizontalSpeedMultiplier: Double,
        verticalSpeedMultiplier: Double,
        flickBoostEnabled: Bool = true
    ) {
        self.primaryStick = primaryStick
        self.precisionStick = precisionStick
        self.primarySpeed = primarySpeed
        self.precisionSpeed = precisionSpeed
        self.deadZone = deadZone
        self.responseCurve = responseCurve
        self.smoothing = smoothing
        self.accelerationEnabled = accelerationEnabled
        self.invertPrimaryX = invertPrimaryX
        self.invertPrimaryY = invertPrimaryY
        self.invertPrecisionX = invertPrecisionX
        self.invertPrecisionY = invertPrecisionY
        self.horizontalSpeedMultiplier = horizontalSpeedMultiplier
        self.verticalSpeedMultiplier = verticalSpeedMultiplier
        self.flickBoostEnabled = flickBoostEnabled
    }
}

extension CursorConfiguration: Codable {
    private enum CodingKeys: String, CodingKey {
        case primaryStick
        case precisionStick
        case primarySpeed
        case precisionSpeed
        case deadZone
        case responseCurve
        case smoothing
        case accelerationEnabled
        case invertPrimaryX
        case invertPrimaryY
        case invertPrecisionX
        case invertPrecisionY
        case horizontalSpeedMultiplier
        case verticalSpeedMultiplier
        case flickBoostEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryStick = try container.decode(StickAssignment.self, forKey: .primaryStick)
        precisionStick = try container.decode(StickAssignment.self, forKey: .precisionStick)
        primarySpeed = try container.decode(Double.self, forKey: .primarySpeed)
        precisionSpeed = try container.decode(Double.self, forKey: .precisionSpeed)
        deadZone = try container.decode(Double.self, forKey: .deadZone)
        responseCurve = try container.decode(Double.self, forKey: .responseCurve)
        smoothing = try container.decode(Double.self, forKey: .smoothing)
        accelerationEnabled = try container.decode(Bool.self, forKey: .accelerationEnabled)
        invertPrimaryX = try container.decode(Bool.self, forKey: .invertPrimaryX)
        invertPrimaryY = try container.decode(Bool.self, forKey: .invertPrimaryY)
        invertPrecisionX = try container.decode(Bool.self, forKey: .invertPrecisionX)
        invertPrecisionY = try container.decode(Bool.self, forKey: .invertPrecisionY)
        horizontalSpeedMultiplier = try container.decode(Double.self, forKey: .horizontalSpeedMultiplier)
        verticalSpeedMultiplier = try container.decode(Double.self, forKey: .verticalSpeedMultiplier)
        flickBoostEnabled = try container.decodeIfPresent(Bool.self, forKey: .flickBoostEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(primaryStick, forKey: .primaryStick)
        try container.encode(precisionStick, forKey: .precisionStick)
        try container.encode(primarySpeed, forKey: .primarySpeed)
        try container.encode(precisionSpeed, forKey: .precisionSpeed)
        try container.encode(deadZone, forKey: .deadZone)
        try container.encode(responseCurve, forKey: .responseCurve)
        try container.encode(smoothing, forKey: .smoothing)
        try container.encode(accelerationEnabled, forKey: .accelerationEnabled)
        try container.encode(invertPrimaryX, forKey: .invertPrimaryX)
        try container.encode(invertPrimaryY, forKey: .invertPrimaryY)
        try container.encode(invertPrecisionX, forKey: .invertPrecisionX)
        try container.encode(invertPrecisionY, forKey: .invertPrecisionY)
        try container.encode(horizontalSpeedMultiplier, forKey: .horizontalSpeedMultiplier)
        try container.encode(verticalSpeedMultiplier, forKey: .verticalSpeedMultiplier)
        try container.encode(flickBoostEnabled, forKey: .flickBoostEnabled)
    }
}

struct ControllerProfile: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var cursor: CursorConfiguration
    var mappings: [ControllerControlID: ControllerActionMapping]
    var modifierLayers: [ControllerModifierLayer]

    init(
        id: String,
        name: String,
        cursor: CursorConfiguration,
        mappings: [ControllerControlID: ControllerActionMapping],
        modifierLayers: [ControllerModifierLayer] = []
    ) {
        self.id = id
        self.name = name
        self.cursor = cursor
        self.mappings = mappings
        self.modifierLayers = modifierLayers
    }

    func modifierLayer(for control: ControllerControlID) -> ControllerModifierLayer? {
        modifierLayers.first(where: { $0.modifierControl == control })
    }

    func effectiveMapping(
        for control: ControllerControlID,
        modifierControl: ControllerControlID?
    ) -> ControllerActionMapping {
        if let modifierControl,
           let override = modifierLayer(for: modifierControl)?.mappings[control] {
            return override
        }
        return mappings[control] ?? ControllerActionMapping()
    }
}

extension ControllerProfile: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case cursor
        case mappings
        case modifierLayers
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
        modifierLayers = try container.decodeIfPresent(
            [ControllerModifierLayer].self,
            forKey: .modifierLayers
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(cursor, forKey: .cursor)
        let rawMappings = Dictionary(uniqueKeysWithValues: mappings.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawMappings, forKey: .mappings)
        try container.encode(modifierLayers, forKey: .modifierLayers)
    }
}

struct ProfileDocument: Codable, Hashable, Sendable {
    var version: Int
    var profiles: [ControllerProfile]
    var activeProfileId: String
}

extension ControllerProfile {
    static let gabesDefaults = ControllerProfile(
        id: "gabes-defaults",
        name: "Gabe's Defaults",
        cursor: CursorConfiguration(
            primaryStick: .left,
            precisionStick: .right,
            primarySpeed: 2227.5417018581084,
            precisionSpeed: 565.6513935810809,
            deadZone: 0.12,
            responseCurve: 1.8,
            smoothing: 0.5,
            accelerationEnabled: true,
            invertPrimaryX: false,
            invertPrimaryY: false,
            invertPrecisionX: false,
            invertPrecisionY: false,
            horizontalSpeedMultiplier: 1.0,
            verticalSpeedMultiplier: 1.0,
            flickBoostEnabled: false
        ),
        mappings: [
            .leftTrigger: ControllerActionMapping(actionType: .leftMouseHold, triggerMode: .holdWhilePressed),
            .leftShoulder: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: ShortcutDescriptor(keyCode: 53, modifiers: []),
                triggerMode: .tap
            ),
            .rightTrigger: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: ShortcutDescriptor(keyCode: 63, modifiers: []),
                triggerMode: .holdWhilePressed
            ),
            .rightShoulder: ControllerActionMapping(actionType: .rightClick, triggerMode: .tap),
            .buttonSouth: ControllerActionMapping(
                actionType: .leftClick,
                shortcut: ShortcutDescriptor(keyCode: 36, modifiers: []),
                triggerMode: .tap
            ),
            .buttonEast: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: ShortcutDescriptor(keyCode: 21, modifiers: [.control, .shift, .command]),
                triggerMode: .tap
            ),
            .buttonWest: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: ShortcutDescriptor(keyCode: 19, modifiers: [.shift, .command]),
                triggerMode: .tap
            ),
            .buttonNorth: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: ShortcutDescriptor(keyCode: 9, modifiers: [.command]),
                triggerMode: .tap
            ),
            .dpadUp: ControllerActionMapping(actionType: .scrollUp, triggerMode: .repeatWhileHeld),
            .dpadDown: ControllerActionMapping(actionType: .scrollDown, triggerMode: .repeatWhileHeld),
            .dpadLeft: ControllerActionMapping(actionType: .switchSpaceLeft, triggerMode: .tap),
            .dpadRight: ControllerActionMapping(actionType: .switchSpaceRight, triggerMode: .tap),
            .leftThumbstickButton: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: ShortcutDescriptor(keyCode: 36, modifiers: []),
                triggerMode: .tap
            ),
            .rightThumbstickButton: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: ShortcutDescriptor(keyCode: 51, modifiers: []),
                triggerMode: .tap
            ),
            .menu: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: ShortcutDescriptor(keyCode: 17, modifiers: [.command]),
                triggerMode: .tap
            ),
            .options: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: ShortcutDescriptor(keyCode: 8, modifiers: [.command]),
                triggerMode: .tap
            ),
            .home: ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: ShortcutDescriptor(keyCode: 13, modifiers: [.command]),
                triggerMode: .tap
            ),
        ],
        modifierLayers: [
            ControllerModifierLayer(
                modifierControl: .leftShoulder,
                mappings: [
                    .dpadLeft: ControllerActionMapping(actionType: .crossEdgeLeft),
                    .dpadRight: ControllerActionMapping(actionType: .crossEdgeRight),
                    .dpadUp: ControllerActionMapping(actionType: .crossEdgeUp),
                    .dpadDown: ControllerActionMapping(actionType: .crossEdgeDown),
                ]
            ),
        ]
    )
}

extension ProfileDocument {
    static let defaultDocument = ProfileDocument(
        version: 2,
        profiles: [.gabesDefaults],
        activeProfileId: ControllerProfile.gabesDefaults.id
    )
}
