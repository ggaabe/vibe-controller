import SwiftUI
import XCTest
@testable import VibeController

final class ShareButtonSetupTests: XCTestCase {
    private var truncatedXbox: ControllerSnapshot {
        var snapshot = ControllerSnapshot.disconnected
        snapshot.isConnected = true
        snapshot.controllerFamily = .xbox
        snapshot.shareRequiresFullUSB = true
        return snapshot
    }

    func testOnlyKnownTruncatedXboxInputRequestsSetup() {
        XCTAssertTrue(ShareButtonSetupPolicy.needsSetup(snapshot: truncatedXbox))
        var disconnected = truncatedXbox; disconnected.isConnected = false
        var playStation = truncatedXbox; playStation.controllerFamily = .playStation
        var working = truncatedXbox; working.shareRequiresFullUSB = false
        for snapshot in [disconnected, playStation, working, .disconnected] {
            XCTAssertFalse(ShareButtonSetupPolicy.needsSetup(snapshot: snapshot))
        }
    }

    func testEditorPromptsOnceAndNeverDuplicatesAnActiveSessionRequest() {
        XCTAssertTrue(ShareButtonSetupPolicy.shouldPrompt(snapshot: truncatedXbox,
            sessionEnabled: false, alreadyPrompted: false, fullUSBAvailable: true))
        XCTAssertFalse(ShareButtonSetupPolicy.shouldPrompt(snapshot: truncatedXbox,
            sessionEnabled: false, alreadyPrompted: true, fullUSBAvailable: true))
        XCTAssertFalse(ShareButtonSetupPolicy.shouldPrompt(snapshot: truncatedXbox,
            sessionEnabled: true, alreadyPrompted: false, fullUSBAvailable: true))
        XCTAssertFalse(ShareButtonSetupPolicy.shouldPrompt(snapshot: .disconnected,
            sessionEnabled: false, alreadyPrompted: false, fullUSBAvailable: true))
    }

    func testPublicBuildNeverPromptsEvenWhenShareIsMissing() {
        XCTAssertFalse(ShareButtonSetupPolicy.shouldPrompt(snapshot: truncatedXbox,
            sessionEnabled: false, alreadyPrompted: false, fullUSBAvailable: false))
        let notice = ShareButtonSetupPresentation.unavailable
        XCTAssertFalse(notice.canEnable)
        XCTAssertEqual(notice.title, "Share unavailable on this USB connection")
        XCTAssertTrue(notice.detail.contains("saved Share shortcuts are kept"))
        XCTAssertTrue(notice.detail.contains("Universal Control are unaffected"))
        XCTAssertFalse(notice.detail.contains("Enable Full USB"))
    }

    func testShareEditorAndShareModifierEditsUseTheSameGate() {
        for layer in [ControllerMappingLayer.base, .modifier(.leftShoulder), .modifier(.rightShoulder)] {
            XCTAssertTrue(ShareButtonSetupPolicy.involvesShare(control: .share, layer: layer))
        }
        XCTAssertTrue(ShareButtonSetupPolicy.involvesShare(control: .buttonNorth, layer: .modifier(.share)))
        XCTAssertFalse(ShareButtonSetupPolicy.involvesShare(control: .options, layer: .base))
        XCTAssertFalse(ShareButtonSetupPolicy.involvesShare(control: .buttonNorth, layer: .modifier(.rightShoulder)))
    }

    func testTransportRequirementChangesPublishEvenWhenNoButtonsChange() {
        var available = truncatedXbox
        available.shareRequiresFullUSB = false
        XCTAssertFalse(truncatedXbox.hasSameInputPayload(as: available))
    }

    func testSetupExplainsExclusiveAccessAndRecoveryBeforeAdministratorApproval() {
        let message = ShareButtonSetupPolicy.approvalMessage
        XCTAssertTrue(message.contains("administrator approval"))
        XCTAssertTrue(message.contains("other apps cannot use it"))
        XCTAssertTrue(message.contains("unplug and reconnect"))
        XCTAssertTrue(message.contains("Keep a trackpad"))
    }

    func testOnlyRequiredAndFailedStatesOfferAnotherEnableRequest() {
        for state in [ShareButtonSetupPresentation.State.unavailable, .required, .approval, .connecting, .ready, .retry] {
            let presentation = ShareButtonSetupPresentation(state: state, detail: "Test")
            XCTAssertEqual(presentation.canEnable, state == .required || state == .approval || state == .retry)
        }
    }
}

@MainActor
final class ShareButtonSetupLayoutTests: XCTestCase {
    func testPublicUnavailableNoticeFitsWithoutAnEnableButton() {
        for width: CGFloat in [320, 480, 620] {
            let view = ShareButtonSetupCard(presentation: .unavailable) {
                XCTFail("Public Share notice must not offer activation")
            }.frame(width: width)
            let host = NSHostingController(rootView: view)
            let size = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            XCTAssertLessThanOrEqual(size.width, width)
            XCTAssertLessThanOrEqual(size.height, 200)
            XCTAssertNotNil(ImageRenderer(content: view).cgImage)
        }
    }

    func testSetupCardFitsTheMappingFormAndMinimumWidthWorkspace() {
        for width: CGFloat in [480, 620] {
            for state in [ShareButtonSetupPresentation.State.required, .approval, .connecting, .ready, .retry] {
                let view = ShareButtonSetupCard(presentation: .init(state: state,
                    detail: "This USB connection does not deliver Share presses. Enable Full USB to use Share and its modifier shortcuts.")) {}
                    .frame(width: width)
                let host = NSHostingController(rootView: view)
                let size = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
                XCTAssertLessThanOrEqual(size.width, width)
                XCTAssertLessThanOrEqual(size.height, 180)
                let renderer = ImageRenderer(content: view)
                XCTAssertNotNil(renderer.cgImage)
            }
        }
    }
}
