import Foundation

enum ControllerVibration: String, CaseIterable, Codable, Identifiable, Sendable {
    case none, softTap, doubleTap, thump, leftPulse, rightPulse, grabRelease

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: "None"
        case .softTap: "Soft tap"
        case .doubleTap: "Double tap"
        case .thump: "Thump"
        case .leftPulse: "Left pulse"
        case .rightPulse: "Right pulse"
        case .grabRelease: "Grab & release"
        }
    }
    var detail: String {
        switch self {
        case .none: "No vibration for this mapping."
        case .softTap: "A light acknowledgement when the command is sent."
        case .doubleTap: "Two light pulses, useful for distinguishing OCR from screenshots."
        case .thump: "One short, rounded pulse for a screen-jump command."
        case .leftPulse: "A pulse in the left handle, or both handles if separate motors are unavailable."
        case .rightPulse: "A pulse in the right handle, or both handles if separate motors are unavailable."
        case .grabRelease: "A tap when the action starts and a lighter tap when a held or toggled action ends."
        }
    }

    enum Phase: Sendable { case press, release }
    enum Locality: Sendable { case handles, left, right }
    struct Pulse: Equatable, Sendable {
        let time: Double
        let duration: Double
        let intensity: Float
    }
    var locality: Locality {
        switch self {
        case .leftPulse: .left
        case .rightPulse: .right
        default: .handles
        }
    }
    func pulses(for phase: Phase) -> [Pulse] {
        if phase == .release {
            return self == .grabRelease ? [Pulse(time: 0, duration: 0.055, intensity: 0.4)] : []
        }
        switch self {
        case .none: return []
        case .softTap, .grabRelease: return [Pulse(time: 0, duration: 0.075, intensity: 0.55)]
        case .doubleTap: return [Pulse(time: 0, duration: 0.065, intensity: 0.6), Pulse(time: 0.14, duration: 0.065, intensity: 0.5)]
        case .thump, .leftPulse, .rightPulse: return [Pulse(time: 0, duration: 0.12, intensity: 0.85)]
        }
    }
}

extension ControllerProfile {
    /// Changes feedback only; never changes a shortcut, trigger mode, or cursor setting.
    mutating func applySuggestedVibrations() {
        let modifiers = Set(modifierLayers.map(\.modifierControl))
        func apply(_ mappings: inout [ControllerControlID: ControllerActionMapping], base: Bool) {
            for control in Array(mappings.keys) {
                guard var mapping = mappings[control] else { continue }
                mapping.vibration = Self.suggestedVibration(for: mapping)
                if base && modifiers.contains(control) { mapping.vibration = .softTap }
                mappings[control] = mapping
            }
        }
        apply(&mappings, base: true)
        for index in modifierLayers.indices { apply(&modifierLayers[index].mappings, base: false) }
        for index in applicationMappings.indices {
            apply(&applicationMappings[index].mappings, base: true)
            for layer in applicationMappings[index].modifierLayers.indices {
                apply(&applicationMappings[index].modifierLayers[layer].mappings, base: false)
            }
        }
    }

    static func suggestedVibration(for mapping: ControllerActionMapping) -> ControllerVibration {
        switch mapping.actionType {
        case .leftMouseHold: return .grabRelease
        case .crossEdgeLeft: return .leftPulse
        case .crossEdgeRight: return .rightPulse
        case .crossEdgeUp, .crossEdgeDown: return .thump
        case .keyboardShortcut:
            guard let shortcut = mapping.shortcut else { return .none }
            let modifiers = Set(shortcut.modifiers)
            if shortcut.keyCode == 63 && modifiers.isEmpty { return .softTap }
            if shortcut.keyCode == 21 && modifiers == [.control, .shift, .command] { return .softTap }
            if shortcut.keyCode == 19 && modifiers == [.shift, .command] { return .doubleTap }
            return .none
        default: return .none
        }
    }
}
