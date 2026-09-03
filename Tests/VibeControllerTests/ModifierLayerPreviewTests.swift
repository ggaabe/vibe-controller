@testable import VibeController
import XCTest

final class ModifierLayerPreviewTests: XCTestCase {
    func testHeldConfiguredModifierTemporarilyOverridesSelectedLayer() {
        let profile = profileWithModifiers()

        let visibleLayer = ControllerMappingLayer.visibleLayer(
            selectedLayer: .base,
            profile: profile,
            pressedControls: [.leftShoulder]
        )

        XCTAssertEqual(visibleLayer, .modifier(.leftShoulder))
    }

    func testReleasingModifierRestoresManualSelection() {
        let profile = profileWithModifiers()
        let manualSelection = ControllerMappingLayer.modifier(.rightShoulder)

        let visibleWhileHeld = ControllerMappingLayer.visibleLayer(
            selectedLayer: manualSelection,
            profile: profile,
            pressedControls: [.leftShoulder]
        )
        let visibleAfterRelease = ControllerMappingLayer.visibleLayer(
            selectedLayer: manualSelection,
            profile: profile,
            pressedControls: []
        )

        XCTAssertEqual(visibleWhileHeld, .modifier(.leftShoulder))
        XCTAssertEqual(visibleAfterRelease, manualSelection)
    }

    func testUnconfiguredHeldControlDoesNotChangeVisibleLayer() {
        let profile = profileWithModifiers()

        let visibleLayer = ControllerMappingLayer.visibleLayer(
            selectedLayer: .base,
            profile: profile,
            pressedControls: [.buttonWest]
        )

        XCTAssertEqual(visibleLayer, .base)
    }

    func testFirstConfiguredModifierWinsWhenMultipleAreHeld() {
        let profile = profileWithModifiers()

        let visibleLayer = ControllerMappingLayer.visibleLayer(
            selectedLayer: .base,
            profile: profile,
            pressedControls: [.leftShoulder, .rightShoulder]
        )

        XCTAssertEqual(visibleLayer, .modifier(.leftShoulder))
    }

    private func profileWithModifiers() -> ControllerProfile {
        var profile = ControllerProfile.gabesDefaults
        profile.modifierLayers = [
            ControllerModifierLayer(modifierControl: .leftShoulder),
            ControllerModifierLayer(modifierControl: .rightShoulder),
        ]
        return profile
    }
}
