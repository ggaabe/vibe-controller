import AppKit
import XCTest
@testable import VibeController

@MainActor
final class DemoCaptureAppMenuTests: XCTestCase {
    private func makeMainMenu() -> NSMenu {
        let root = NSMenu(title: "Main Menu")
        let appItem = NSMenuItem(title: "Vibe Controller", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Vibe Controller")
        appMenu.addItem(withTitle: "About Vibe Controller", action: nil, keyEquivalent: "")
        appMenu.addItem(.separator())
        appItem.submenu = appMenu
        root.addItem(appItem)
        return root
    }

    private func captureItem(in root: NSMenu) throws -> NSMenuItem {
        try XCTUnwrap(root.items.first?.submenu?.items.first {
            $0.identifier?.rawValue == "vibe.demo-capture"
        })
    }

    private func post(_ name: Notification.Name, menu: NSMenu) {
        NotificationCenter.default.post(name: name, object: menu)
    }

    private func trackUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(0.5)
        while !condition(), Date() < deadline {
            RunLoop.main.run(mode: .eventTracking, before: deadline)
        }
        return condition()
    }

    func testOptionBeforeOpeningRootMenuRevealsCapture() throws {
        let root = makeMainMenu()
        var option = false
        let controller = DemoCaptureAppMenu(mainMenuProvider: { root }, optionHeld: { option })
        let capture = DemoCaptureCoordinator()
        controller.connect(capture)
        let item = try captureItem(in: root)
        XCTAssertTrue(item.isHidden)

        option = true
        post(NSMenu.didBeginTrackingNotification, menu: root)
        defer { post(NSMenu.didEndTrackingNotification, menu: root) }
        XCTAssertFalse(item.isHidden, "AppKit posts tracking notifications for the root menu, not the app submenu.")
        XCTAssertTrue(controller.isTrackingMainMenu)
        XCTAssertNotNil(item.target)
        XCTAssertNotNil(item.action)
        XCTAssertEqual(root.items.first?.submenu?.items.filter { $0.identifier == item.identifier }.count, 1)
    }

    func testOptionChangesWhileMenuIsAlreadyOpenAndTimerStopsAtClose() throws {
        let root = makeMainMenu()
        var option = false
        let controller = DemoCaptureAppMenu(mainMenuProvider: { root }, optionHeld: { option })
        controller.connect(DemoCaptureCoordinator())
        let item = try captureItem(in: root)
        post(NSMenu.didBeginTrackingNotification, menu: root)
        defer { post(NSMenu.didEndTrackingNotification, menu: root) }
        XCTAssertTrue(item.isHidden)

        option = true
        XCTAssertTrue(trackUntil { !item.isHidden }, "Holding Option must reveal the item without reopening the menu.")
        option = false
        XCTAssertTrue(trackUntil { item.isHidden }, "Releasing Option must hide the idle capture command again.")
        post(NSMenu.didEndTrackingNotification, menu: root)
        XCTAssertFalse(controller.isTrackingMainMenu)
    }

    func testSwiftUIMenuReplacementIsRepairedOnNextOpenWithoutDuplicates() throws {
        var root = makeMainMenu()
        let controller = DemoCaptureAppMenu(mainMenuProvider: { root }, optionHeld: { true })
        controller.connect(DemoCaptureCoordinator())
        root = makeMainMenu()
        post(NSMenu.didBeginTrackingNotification, menu: root)
        defer { post(NSMenu.didEndTrackingNotification, menu: root) }
        let item = try captureItem(in: root)
        XCTAssertFalse(item.isHidden)
        post(NSMenu.didBeginTrackingNotification, menu: root)
        XCTAssertEqual(root.items.first?.submenu?.items.filter { $0.identifier == item.identifier }.count, 1)
    }

    func testPopupMenusDoNotStartOrStopMainMenuTracking() throws {
        let root = makeMainMenu()
        let popup = NSMenu(title: "Profiles")
        let controller = DemoCaptureAppMenu(mainMenuProvider: { root }, optionHeld: { false })
        controller.connect(DemoCaptureCoordinator())
        post(NSMenu.didBeginTrackingNotification, menu: popup)
        XCTAssertFalse(controller.isTrackingMainMenu)
        post(NSMenu.didBeginTrackingNotification, menu: root)
        defer { post(NSMenu.didEndTrackingNotification, menu: root) }
        XCTAssertTrue(controller.isTrackingMainMenu)
        post(NSMenu.didEndTrackingNotification, menu: popup)
        XCTAssertTrue(controller.isTrackingMainMenu)
        post(NSMenu.didEndTrackingNotification, menu: root)
        XCTAssertFalse(controller.isTrackingMainMenu)
    }

    func testOriginalRootEndsTrackingEvenWhenMainMenuIsReplaced() {
        var root = makeMainMenu()
        let controller = DemoCaptureAppMenu(mainMenuProvider: { root }, optionHeld: { false })
        controller.connect(DemoCaptureCoordinator())
        let openedRoot = root
        post(NSMenu.didBeginTrackingNotification, menu: openedRoot)
        root = makeMainMenu()
        post(NSMenu.didEndTrackingNotification, menu: openedRoot)
        XCTAssertFalse(controller.isTrackingMainMenu)
    }
}
