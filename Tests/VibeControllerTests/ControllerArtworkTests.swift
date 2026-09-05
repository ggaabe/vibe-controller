import AppKit
import SwiftUI
import XCTest

@testable import VibeController

@MainActor
final class ControllerArtworkTests: XCTestCase {
    func testBothVectorResourcesLoadAndRasterizeAtRetinaResolution() throws {
        for family in [ControllerFamily.xbox, .playStation] {
            let image = try XCTUnwrap(ControllerArtwork.image(for: family))
            XCTAssertEqual(image.size, ControllerArtwork.size)
            XCTAssertTrue(image.representations.contains { String(describing: type(of: $0)).contains("SVG") })

            let renderer = ImageRenderer(
                content: ControllerArtworkView(family: family)
                    .frame(width: 1000, height: 660))
            renderer.scale = 2
            let bitmap = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(bitmap.width, 2000)
            XCTAssertEqual(bitmap.height, 1320)
        }
    }

    func testEverySupportedButtonHasExactlyOneHitRegion() {
        for family in [ControllerFamily.xbox, .playStation] {
            let controls = ControllerArtwork.controls(for: family).map(\.control)
            let expected = ControllerControlID.mappingControls.filter {
                family == .playStation || $0 != .touchpadButton
            }
            XCTAssertEqual(Set(controls), Set(expected))
            XCTAssertEqual(controls.count, Set(controls).count)
        }
    }

    func testHitRegionsStayInsideArtworkAndDoNotOverlap() {
        let bounds = CGRect(origin: .zero, size: ControllerArtwork.size)
        for family in [ControllerFamily.xbox, .playStation] {
            let regions = ControllerArtwork.controls(for: family)
            for (index, region) in regions.enumerated() {
                let rect = frame(for: region)
                XCTAssertTrue(bounds.contains(rect), "\(family) \(region.control) outside artwork")
                for other in regions.dropFirst(index + 1) {
                    XCTAssertFalse(
                        rect.intersects(frame(for: other)),
                        "\(family) \(region.control) overlaps \(other.control)")
                }
            }
        }
    }

    func testPlayStationUsesSymmetricSticksAndXboxUsesOffsetSticks() throws {
        func stick(_ control: ControllerControlID, _ family: ControllerFamily) throws -> CGPoint {
            try XCTUnwrap(ControllerArtwork.controls(for: family).first { $0.control == control }).center
        }
        let psLeft = try stick(.leftThumbstickButton, .playStation)
        let psRight = try stick(.rightThumbstickButton, .playStation)
        XCTAssertEqual(psLeft.y, psRight.y)
        XCTAssertEqual(psLeft.x, 1000 - psRight.x)
        XCTAssertLessThan(
            try stick(.leftThumbstickButton, .xbox).y,
            try stick(.rightThumbstickButton, .xbox).y)
    }

    func testGenericControllersUseXboxFallbackArtwork() throws {
        XCTAssertTrue(
            try XCTUnwrap(ControllerArtwork.image(for: .generic)) === XCTUnwrap(ControllerArtwork.image(for: .xbox)))
    }

    func testInteractiveMapFitsCompactAndLargeLayoutsInBothAppearances() throws {
        for family in [ControllerFamily.xbox, .playStation] {
            for scheme in [ColorScheme.light, .dark] {
                for width in [CGFloat(400), 800] {
                    let height = width * 0.66
                    let view = ControllerHardwareMap(
                        family: family, pressedControls: [.buttonSouth],
                        overriddenControls: [.menu], modifierControl: .leftShoulder,
                        leftStick: StickSnapshot(x: 0.5, y: -0.5), rightStick: StickSnapshot(),
                        actionDescription: { $0.displayName(for: family) },
                        onSelect: { _ in }, onHover: { _ in }
                    )
                    .frame(width: width, height: height)
                    .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: view)
                    let result = try XCTUnwrap(renderer.cgImage)
                    XCTAssertEqual(result.width, Int(width))
                    XCTAssertEqual(result.height, Int(height))
                }
            }
        }
    }

    private func frame(for region: HardwareControlRegion) -> CGRect {
        CGRect(
            x: region.center.x - region.size.width / 2,
            y: region.center.y - region.size.height / 2,
            width: region.size.width, height: region.size.height)
    }
}
