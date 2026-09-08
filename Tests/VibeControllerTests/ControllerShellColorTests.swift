import AppKit
import SwiftUI
import XCTest
@testable import VibeController

@MainActor
final class ControllerShellColorTests: XCTestCase {
    func testEveryColorLoadsAsVectorArtworkAndUsesTheRequestedShellPalette() throws {
        for family in [ControllerFamily.xbox, .playStation] {
            for color in ControllerShellColor.allCases {
                let image = try XCTUnwrap(ControllerArtwork.image(for: family, shellColor: color))
                XCTAssertEqual(image.size, ControllerArtwork.size)
                XCTAssertTrue(image.representations.contains { String(describing: type(of: $0)).contains("SVG") })
                let document = try XMLDocument(data: XCTUnwrap(ControllerArtwork.svgData(for: family, shellColor: color)))
                let gradient = family == .playStation ? "white" : "shell"
                let colors = try document.nodes(forXPath: "//*[@id='\(gradient)']/*/@stop-color").compactMap(\.stringValue)
                XCTAssertEqual(colors, color.palette(for: family))
            }
        }
    }

    func testRecoloringPreservesButtonMaterialsSymbolsAndGeometry() throws {
        for family in [ControllerFamily.xbox, .playStation] {
            let original = try XMLDocument(data: XCTUnwrap(ControllerArtwork.svgData(for: family, shellColor: .original)))
            for color in ControllerShellColor.allCases {
                let changed = try XMLDocument(data: XCTUnwrap(ControllerArtwork.svgData(for: family, shellColor: color)))
                for query in [
                    "//*[@id='key' or @id='cap' or @id='trigger' or @id='core']",
                    "//@d", "//@cx", "//@cy", "//@r", "//@x", "//@y", "//@width", "//@height", "//text",
                ] {
                    XCTAssertEqual(
                        try original.nodes(forXPath: query).map(\.xmlString),
                        try changed.nodes(forXPath: query).map(\.xmlString), "\(family) \(color) changed \(query)")
                }
            }
        }
    }

    func testArtworkVariantsAreCachedIncludingGenericFallback() throws {
        let blue = try XCTUnwrap(ControllerArtwork.image(for: .xbox, shellColor: .blue))
        XCTAssertTrue(blue === ControllerArtwork.image(for: .xbox, shellColor: .blue))
        XCTAssertTrue(blue === ControllerArtwork.image(for: .generic, shellColor: .blue))
        XCTAssertFalse(blue === ControllerArtwork.image(for: .xbox, shellColor: .pink))
    }

    func testColoredMapsRenderDistinctShellsWithLiveInputInLightAndDarkModes() throws {
        for family in [ControllerFamily.xbox, .playStation] {
            for scheme in [ColorScheme.light, .dark] {
                var renderedColors = Set<Data>()
                for color in ControllerShellColor.allCases where color != .original {
                    let neutral = try render(family: family, color: color, scheme: scheme, active: false)
                    renderedColors.insert(neutral)
                    let active = try render(family: family, color: color, scheme: scheme, active: true)
                    XCTAssertNotEqual(neutral, active, "Live input missing for \(family) \(color)")
                }
                XCTAssertEqual(renderedColors.count, ControllerShellColor.allCases.count - 1)
            }
        }
    }

    private func render(
        family: ControllerFamily, color: ControllerShellColor, scheme: ColorScheme, active: Bool
    ) throws -> Data {
        let map = ControllerHardwareMap(
            family: family, shellColor: color,
            pressedControls: active ? [.buttonSouth, .share] : [],
            analogValues: active ? [.leftTrigger: 0.65] : [:],
            modifierControl: nil,
            leftStick: StickSnapshot(x: active ? 0.7 : 0), rightStick: StickSnapshot(),
            actionDescription: { $0.displayName }, onSelect: { _ in }, onHover: { _ in })
        let renderer = ImageRenderer(content: map.frame(width: 500, height: 330).environment(\.colorScheme, scheme))
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 500)
        XCTAssertEqual(image.height, 330)
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }
}
