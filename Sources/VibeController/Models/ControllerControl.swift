import Foundation

enum ControllerFamily: String, Codable, Equatable, Sendable {
    case xbox
    case playStation
    case generic

    static func inferred(from vendorName: String?) -> ControllerFamily {
        let name = vendorName?.lowercased() ?? ""
        if name.contains("dualsense") ||
            name.contains("dualshock") ||
            name.contains("playstation") ||
            name.contains("sony") {
            return .playStation
        }
        if name.contains("xbox") || name.contains("microsoft") {
            return .xbox
        }
        return .generic
    }

    var displayName: String {
        switch self {
        case .xbox:
            return "Xbox"
        case .playStation:
            return "PlayStation"
        case .generic:
            return "Game Controller"
        }
    }
}

enum StickSide: String, Codable, CaseIterable, Identifiable, Sendable {
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left:
            return "Left Stick"
        case .right:
            return "Right Stick"
        }
    }
}

enum StickAssignment: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .left:
            return "Left Stick"
        case .right:
            return "Right Stick"
        }
    }

    var stickSide: StickSide? {
        switch self {
        case .off:
            return nil
        case .left:
            return .left
        case .right:
            return .right
        }
    }
}

enum ControllerControlID: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case buttonSouth
    case buttonEast
    case buttonWest
    case buttonNorth
    case leftShoulder
    case rightShoulder
    case leftTrigger
    case rightTrigger
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight
    case leftThumbstick
    case rightThumbstick
    case leftThumbstickButton
    case rightThumbstickButton
    case menu
    case options
    case home
    case touchpadButton

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .buttonSouth:
            return "A"
        case .buttonEast:
            return "B"
        case .buttonWest:
            return "X"
        case .buttonNorth:
            return "Y"
        case .leftShoulder:
            return "LB"
        case .rightShoulder:
            return "RB"
        case .leftTrigger:
            return "LT"
        case .rightTrigger:
            return "RT"
        case .dpadUp:
            return "D-Pad Up"
        case .dpadDown:
            return "D-Pad Down"
        case .dpadLeft:
            return "D-Pad Left"
        case .dpadRight:
            return "D-Pad Right"
        case .leftThumbstick:
            return "Left Stick"
        case .rightThumbstick:
            return "Right Stick"
        case .leftThumbstickButton:
            return "Left Stick Click"
        case .rightThumbstickButton:
            return "Right Stick Click"
        case .menu:
            return "Menu"
        case .options:
            return "View"
        case .home:
            return "Home"
        case .touchpadButton:
            return "Touchpad"
        }
    }

    func displayName(for family: ControllerFamily) -> String {
        guard family == .playStation else { return displayName }
        switch self {
        case .buttonSouth:
            return "Cross"
        case .buttonEast:
            return "Circle"
        case .buttonWest:
            return "Square"
        case .buttonNorth:
            return "Triangle"
        case .leftShoulder:
            return "L1"
        case .rightShoulder:
            return "R1"
        case .leftTrigger:
            return "L2"
        case .rightTrigger:
            return "R2"
        case .leftThumbstickButton:
            return "L3"
        case .rightThumbstickButton:
            return "R3"
        case .menu:
            return "Options"
        case .options:
            return "Create"
        case .home:
            return "PS"
        case .touchpadButton:
            return "Touchpad"
        default:
            return displayName
        }
    }

    func diagramLabel(for family: ControllerFamily) -> String {
        guard family == .playStation else { return displayName }
        switch self {
        case .buttonSouth:
            return "✕"
        case .buttonEast:
            return "○"
        case .buttonWest:
            return "□"
        case .buttonNorth:
            return "△"
        default:
            return displayName(for: family)
        }
    }

    var sfSymbolName: String {
        switch self {
        case .buttonSouth:
            return "a.circle"
        case .buttonEast:
            return "b.circle"
        case .buttonWest:
            return "x.circle"
        case .buttonNorth:
            return "y.circle"
        case .leftShoulder:
            return "l.circle"
        case .rightShoulder:
            return "r.circle"
        case .leftTrigger:
            return "lt.rectangle.roundedtop"
        case .rightTrigger:
            return "rt.rectangle.roundedtop"
        case .dpadUp:
            return "arrow.up.square"
        case .dpadDown:
            return "arrow.down.square"
        case .dpadLeft:
            return "arrow.left.square"
        case .dpadRight:
            return "arrow.right.square"
        case .leftThumbstick, .rightThumbstick:
            return "circle.circle"
        case .leftThumbstickButton, .rightThumbstickButton:
            return "smallcircle.filled.circle"
        case .menu:
            return "line.3.horizontal.circle"
        case .options:
            return "square.on.square"
        case .home:
            return "house.circle"
        case .touchpadButton:
            return "rectangle.inset.filled"
        }
    }

    var isStickRoleControl: Bool {
        self == .leftThumbstick || self == .rightThumbstick
    }

    var isMappingEligible: Bool {
        !isStickRoleControl
    }

    static let mappingControls: [ControllerControlID] = Self.allCases.filter(\.isMappingEligible)
}
