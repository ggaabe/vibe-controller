import SwiftUI
import XCTest
@testable import VibeController

@MainActor
final class SetupBannerLayoutTests: XCTestCase {
    func testDriverSetupControlsFitAboveTheScrollableWorkspaceAtMinimumWindowWidth() throws {
        let presentation = try XCTUnwrap(
            VirtualHardwareSetupPhase.needsDriverApproval.bannerPresentation(
                accessibilityRepairRecommended: false
            )
        )
        let availableWidth = MainWindowLayoutMetrics.minimumWidth -
            (MainWindowLayoutMetrics.horizontalPadding * 2)
        let controller = NSHostingController(
            rootView: SetupBannerView(presentation: presentation) { _ in }
                .frame(width: availableWidth)
        )
        let fittingSize = controller.sizeThatFits(
            in: CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        )

        XCTAssertLessThanOrEqual(fittingSize.width, availableWidth)
        XCTAssertLessThanOrEqual(fittingSize.height, 240)
        XCTAssertEqual(presentation.actions.map(\.id), [.openDriverSettings, .refresh])
    }
}
