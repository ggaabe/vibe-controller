@testable import VibeController
import Foundation
import XCTest

final class ProfileStoreTests: XCTestCase {
    func testDevelopmentBuildKeepsProfilesSeparateFromProduction() {
        XCTAssertEqual(
            ProfileStore.defaultDirectoryName(bundleIdentifier: "com.vibe-controller.app"),
            "Vibe Controller"
        )
        XCTAssertEqual(
            ProfileStore.defaultDirectoryName(bundleIdentifier: "com.vibe-controller.app.dev"),
            "Vibe Controller Dev"
        )
        XCTAssertEqual(
            ProfileStore.defaultDirectoryName(bundleIdentifier: nil),
            "Vibe Controller Dev"
        )
    }

    func testLoadOrCreateSeedsDefaultDocument() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(baseDirectoryURL: directory)

        let document = try store.loadOrCreate()

        XCTAssertEqual(document.version, 2)
        XCTAssertEqual(document.profiles.first?.name, "Gabe's Defaults")
        XCTAssertEqual(document.activeProfileId, "gabes-defaults")
        XCTAssertEqual(document.profiles.first?.mappings[.buttonWest]?.shortcut?.displayString, "⇧⌘2")
        XCTAssertEqual(document.profiles.first?.mappings[.buttonEast]?.shortcut?.displayString, "^⇧⌘4")
        XCTAssertEqual(document.profiles.first?.mappings[.rightTrigger]?.shortcut?.displayString, "fn")
        XCTAssertEqual(document.profiles.first?.mappings[.menu]?.shortcut?.displayString, "⌘T")
        XCTAssertEqual(document.profiles.first?.mappings[.options]?.shortcut?.displayString, "⌘C")
        XCTAssertEqual(document.profiles.first?.mappings[.home]?.shortcut?.displayString, "⌘W")
        XCTAssertEqual(document.profiles.first?.cursor.flickBoostEnabled, false)
        XCTAssertEqual(
            document.profiles.first?.modifierLayer(for: .leftShoulder)?.mappings[.dpadLeft]?.actionType,
            .crossEdgeLeft
        )
        XCTAssertEqual(
            document.profiles.first?.modifierLayer(for: .leftShoulder)?.mappings[.dpadRight]?.actionType,
            .crossEdgeRight
        )
        XCTAssertEqual(
            document.profiles.first?.modifierLayer(for: .leftShoulder)?.mappings[.dpadUp]?.actionType,
            .crossEdgeUp
        )
        XCTAssertEqual(
            document.profiles.first?.modifierLayer(for: .leftShoulder)?.mappings[.dpadDown]?.actionType,
            .crossEdgeDown
        )
        XCTAssertEqual(
            document.profiles.first?.modifierLayer(for: .leftShoulder)?.mappings[.buttonNorth]?.shortcut?.displayString,
            "Space"
        )
        XCTAssertEqual(
            document.profiles.first?.modifierLayer(for: .leftShoulder)?.mappings[.buttonWest]?.shortcut?.displayString,
            "."
        )
        XCTAssertEqual(
            document.profiles.first?.modifierLayer(for: .leftShoulder)?.mappings[.rightShoulder]?.shortcut?.displayString,
            "L⌘ + R⌘"
        )
        XCTAssertEqual(
            document.profiles.first?.modifierLayer(for: .rightShoulder)?.mappings[.dpadLeft]?.actionType,
            .crossEdgeLeft
        )
        XCTAssertEqual(
            document.profiles.first?.modifierLayer(for: .rightShoulder)?.mappings[.dpadRight]?.actionType,
            .crossEdgeRight
        )
        XCTAssertEqual(
            document.profiles.first?.modifierLayer(for: .rightShoulder)?.mappings[.dpadUp]?.actionType,
            .crossEdgeUp
        )
        XCTAssertEqual(
            document.profiles.first?.modifierLayer(for: .rightShoulder)?.mappings[.dpadDown]?.actionType,
            .crossEdgeDown
        )
        XCTAssertEqual(document.profiles.first, ControllerProfile.gabesDefaults)
    }

    func testImportProfileRenamesDuplicateIdentifiers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(baseDirectoryURL: directory)
        let existing = ProfileDocument.defaultDocument

        let imported = ControllerProfile.gabesDefaults
        let importURL = directory.appendingPathComponent("import.json")
        let encoder = JSONEncoder()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(imported).write(to: importURL)

        let merged = try store.importProfile(from: importURL, into: existing)

        XCTAssertEqual(merged.profiles.count, 2)
        XCTAssertEqual(merged.profiles[1].id, "gabes-defaults-2")
        XCTAssertEqual(merged.activeProfileId, "gabes-defaults-2")
    }

    func testLegacyCursorConfigurationDefaultsFlickBoostOn() throws {
        let legacyJSON = """
        {
          "primaryStick": "left",
          "precisionStick": "right",
          "primarySpeed": 2200,
          "precisionSpeed": 560,
          "deadZone": 0.12,
          "responseCurve": 1.8,
          "smoothing": 0.5,
          "accelerationEnabled": true,
          "invertPrimaryX": false,
          "invertPrimaryY": false,
          "invertPrecisionX": false,
          "invertPrecisionY": false,
          "horizontalSpeedMultiplier": 1,
          "verticalSpeedMultiplier": 1
        }
        """

        let configuration = try JSONDecoder().decode(
            CursorConfiguration.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertTrue(configuration.flickBoostEnabled)
    }

    func testCursorConfigurationPersistsDisabledFlickBoost() throws {
        var configuration = ControllerProfile.gabesDefaults.cursor
        configuration.flickBoostEnabled = false

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(CursorConfiguration.self, from: data)

        XCTAssertFalse(decoded.flickBoostEnabled)
    }

    func testLegacyCursorConfigurationEnablesZoomGesture() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(ControllerProfile.gabesDefaults.cursor)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "zoomGestureEnabled")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(CursorConfiguration.self, from: legacyData)

        XCTAssertTrue(decoded.zoomGestureEnabled)
    }

    func testCursorConfigurationPersistsDisabledZoomGesture() throws {
        var configuration = ControllerProfile.gabesDefaults.cursor
        configuration.zoomGestureEnabled = false

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(CursorConfiguration.self, from: data)

        XCTAssertFalse(decoded.zoomGestureEnabled)
    }

    func testLegacyProfileDefaultsToNoModifierLayers() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(ControllerProfile.gabesDefaults)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "modifierLayers")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            ControllerProfile.self,
            from: legacyData
        )

        XCTAssertTrue(decoded.modifierLayers.isEmpty)
    }

    func testModifierLayersRoundTripWithExplicitNoneOverrides() throws {
        var profile = ControllerProfile.gabesDefaults
        profile.modifierLayers = [
            ControllerModifierLayer(
                modifierControl: .leftShoulder,
                mappings: [
                    .dpadRight: ControllerActionMapping(
                        actionType: .keyboardShortcut,
                        shortcut: ShortcutDescriptor(keyCode: 0, modifiers: [.command])
                    ),
                    .dpadLeft: ControllerActionMapping(actionType: .crossEdgeLeft),
                    .dpadUp: ControllerActionMapping(actionType: .crossEdgeUp),
                    .dpadDown: ControllerActionMapping(actionType: .crossEdgeDown),
                    .buttonSouth: ControllerActionMapping(actionType: .none),
                ]
            ),
        ]

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ControllerProfile.self, from: data)

        XCTAssertEqual(decoded.modifierLayers, profile.modifierLayers)
        XCTAssertEqual(
            decoded.modifierLayer(for: .leftShoulder)?.mappings[.buttonSouth]?.actionType,
            ActionType.none
        )
        XCTAssertEqual(
            decoded.modifierLayer(for: .leftShoulder)?.mappings[.dpadLeft]?.actionType,
            ActionType.crossEdgeLeft
        )
        XCTAssertEqual(
            decoded.modifierLayer(for: .leftShoulder)?.mappings[.dpadUp]?.actionType,
            ActionType.crossEdgeUp
        )
        XCTAssertEqual(
            decoded.modifierLayer(for: .leftShoulder)?.mappings[.dpadDown]?.actionType,
            ActionType.crossEdgeDown
        )
    }
}
