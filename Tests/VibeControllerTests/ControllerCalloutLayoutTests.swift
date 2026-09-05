import SwiftUI
import XCTest

@testable import VibeController

@MainActor
final class ControllerCalloutLayoutTests: XCTestCase {
    func testEveryPhysicalControlHasOneVisibleLabel() {
        for family in [ControllerFamily.xbox, .playStation, .generic] {
            let layout = ControllerCalloutLayout(family: family, size: CGSize(width: 814, height: 448))
            let controls = layout.callouts.map(\.control)
            XCTAssertEqual(Set(controls), Set(ControllerArtwork.controls(for: family).map(\.control)))
            XCTAssertEqual(controls.count, Set(controls).count)
        }
    }

    func testLabelsFitWithoutCoveringEachOtherOrArtworkAtSupportedWindowWidths() {
        for family in [ControllerFamily.xbox, .playStation] {
            for width in [CGFloat(814), 1000, 1130] {
                for height in [ControllerCalloutLayout.minimumHeight, 504] {
                    let size = CGSize(width: width, height: height)
                    let layout = ControllerCalloutLayout(family: family, size: size)
                    for (index, callout) in layout.callouts.enumerated() {
                        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(callout.labelFrame))
                        XCTAssertGreaterThanOrEqual(callout.labelFrame.height, 40)
                        XCTAssertFalse(callout.labelFrame.intersects(layout.artworkFrame))
                        for other in layout.callouts.dropFirst(index + 1) {
                            XCTAssertFalse(callout.labelFrame.intersects(other.labelFrame))
                        }
                    }
                }
            }
        }
    }

    func testConnectorsEndAtTheMatchingPhysicalButton() throws {
        for family in [ControllerFamily.xbox, .playStation] {
            let layout = ControllerCalloutLayout(family: family, size: CGSize(width: 814, height: 448))
            for callout in layout.callouts {
                let region = try XCTUnwrap(
                    ControllerArtwork.controls(for: family).first {
                        $0.control == callout.control
                    })
                XCTAssertEqual(
                    callout.anchor.x,
                    layout.artworkFrame.minX + region.center.x * layout.artworkFrame.width / 1000,
                    accuracy: 0.001)
                XCTAssertEqual(
                    callout.anchor.y,
                    layout.artworkFrame.minY + region.center.y * layout.artworkFrame.height / 660,
                    accuracy: 0.001)
            }
        }
    }

    func testAnnotatedMapRendersAllActionsInBothAppearances() throws {
        for family in [ControllerFamily.xbox, .playStation] {
            for scheme in [ColorScheme.light, .dark] {
                var describedControls: Set<ControllerControlID> = []
                let hardware = ControllerHardwareMap(
                    family: family, pressedControls: [.buttonSouth],
                    overriddenControls: [.menu], focusedControl: .leftTrigger,
                    modifierControl: .leftShoulder,
                    leftStick: StickSnapshot(), rightStick: StickSnapshot(),
                    actionDescription: { control in
                        describedControls.insert(control)
                        return "All Apps · Left Mouse Hold (drag)"
                    },
                    onSelect: { _ in }, onHover: { _ in })
                let renderer = ImageRenderer(
                    content: ControllerAnnotatedMap(
                        hardware: hardware, hoveredControl: .leftTrigger
                    )
                    .frame(width: 814, height: ControllerCalloutLayout.minimumHeight)
                    .environment(\.colorScheme, scheme))
                let bitmap = try XCTUnwrap(renderer.cgImage)
                XCTAssertEqual(bitmap.width, 814)
                XCTAssertEqual(bitmap.height, Int(ControllerCalloutLayout.minimumHeight))
                XCTAssertEqual(describedControls, Set(ControllerArtwork.controls(for: family).map(\.control)))
            }
        }
    }
}
