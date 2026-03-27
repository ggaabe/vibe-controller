import Foundation

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
