@testable import VibeController
import Foundation
import XCTest

final class ProfileStoreTests: XCTestCase {
    func testLoadOrCreateSeedsDefaultDocument() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(baseDirectoryURL: directory)

        let document = try store.loadOrCreate()

        XCTAssertEqual(document.version, 1)
        XCTAssertEqual(document.profiles.first?.name, "Desktop Control")
    }

    func testImportProfileRenamesDuplicateIdentifiers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(baseDirectoryURL: directory)
        let existing = ProfileDocument.defaultDocument

        let imported = ControllerProfile.desktopControl
        let importURL = directory.appendingPathComponent("import.json")
        let encoder = JSONEncoder()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(imported).write(to: importURL)

        let merged = try store.importProfile(from: importURL, into: existing)

        XCTAssertEqual(merged.profiles.count, 2)
        XCTAssertEqual(merged.profiles[1].id, "desktop-control-2")
        XCTAssertEqual(merged.activeProfileId, "desktop-control-2")
    }
}
