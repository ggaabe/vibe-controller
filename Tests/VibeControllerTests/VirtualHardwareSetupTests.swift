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
