import Foundation

enum CompanionProtocol {
    static let version = 2
}

enum CompanionMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case off
    case controller
    case receiver

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .controller:
            return "Controller Mac"
        case .receiver:
            return "Receiver Mac"
        }
    }
}

enum CompanionEdge: String, CaseIterable, Codable, Identifiable, Sendable {
    case left
    case right
    case top
    case bottom

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var opposite: CompanionEdge {
        switch self {
        case .left:
            return .right
        case .right:
            return .left
        case .top:
            return .bottom
        case .bottom:
            return .top
        }
    }
}

struct CompanionPeer: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

enum CompanionConnectionState: Equatable, Sendable {
    case off
    case browsing
    case listening
    case connecting(String)
    case connected(String)
    case error(String)

    var summary: String {
        switch self {
        case .off:
            return "Off"
        case .browsing:
            return "Browsing for receiver"
        case .listening:
            return "Listening for controller"
        case .connecting(let name):
            return "Connecting to \(name)"
        case .connected(let name):
            return "Connected to \(name)"
        case .error(let message):
            return message
        }
    }
}

enum CompanionMouseButton: String, Codable, Sendable {
    case left
    case right
    case middle
}

enum CompanionMousePhase: String, Codable, Sendable {
    case click
    case doubleClick
    case down
    case up
}

enum CompanionShortcutPhase: String, Codable, Sendable {
    case tap
    case down
    case up
}

enum SpaceSwitchDirection: String, Codable, Sendable {
    case left
    case right
}

struct CompanionControlEvent: Sendable {
    enum Payload: Sendable {
        case mouse(button: CompanionMouseButton, phase: CompanionMousePhase)
        case scroll(vertical: Int32, horizontal: Int32)
        case shortcut(ShortcutDescriptor, phase: CompanionShortcutPhase)
        case spaceSwitch(SpaceSwitchDirection)
    }

    let payload: Payload
}

enum CompanionMessageType: String, Codable, Sendable {
    case hello
    case handoffStart
    case pointerDelta
    case mouse
    case scroll
    case shortcut
    case spaceSwitch
    case handoffBack
}

struct CompanionMessage: Codable, Sendable {
    var type: CompanionMessageType
    var name: String?
    var protocolVersion: Int?
    var buildVersion: String?
    var edge: CompanionEdge?
    var normalizedPosition: Double?
    var dx: Double?
    var dy: Double?
    var button: CompanionMouseButton?
    var phase: CompanionMousePhase?
    var vertical: Int32?
    var horizontal: Int32?
    var shortcut: ShortcutDescriptor?
    var shortcutPhase: CompanionShortcutPhase?
    var spaceSwitchDirection: SpaceSwitchDirection?

    static func hello(name: String, protocolVersion: Int, buildVersion: String) -> Self {
        Self(type: .hello, name: name, protocolVersion: protocolVersion, buildVersion: buildVersion)
    }

    static func handoffStart(edge: CompanionEdge, normalizedPosition: Double) -> Self {
        Self(type: .handoffStart, edge: edge, normalizedPosition: normalizedPosition)
    }

    static func pointerDelta(dx: Double, dy: Double) -> Self {
        Self(type: .pointerDelta, dx: dx, dy: dy)
    }

    static func mouse(button: CompanionMouseButton, phase: CompanionMousePhase) -> Self {
        Self(type: .mouse, button: button, phase: phase)
    }

    static func scroll(vertical: Int32, horizontal: Int32) -> Self {
        Self(type: .scroll, vertical: vertical, horizontal: horizontal)
    }

    static func shortcut(_ shortcut: ShortcutDescriptor, phase: CompanionShortcutPhase) -> Self {
        Self(type: .shortcut, shortcut: shortcut, shortcutPhase: phase)
    }

    static func spaceSwitch(_ direction: SpaceSwitchDirection) -> Self {
        Self(type: .spaceSwitch, spaceSwitchDirection: direction)
    }

    static let handoffBack = Self(type: .handoffBack)
}
