import CoreGraphics
import Foundation

enum KeyboardModifier: String, Codable, CaseIterable, Hashable, Sendable {
    case control
    case option
    case shift
    case command

    var symbol: String {
        switch self {
        case .control:
            return "^"
        case .option:
            return "⌥"
        case .shift:
            return "⇧"
        case .command:
            return "⌘"
        }
    }

    var keyCode: CGKeyCode {
        switch self {
        case .control:
            return 59
        case .option:
            return 58
        case .shift:
            return 56
        case .command:
            return 55
        }
    }

    static let displayOrder: [KeyboardModifier] = [.control, .option, .shift, .command]
}

struct ShortcutDescriptor: Codable, Hashable, Sendable {
    var keyCode: UInt16
    var modifiers: [KeyboardModifier]

    init(keyCode: UInt16, modifiers: [KeyboardModifier]) {
        self.keyCode = keyCode
        self.modifiers = Self.normalizeModifiers(modifiers)
    }

    var orderedModifiers: [KeyboardModifier] {
        Self.normalizeModifiers(modifiers)
    }

    var isFunctionKeyShortcut: Bool {
        keyCode == 63 && orderedModifiers.isEmpty
    }

    var isModifierOnly: Bool {
        Self.modifierKeyCodes.contains(keyCode) && !isFunctionKeyShortcut
    }

    var displayString: String {
        orderedModifiers.map(\.symbol).joined() + Self.displayName(for: keyCode)
    }

    var duplicateKey: String {
        let modifierKey = orderedModifiers.map(\.rawValue).joined(separator: "+")
        return "\(keyCode)|\(modifierKey)"
    }

    var knownSystemConflictWarning: String? {
        guard let rule = Self.systemConflicts.first(where: { $0.matches(self) }) else {
            return nil
        }
        return rule.warning
    }

    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    static let functionKeyCodes: [Int: UInt16] = [
        1: 122,
        2: 120,
        3: 99,
        4: 118,
        5: 96,
        6: 97,
        7: 98,
        8: 100,
        9: 101,
        10: 109,
        11: 103,
        12: 111,
    ]

    private static let systemConflicts: [SystemConflict] = [
        SystemConflict(
            keyCode: 49,
            modifiers: [.command],
            warning: "⌘Space is commonly reserved by Spotlight."
        ),
        SystemConflict(
            keyCode: 49,
            modifiers: [.control],
            warning: "^Space is commonly used by system input source shortcuts."
        ),
        SystemConflict(
            keyCode: 48,
            modifiers: [.command],
            warning: "⌘Tab is reserved by the macOS app switcher."
        ),
        SystemConflict(
            keyCode: 12,
            modifiers: [.command],
            warning: "⌘Q usually quits the frontmost app."
        ),
    ]

    static func normalizeModifiers(_ modifiers: [KeyboardModifier]) -> [KeyboardModifier] {
        var seen = Set<KeyboardModifier>()
        let deduplicated = modifiers.filter { seen.insert($0).inserted }
        return KeyboardModifier.displayOrder.filter(deduplicated.contains)
    }

    static func displayName(for keyCode: UInt16) -> String {
        if let symbol = specialKeyNames[keyCode] {
            return symbol
        }
        if let glyph = ansiKeyNames[keyCode] {
            return glyph
        }
        return "Key \(keyCode)"
    }

    private static let specialKeyNames: [UInt16: String] = [
        36: "↩",
        48: "⇥",
        49: "Space",
        51: "⌫",
        53: "⎋",
        63: "fn",
        71: "⌧",
        76: "⌤",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        109: "F10",
        111: "F12",
        115: "↖",
        116: "⇞",
        117: "⌦",
        118: "F4",
        119: "↘",
        120: "F2",
        121: "⇟",
        122: "F1",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑",
    ]

    private static let ansiKeyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        50: "`",
    ]

    private struct SystemConflict {
        let keyCode: UInt16
        let modifiers: [KeyboardModifier]
        let warning: String

        func matches(_ shortcut: ShortcutDescriptor) -> Bool {
            shortcut.keyCode == keyCode && shortcut.orderedModifiers == ShortcutDescriptor.normalizeModifiers(modifiers)
        }
    }
}
