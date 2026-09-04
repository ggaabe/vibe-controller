import Foundation

enum CodexKeybindingProvisionResult: Equatable {
    case codexConfigurationUnavailable
    case alreadyConfigured
    case installed
}

enum CodexKeybindingProvisioner {
    static let forkCommand = "forkThread"
    static let forkAccelerator = "Command+Alt+Shift+F"
    static let forkShortcut = ShortcutDescriptor(
        keyCode: 3,
        modifiers: [.option, .shift, .command]
    )

    static func ensureForkShortcut(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> CodexKeybindingProvisionResult {
        let codexDirectoryURL = homeDirectoryURL.appendingPathComponent(
            ".codex",
            isDirectory: true
        )
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: codexDirectoryURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return .codexConfigurationUnavailable
        }

        let keybindingsURL = codexDirectoryURL.appendingPathComponent("keybindings.json")
        var keybindings: [[String: Any]]
        if fileManager.fileExists(atPath: keybindingsURL.path) {
            let data = try Data(contentsOf: keybindingsURL)
            guard let decoded = try JSONSerialization.jsonObject(with: data)
                as? [[String: Any]] else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            keybindings = decoded
        } else {
            keybindings = []
        }

        let alreadyConfigured = keybindings.contains { keybinding in
            guard let command = keybinding["command"] as? String,
                  let key = keybinding["key"] as? String else {
                return false
            }
            return command == forkCommand &&
                key.caseInsensitiveCompare(forkAccelerator) == .orderedSame
        }
        guard !alreadyConfigured else {
            return .alreadyConfigured
        }

        // Codex supports more than one binding for a command. Appending keeps
        // any shortcut the user already chose while guaranteeing the starter
        // profile has a stable chord it can send.
        keybindings.append([
            "command": forkCommand,
            "key": forkAccelerator,
        ])
        let encoded = try JSONSerialization.data(
            withJSONObject: keybindings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try encoded.write(to: keybindingsURL, options: .atomic)
        return .installed
    }
}
