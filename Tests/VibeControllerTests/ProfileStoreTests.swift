@testable import VibeController
import Foundation
import XCTest

final class ProfileStoreTests: XCTestCase {
    func testLoadOrCreateSeedsDefaultDocument() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(baseDirectoryURL: directory)

        let document = try store.loadOrCreate()

        XCTAssertEqual(document.version, 1)
        XCTAssertEqual(document.profiles.first?.name, "Gabe's Defaults")
        XCTAssertEqual(document.activeProfileId, "gabes-defaults")
        XCTAssertEqual(document.profiles.first?.mappings[.buttonWest]?.shortcut?.displayString, "⇧⌘2")
        XCTAssertEqual(document.profiles.first?.mappings[.buttonEast]?.shortcut?.displayString, "^⇧⌘4")
        XCTAssertEqual(document.profiles.first?.mappings[.rightTrigger]?.shortcut?.displayString, "fn")
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
}
