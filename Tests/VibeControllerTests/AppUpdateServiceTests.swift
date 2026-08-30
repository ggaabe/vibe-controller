import SwiftUI
import XCTest
@testable import VibeController

final class AppUpdateServiceTests: XCTestCase {
    func testSemanticVersionsCompareNumerically() throws {
        XCTAssertLessThan(try XCTUnwrap(AppVersion("0.3.9")), try XCTUnwrap(AppVersion("0.4.0")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.9.9")), try XCTUnwrap(AppVersion("2.0.0")))
        XCTAssertEqual(AppVersion("v0.3.1"), AppVersion("0.3.1"))
        XCTAssertNil(AppVersion("0.3"))
        XCTAssertNil(AppVersion("0.3.beta"))
    }

    func testResolverSelectsOnlyTheSignedDistributionDiskImage() throws {
        let release = GitHubRelease(
            tagName: "v0.4.0",
            htmlURL: "https://github.com/ggaabe/vibe-controller/releases/tag/v0.4.0",
            draft: false,
            prerelease: false,
            assets: [
                .init(
                    name: "Vibe-Controller-0.4.0-arm64-development.dmg",
                    browserDownloadURL: "https://example.com/development.dmg"
                ),
                .init(
                    name: "Vibe-Controller-0.4.0-arm64.dmg",
                    browserDownloadURL: "https://example.com/release.dmg"
                ),
                .init(
                    name: "SHA256SUMS.txt",
                    browserDownloadURL: "https://example.com/SHA256SUMS.txt"
                ),
            ]
        )

        let result = try AppUpdateService.resolve(
            release: release,
            currentVersion: try XCTUnwrap(AppVersion("0.3.1"))
        )
        guard case .available(let update) = result else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(update.version, AppVersion("0.4.0"))
        XCTAssertEqual(update.diskImageFilename, "Vibe-Controller-0.4.0-arm64.dmg")
        XCTAssertEqual(update.diskImageURL.absoluteString, "https://example.com/release.dmg")
    }

    func testResolverDoesNotDowngradeAPreReleaseBuild() throws {
        let release = GitHubRelease(
            tagName: "v0.3.0",
            htmlURL: "https://github.com/ggaabe/vibe-controller/releases/tag/v0.3.0",
            draft: false,
            prerelease: false,
            assets: []
        )

        let result = try AppUpdateService.resolve(
            release: release,
            currentVersion: try XCTUnwrap(AppVersion("0.3.1"))
        )
        XCTAssertEqual(result, .upToDate(latestVersion: try XCTUnwrap(AppVersion("0.3.0"))))
    }

    func testChecksumParserFindsTheExactDiskImage() {
        let checksums = """
        aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  Vibe-Controller-0.4.0-arm64.dmg
        bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  VibeController-VirtualHardwareSupport-0.4.0-arm64.pkg
        """

        XCTAssertEqual(
            AppUpdateService.expectedChecksum(
                named: "Vibe-Controller-0.4.0-arm64.dmg",
                in: checksums
            ),
            String(repeating: "a", count: 64)
        )
        XCTAssertNil(
            AppUpdateService.expectedChecksum(
                named: "Vibe-Controller-0.4.1-arm64.dmg",
                in: checksums
            )
        )
    }

    func testAutomaticChecksAreLimitedToOncePerDay() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(AppUpdateService.shouldAutomaticallyCheck(lastCheckedAt: nil, now: now))
        XCTAssertFalse(
            AppUpdateService.shouldAutomaticallyCheck(
                lastCheckedAt: now.addingTimeInterval(-(23 * 60 * 60)),
                now: now
            )
        )
        XCTAssertTrue(
            AppUpdateService.shouldAutomaticallyCheck(
                lastCheckedAt: now.addingTimeInterval(-(24 * 60 * 60)),
                now: now
            )
        )
    }

    func testUpdatePresentationOffersAnInPlaceInstallForReleaseBuilds() throws {
        let update = AvailableAppUpdate(
            version: try XCTUnwrap(AppVersion("0.4.0")),
            releasePageURL: URL(string: "https://example.com/release")!,
            diskImageURL: URL(string: "https://example.com/release.dmg")!,
            diskImageFilename: "Vibe-Controller-0.4.0-arm64.dmg",
            checksumsURL: URL(string: "https://example.com/checksums")!
        )

        let releasePresentation = AppUpdatePresentation.make(
            state: .available(update),
            currentVersion: "0.3.1",
            canInstallAutomatically: true
        )
        let developmentPresentation = AppUpdatePresentation.make(
            state: .available(update),
            currentVersion: "0.3.1",
            canInstallAutomatically: false
        )

        XCTAssertEqual(releasePresentation.buttonTitle, "Update Now")
        XCTAssertTrue(releasePresentation.isProminent)
        XCTAssertEqual(developmentPresentation.buttonTitle, "View Release")
    }

    func testPublishedReleasePassesTheFullSecureStagingPathWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["VIBE_CONTROLLER_LIVE_UPDATE_TEST"] == "1" else {
            throw XCTSkip("Set VIBE_CONTROLLER_LIVE_UPDATE_TEST=1 to validate the published release.")
        }
        let installedAppURL = URL(fileURLWithPath: "/Applications/Vibe Controller.app")
        guard FileManager.default.fileExists(atPath: installedAppURL.path) else {
            throw XCTSkip("The signed production app is not installed.")
        }

        let service = AppUpdateService()
        let result = try await service.checkForUpdate(currentVersion: "0.2.0")
        guard case .available(let update) = result else {
            return XCTFail("Expected the current public release to be newer than v0.2.0")
        }

        let prepared = try await service.prepare(
            update: update,
            currentApplicationURL: installedAppURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.stagedApplicationURL.path))
        await service.discard(prepared)
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.stagedApplicationURL.path))
    }

    func testAbandonedUpdateArtifactsAreCleanedOnTheNextLaunch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeControllerUpdateCleanup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let current = root.appendingPathComponent("Vibe Controller.app")
        let staged = root.appendingPathComponent(".Vibe Controller.update-test.app")
        let backup = root.appendingPathComponent(".Vibe Controller.backup-test.app")
        let unrelated = root.appendingPathComponent("Keep Me.app")
        for url in [current, staged, backup, unrelated] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        let service = AppUpdateService()
        await service.removeAbandonedArtifacts(beside: current)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }
}

@MainActor
final class AppUpdateControlLayoutTests: XCTestCase {
    func testUpdateControlFitsTheMinimumWindowFooter() {
        let presentation = AppUpdatePresentation.make(
            state: .idle,
            currentVersion: "0.3.1",
            canInstallAutomatically: true
        )
        let controller = NSHostingController(
            rootView: AppUpdateControlView(presentation: presentation) {}
        )
        let fittingSize = controller.sizeThatFits(
            in: CGSize(width: 360, height: CGFloat.greatestFiniteMagnitude)
        )

        XCTAssertLessThanOrEqual(fittingSize.width, 360)
        XCTAssertLessThanOrEqual(fittingSize.height, 56)
    }
}
