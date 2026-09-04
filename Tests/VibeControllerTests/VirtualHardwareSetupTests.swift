import XCTest
@testable import VibeController

final class VirtualHardwareSetupTests: XCTestCase {
    func testAccessibilityIsAlwaysTheFirstGate() {
        let snapshot = makeSnapshot(
            accessibilityTrusted: false,
            helperInstalledSecurely: true,
            driverManagerInstalled: true,
            driverActivated: true,
            virtualHardwareReady: true
        )

        XCTAssertEqual(snapshot.phase, .needsAccessibility)
    }

    func testMissingSupportOpensTheBundledInstaller() {
        XCTAssertEqual(makeSnapshot().phase, .needsSupportInstall)
    }

    func testMissingBundledInstallerIsReported() {
        let snapshot = makeSnapshot(bundledInstallerAvailable: false)
        XCTAssertEqual(snapshot.phase, .missingBundledInstaller)
    }

    func testInstalledSupportWaitsForInitialDriverStatus() {
        let snapshot = makeSnapshot(
            helperInstalledSecurely: true,
            driverManagerInstalled: true
        )

        XCTAssertEqual(snapshot.phase, .checking)
    }

    func testInstalledSupportRequestsDriverApproval() {
        let snapshot = makeSnapshot(
            helperInstalledSecurely: true,
            driverManagerInstalled: true,
            driverStatusKnown: true
        )

        XCTAssertEqual(snapshot.phase, .needsDriverApproval)
    }

    func testMismatchedDriverRequestsBundledUpdate() {
        let snapshot = makeSnapshot(
            helperInstalledSecurely: true,
            driverManagerInstalled: true,
            driverStatusKnown: true,
            driverVersionMismatched: true
        )

        XCTAssertEqual(snapshot.phase, .driverVersionMismatch)
    }

    func testKnownSupportMismatchDoesNotRemainStuckChecking() {
        let snapshot = makeSnapshot(
            helperInstalledSecurely: true,
            driverManagerInstalled: true,
            driverStatusKnown: false,
            driverVersionMismatched: true
        )

        XCTAssertEqual(snapshot.phase, .driverVersionMismatch)
        XCTAssertTrue(
            PrivilegedVirtualHIDBridge.requiresSupportUpdate(
                forOutputLine: "ERROR unauthorized parent process"
            )
        )
    }

    func testActivatedDriverWaitsForVirtualDevices() {
        let snapshot = makeSnapshot(
            helperInstalledSecurely: true,
            driverManagerInstalled: true,
            driverStatusKnown: true,
            driverActivated: true
        )

        XCTAssertEqual(snapshot.phase, .startingVirtualHardware)
    }

    func testReadyDevicesCompleteSetup() {
        let snapshot = makeSnapshot(
            helperInstalledSecurely: true,
            driverManagerInstalled: true,
            driverStatusKnown: true,
            driverActivated: true,
            virtualHardwareReady: true
        )

        XCTAssertEqual(snapshot.phase, .ready)
    }

    func testDriverApprovalBannerUsesTheExactSystemSettingsPathAndKeepsActionsVisible() throws {
        let presentation = try XCTUnwrap(
            VirtualHardwareSetupPhase.needsDriverApproval.bannerPresentation(
                accessibilityRepairRecommended: false
            )
        )

        XCTAssertEqual(presentation.stepLabel, "Step 3 of 3")
        XCTAssertTrue(
            presentation.instructions.contains {
                $0.contains(".Karabiner‑VirtualHIDDevice‑Manager Driver Extension") &&
                    $0.contains("Show Detail")
            }
        )
        XCTAssertTrue(
            presentation.instructions.contains {
                $0.contains("Provides additional functionality for system drivers")
            }
        )
        XCTAssertEqual(presentation.actions.first?.id, .openDriverSettings)
        XCTAssertTrue(presentation.actions.contains { $0.id == .refresh })
    }

    func testAccessibilityBannerExplainsHowToRepairAnEnabledButStaleGrant() throws {
        let presentation = try XCTUnwrap(
            VirtualHardwareSetupPhase.needsAccessibility.bannerPresentation(
                accessibilityRepairRecommended: true
            )
        )

        XCTAssertEqual(presentation.title, "Refresh Accessibility access")
        XCTAssertTrue(presentation.instructions.contains { $0.contains("click −") })
        XCTAssertEqual(presentation.actions.first?.id, .openAccessibilitySettings)
    }

    func testEveryIncompleteSetupPhaseHasAReachableAction() {
        let phases: [VirtualHardwareSetupPhase] = [
            .checking,
            .needsAccessibility,
            .needsSupportInstall,
            .missingBundledInstaller,
            .driverVersionMismatch,
            .needsDriverApproval,
            .startingVirtualHardware
        ]

        for phase in phases {
            let presentation = phase.bannerPresentation(accessibilityRepairRecommended: false)
            XCTAssertFalse(presentation?.actions.isEmpty ?? true, "Missing action for \(phase)")
        }
        XCTAssertNil(VirtualHardwareSetupPhase.ready.bannerPresentation(accessibilityRepairRecommended: false))
    }

    private func makeSnapshot(
        accessibilityTrusted: Bool = true,
        helperInstalledSecurely: Bool = false,
        driverManagerInstalled: Bool = false,
        bundledInstallerAvailable: Bool = true,
        driverStatusKnown: Bool = false,
        driverActivated: Bool = false,
        driverVersionMismatched: Bool = false,
        virtualHardwareReady: Bool = false
    ) -> VirtualHardwareSetupSnapshot {
        VirtualHardwareSetupSnapshot(
            accessibilityTrusted: accessibilityTrusted,
            helperInstalledSecurely: helperInstalledSecurely,
            driverManagerInstalled: driverManagerInstalled,
            bundledInstallerAvailable: bundledInstallerAvailable,
            driverStatusKnown: driverStatusKnown,
            driverActivated: driverActivated,
            driverVersionMismatched: driverVersionMismatched,
            virtualHardwareReady: virtualHardwareReady
        )
    }
}
