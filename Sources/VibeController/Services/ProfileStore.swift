import Foundation
import UniformTypeIdentifiers

final class ProfileStore {
    static let profileFileName = "profiles.json"
    static let activeProfileDefaultsKey = "ActiveProfileID"
    static let enabledDefaultsKey = "ControllerRuntimeEnabled"
    static let productionBundleIdentifier = "com.vibe-controller.app"

    let fileManager: FileManager
    let userDefaults: UserDefaults
    let profilesURL: URL

    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        baseDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults

        if let baseDirectoryURL {
            self.profilesURL = baseDirectoryURL.appendingPathComponent(Self.profileFileName)
        } else {
            let appSupport = try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directoryName = Self.defaultDirectoryName(
                bundleIdentifier: Bundle.main.bundleIdentifier
            )
            let directory = (appSupport ?? URL(fileURLWithPath: NSTemporaryDirectory()))
                .appendingPathComponent(directoryName, isDirectory: true)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            self.profilesURL = directory.appendingPathComponent(Self.profileFileName)
        }
    }

    static func defaultDirectoryName(bundleIdentifier: String?) -> String {
        bundleIdentifier == productionBundleIdentifier
            ? "Vibe Controller"
            : "Vibe Controller Dev"
    }

    func loadOrCreate() throws -> ProfileDocument {
        guard fileManager.fileExists(atPath: profilesURL.path) else {
            let document = ProfileDocument.defaultDocument
            try save(document)
            return document
        }

        let data = try Data(contentsOf: profilesURL)
        let decoder = JSONDecoder()
        let document = try decoder.decode(ProfileDocument.self, from: data)
        return normalize(document)
    }

    func save(_ document: ProfileDocument) throws {
        let normalized = normalize(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(normalized)
        try fileManager.createDirectory(
            at: profilesURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: profilesURL, options: .atomic)
    }

    func effectiveActiveProfileID(for document: ProfileDocument) -> String {
        userDefaults.string(forKey: Self.activeProfileDefaultsKey) ?? document.activeProfileId
    }

    func setActiveProfileID(_ profileID: String) {
        userDefaults.set(profileID, forKey: Self.activeProfileDefaultsKey)
    }

    func loadEnabledState() -> Bool {
        if userDefaults.object(forKey: Self.enabledDefaultsKey) == nil {
            return true
        }
        return userDefaults.bool(forKey: Self.enabledDefaultsKey)
    }

    func setEnabledState(_ isEnabled: Bool) {
        userDefaults.set(isEnabled, forKey: Self.enabledDefaultsKey)
    }

    func exportProfile(_ profile: ControllerProfile, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        try data.write(to: url, options: .atomic)
    }

    func importProfile(from url: URL, into document: ProfileDocument) throws -> ProfileDocument {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()

        if let importedProfile = try? decoder.decode(ControllerProfile.self, from: data) {
            return merge(profile: importedProfile, into: document)
        }

        let importedDocument = try decoder.decode(ProfileDocument.self, from: data)
        var merged = document
        for profile in importedDocument.profiles {
            merged = merge(profile: profile, into: merged)
        }
        return normalize(merged)
    }

    func merge(profile: ControllerProfile, into document: ProfileDocument) -> ProfileDocument {
        var merged = normalize(document)
        let existingIDs = Set(merged.profiles.map(\.id))
        let profileID = uniqueProfileID(from: profile.id, existingIDs: existingIDs)
        let profileName = uniqueProfileName(from: profile.name, existingNames: Set(merged.profiles.map(\.name)))
        let imported = ControllerProfile(
            id: profileID,
            name: profileName,
            cursor: profile.cursor,
            mappings: profile.mappings,
            modifierLayers: profile.modifierLayers,
            applicationMappings: profile.applicationMappings
        )
        merged.profiles.append(imported)
        merged.activeProfileId = imported.id
        return merged
    }

    private func normalize(_ document: ProfileDocument) -> ProfileDocument {
        var normalized = document
        if document.version < 3,
           let gabeIndex = normalized.profiles.firstIndex(where: {
               $0.id == ControllerProfile.gabesDefaults.id
           }),
           normalized.profiles[gabeIndex].applicationMapping(
               for: ApplicationMappingOverrides.codexBundleIdentifier
           ) == nil {
            normalized.profiles[gabeIndex].applicationMappings.append(
                ControllerProfile.codexStarterApplicationMappings
            )
        }
        if document.version < 4 {
            let legacyCodexRightTrigger = ControllerActionMapping(
                actionType: .keyboardShortcut,
                shortcut: ShortcutDescriptor(keyCode: 61, modifiers: []),
                triggerMode: .holdWhilePressed
            )
            for profileIndex in normalized.profiles.indices {
                guard let applicationIndex = normalized.profiles[profileIndex]
                    .applicationMappings.firstIndex(where: {
                        $0.bundleIdentifier == ApplicationMappingOverrides.codexBundleIdentifier
                    }),
                    normalized.profiles[profileIndex]
                    .applicationMappings[applicationIndex]
                    .mappings[.rightTrigger] == legacyCodexRightTrigger else {
                    continue
                }
                normalized.profiles[profileIndex]
                    .applicationMappings[applicationIndex]
                    .mappings.removeValue(forKey: .rightTrigger)
            }
        }
        if document.version < 5,
           let gabeIndex = normalized.profiles.firstIndex(where: {
               $0.id == ControllerProfile.gabesDefaults.id
           }),
           let applicationIndex = normalized.profiles[gabeIndex]
               .applicationMappings.firstIndex(where: {
                   $0.bundleIdentifier == ApplicationMappingOverrides.codexBundleIdentifier
               }) {
            // Version 5 deliberately pares Gabe's Codex setup back to the
            // small, opinionated starter. Every omitted cell falls through to
            // All Apps, including the existing Escape, Return, and dictation
            // controls.
            normalized.profiles[gabeIndex]
                .applicationMappings[applicationIndex] =
                ControllerProfile.codexStarterApplicationMappings
        }
        normalized.version = max(document.version, ProfileDocument.defaultDocument.version)
        if normalized.profiles.isEmpty {
            normalized.profiles = ProfileDocument.defaultDocument.profiles
        }
        if !normalized.profiles.contains(where: { $0.id == normalized.activeProfileId }) {
            normalized.activeProfileId = normalized.profiles[0].id
        }
        return normalized
    }

    private func uniqueProfileID(from candidate: String, existingIDs: Set<String>) -> String {
        guard existingIDs.contains(candidate) else {
            return candidate
        }
        var suffix = 2
        while existingIDs.contains("\(candidate)-\(suffix)") {
            suffix += 1
        }
        return "\(candidate)-\(suffix)"
    }

    private func uniqueProfileName(from candidate: String, existingNames: Set<String>) -> String {
        guard existingNames.contains(candidate) else {
            return candidate
        }
        var suffix = 2
        while existingNames.contains("\(candidate) \(suffix)") {
            suffix += 1
        }
        return "\(candidate) \(suffix)"
    }
}

extension UTType {
    static let vibeControllerProfile = UTType(exportedAs: "com.vibe-controller.profile", conformingTo: .json)
}
