import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest

@testable import VibeController

@MainActor
final class ControllerLiveFeedbackTests: XCTestCase {
    func testAnalogTriggersPreservePartialPullsBeforeActionThreshold() {
        let state = feedback(analog: [.leftTrigger: 0.08, .rightTrigger: 0.65])
        XCTAssertEqual(state.amount(for: .leftTrigger), 0.08)
        XCTAssertEqual(state.amount(for: .rightTrigger), 0.65)
        XCTAssertTrue(state.isActive(.leftTrigger))
        XCTAssertFalse(feedback(analog: [.leftTrigger: 0.01]).isActive(.leftTrigger))
    }

    func testDigitalAndStickClickStatesRemainVisible() {
        let state = feedback(
            pressed: [.buttonSouth, .leftTrigger, .rightThumbstickButton],
            left: StickSnapshot(pressed: true))
        for control in [ControllerControlID.buttonSouth, .leftTrigger, .leftThumbstickButton, .rightThumbstickButton] {
            XCTAssertTrue(state.isActive(control))
        }
        XCTAssertFalse(state.isActive(.buttonEast))
        XCTAssertEqual(state.amount(for: .leftTrigger), 1)
    }

    func testMalformedAnalogInputIsBounded() {
        XCTAssertEqual(ControllerLiveFeedback.unit(-1), 0)
        XCTAssertEqual(ControllerLiveFeedback.unit(2), 1)
        XCTAssertEqual(ControllerLiveFeedback.unit(.nan), 0)
        XCTAssertEqual(ControllerLiveFeedback.unit(.infinity), 0)
        let vector = ControllerLiveFeedback.stickVector(StickSnapshot(x: .nan, y: .infinity))
        XCTAssertEqual(vector, .zero)
    }

    func testStickTravelMatchesAllDirectionsAndReturnsToCenter() {
        for x in [-1.0, 0, 1] {
            for y in [-1.0, 0, 1] {
                let vector = ControllerLiveFeedback.stickVector(StickSnapshot(x: x, y: y))
                XCTAssertLessThanOrEqual(hypot(vector.dx, vector.dy), 1.00001)
                XCTAssertEqual(vector.dx.sign, x.sign)
                if y != 0 { XCTAssertEqual(vector.dy.sign, (-y).sign) }
            }
        }
        XCTAssertEqual(ControllerLiveFeedback.stickVector(StickSnapshot()), .zero)
    }

    func testEveryButtonProducesDifferentRenderedFeedbackOnBothControllers() throws {
        for family in [ControllerFamily.xbox, .playStation] {
            let neutral = try png(render(family: family, state: feedback()))
            for region in ControllerArtwork.controls(for: family) {
                let active = try png(render(family: family, state: feedback(pressed: [region.control])))
                XCTAssertNotEqual(active, neutral, "Missing visual press feedback for \(family) \(region.control)")
            }
        }
    }

    func testStickMovementAndTriggerTravelChangeTheActualRenderedMap() throws {
        for family in [ControllerFamily.xbox, .playStation] {
            for labels in [false, true] {
                let neutral = try png(render(family: family, state: feedback(), labels: labels))
                let left = try png(render(family: family, state: feedback(left: StickSnapshot(x: 1)), labels: labels))
                let right = try png(render(family: family, state: feedback(right: StickSnapshot(y: 1)), labels: labels))
                let partial = try png(
                    render(family: family, state: feedback(analog: [.rightTrigger: 0.1]), labels: labels))
                let full = try png(render(family: family, state: feedback(analog: [.rightTrigger: 1]), labels: labels))
                XCTAssertNotEqual(neutral, left)
                XCTAssertNotEqual(neutral, right)
                XCTAssertNotEqual(left, right)
                XCTAssertNotEqual(neutral, partial)
                XCTAssertNotEqual(partial, full)
                XCTAssertEqual(neutral, try png(render(family: family, state: feedback(), labels: labels)))
            }
        }
    }

    func testAnimatedInputSequenceUsesLiveComponents() throws {
        let output = ProcessInfo.processInfo.environment["VIBE_CONTROLLER_FEEDBACK_PREVIEW_DIR"]
        for family in [ControllerFamily.xbox, .playStation] {
            var destination: CGImageDestination?
            if let output {
                let directory = URL(fileURLWithPath: output, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("\(family.rawValue)-live-feedback.gif")
                destination = try XCTUnwrap(
                    CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 36, nil))
                CGImageDestinationSetProperties(
                    destination!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            }
            let count = destination == nil ? 6 : 36
            for frame in 0..<count {
                let phase = Double(frame) / Double(count)
                let angle = phase * .pi * 2
                let buttons: [ControllerControlID] = [
                    .buttonSouth, .buttonEast, .buttonWest, .buttonNorth,
                    .dpadUp, .dpadRight, .dpadDown, .dpadLeft, .leftShoulder, .rightShoulder, .leftThumbstickButton,
                    .rightThumbstickButton,
                ]
                let state = feedback(
                    pressed: [buttons[min(buttons.count - 1, Int(phase * Double(buttons.count)))]],
                    analog: [.leftTrigger: (sin(angle) + 1) / 2, .rightTrigger: (cos(angle) + 1) / 2],
                    left: StickSnapshot(x: cos(angle), y: sin(angle)),
                    right: StickSnapshot(x: -sin(angle), y: -cos(angle)))
                let image = try render(family: family, state: state, labels: true)
                if let destination {
                    CGImageDestinationAddImage(
                        destination, image,
                        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 12]] as CFDictionary)
                }
            }
            if let destination { XCTAssertTrue(CGImageDestinationFinalize(destination)) }
        }
    }

    private func feedback(
        pressed: Set<ControllerControlID> = [], analog: [ControllerControlID: Double] = [:],
        left: StickSnapshot = StickSnapshot(), right: StickSnapshot = StickSnapshot()
    ) -> ControllerLiveFeedback {
        ControllerLiveFeedback(pressedControls: pressed, analogValues: analog, leftStick: left, rightStick: right)
    }

    private func render(family: ControllerFamily, state: ControllerLiveFeedback, labels: Bool = false) throws -> CGImage
    {
        let hardware = ControllerHardwareMap(
            family: family, pressedControls: state.pressedControls,
            analogValues: state.analogValues, modifierControl: nil, leftStick: state.leftStick,
            rightStick: state.rightStick,
            actionDescription: {
                ControllerProfile.gabesDefaults.effectiveMapping(
                    for: $0, modifierControl: nil,
                    applicationBundleIdentifier: nil
                ).summary
            }, onSelect: { _ in }, onHover: { _ in })
        let renderer = ImageRenderer(
            content: Group {
                if labels { ControllerAnnotatedMap(hardware: hardware, hoveredControl: nil) } else { hardware }
            }
            .frame(width: 900, height: 594)
            .background(ProductSurfaceStyle.canvas(for: .dark))
            .environment(\.colorScheme, .dark)
            .tint(Color(red: 0.27, green: 0.53, blue: 0.97)))
        return try XCTUnwrap(renderer.cgImage)
    }

    private func png(_ image: CGImage) throws -> Data {
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }
}
