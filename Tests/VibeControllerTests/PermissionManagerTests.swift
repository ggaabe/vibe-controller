import XCTest
import Combine
@testable import VibeController

@MainActor
final class PermissionManagerTests: XCTestCase {
    func testUnchangedPermissionPollDoesNotInvalidateTheControllerLayout() {
        let manager = PermissionManager(userDefaults: makeDefaults(), pollingInterval: nil,
                                        trustStatus: { true }, promptRequest: { true })
        var updates = 0
        let observation = manager.objectWillChange.sink { updates += 1 }
        manager.refresh()
        manager.refresh()
        XCTAssertEqual(updates, 0)
        withExtendedLifetime(observation) {}
    }

    func testFirstDeniedRequestDoesNotClaimAStaleGrant() {
        let defaults = makeDefaults()
        let manager = PermissionManager(
            userDefaults: defaults,
            pollingInterval: nil,
            trustStatus: { false },
            promptRequest: { false }
        )

        XCTAssertFalse(manager.accessibilityTrusted)
        XCTAssertFalse(manager.accessibilityRepairRecommended)
    }

    func testPreviouslyTrustedAppExplainsHowToRepairAStaleGrant() {
        let defaults = makeDefaults()
        var trusted = true
        let manager = PermissionManager(
            userDefaults: defaults,
            pollingInterval: nil,
            trustStatus: { trusted },
            promptRequest: { trusted }
        )

        XCTAssertTrue(manager.accessibilityTrusted)
        trusted = false
        manager.refresh()

        XCTAssertFalse(manager.accessibilityTrusted)
        XCTAssertTrue(manager.accessibilityRepairRecommended)
    }

    func testRestoredTrustClearsRepairState() {
        let defaults = makeDefaults()
        var trusted = true
        let manager = PermissionManager(
            userDefaults: defaults,
            pollingInterval: nil,
            trustStatus: { trusted },
            promptRequest: { trusted }
        )

        trusted = false
        manager.refresh()
        XCTAssertTrue(manager.accessibilityRepairRecommended)

        trusted = true
        manager.refresh()
        XCTAssertTrue(manager.accessibilityTrusted)
        XCTAssertFalse(manager.accessibilityRepairRecommended)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PermissionManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
