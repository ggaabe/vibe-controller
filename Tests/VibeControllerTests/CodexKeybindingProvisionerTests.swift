@testable import VibeController
import Foundation
import XCTest

final class CodexKeybindingProvisionerTests: XCTestCase {
    func testUnavailableCodexConfigurationIsLeftAlone() throws {
        let home = temporaryHome()

        let result = try CodexKeybindingProvisioner.ensureForkShortcut(
            homeDirectoryURL: home
        )

        XCTAssertEqual(result, .codexConfigurationUnavailable)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: home.appendingPathComponent(".codex/keybindings.json").path
            )
        )
    }

    func testForkShortcutIsAppendedWithoutReplacingExistingBindings() throws {
        let home = temporaryHome()
        let keybindingsURL = try makeCodexConfiguration(
            at: home,
            keybindings: [[
                "command": "globalDictationHold",
                "key": "RightOption",
                "futureField": true,
            ]]
        )

        let result = try CodexKeybindingProvisioner.ensureForkShortcut(
            homeDirectoryURL: home
        )
        let decoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: keybindingsURL))
                as? [[String: Any]]
        )

        XCTAssertEqual(result, .installed)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0]["command"] as? String, "globalDictationHold")
        XCTAssertEqual(decoded[0]["futureField"] as? Bool, true)
        XCTAssertEqual(decoded[1]["command"] as? String, "forkThread")
        XCTAssertEqual(decoded[1]["key"] as? String, "Command+Alt+Shift+F")
    }

    func testExistingForkShortcutIsNotDuplicated() throws {
        let home = temporaryHome()
        let keybindingsURL = try makeCodexConfiguration(
            at: home,
            keybindings: [[
                "command": "forkThread",
                "key": "command+alt+shift+f",
            ]]
        )

        let result = try CodexKeybindingProvisioner.ensureForkShortcut(
            homeDirectoryURL: home
        )
        let decoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: keybindingsURL))
                as? [[String: Any]]
        )

        XCTAssertEqual(result, .alreadyConfigured)
        XCTAssertEqual(decoded.count, 1)
    }

    func testExistingCustomForkShortcutIsPreservedAlongsideStarterChord() throws {
        let home = temporaryHome()
        let keybindingsURL = try makeCodexConfiguration(
            at: home,
            keybindings: [[
                "command": "forkThread",
                "key": "Command+Shift+Y",
            ]]
        )

        _ = try CodexKeybindingProvisioner.ensureForkShortcut(
            homeDirectoryURL: home
        )
        let decoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: keybindingsURL))
                as? [[String: Any]]
        )

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0]["key"] as? String, "Command+Shift+Y")
        XCTAssertEqual(decoded[1]["key"] as? String, "Command+Alt+Shift+F")
    }

    private func temporaryHome() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
    }

    private func makeCodexConfiguration(
        at home: URL,
        keybindings: [[String: Any]]
    ) throws -> URL {
        let directory = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("keybindings.json")
        let data = try JSONSerialization.data(
            withJSONObject: keybindings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url)
        return url
    }
}
