import AppKit

/// Native menu integration deliberately uses tracking-mode polling, not a
/// SwiftUI keyboard shortcut. Option also reveals the item after a menu opens.
@MainActor
final class DemoCaptureAppMenu: NSObject, NSApplicationDelegate {
    private var capture: DemoCaptureCoordinator?
    private var trackingTimer: Timer?
    private weak var trackedMenu: NSMenu?
    private var statusItem: NSStatusItem?
    private var awaitingTermination = false
    private let itemID = NSUserInterfaceItemIdentifier("vibe.demo-capture")
    private let mainMenuProvider: () -> NSMenu?
    private let optionHeld: () -> Bool

    override convenience init() {
        self.init(mainMenuProvider: { NSApp.mainMenu },
                  optionHeld: { NSEvent.modifierFlags.contains(.option) })
    }

    init(mainMenuProvider: @escaping () -> NSMenu?, optionHeld: @escaping () -> Bool) {
        self.mainMenuProvider = mainMenuProvider
        self.optionHeld = optionHeld
        super.init()
    }

    var isTrackingMainMenu: Bool { trackingTimer != nil }

    func connect(_ capture: DemoCaptureCoordinator) {
        guard self.capture == nil else { return }
        self.capture = capture
        capture.onStateChange = { [weak self] in self?.refresh() }
        NotificationCenter.default.addObserver(self, selector: #selector(menuOpened(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuClosed(_:)),
            name: NSMenu.didEndTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        refresh()
    }

    static func shouldShow(optionHeld: Bool, isCapturing: Bool) -> Bool { optionHeld || isCapturing }

    @objc private func refresh() {
        guard let capture, let menu = mainMenuProvider()?.items.first?.submenu else { return }
        let item: NSMenuItem
        if let existing = menu.items.first(where: { $0.identifier == itemID }) { item = existing }
        else {
            item = NSMenuItem(title: "Demo Capture…", action: #selector(showCapture), keyEquivalent: "")
            item.identifier = itemID
            item.target = self
            menu.insertItem(item, at: min(1, menu.numberOfItems))
        }
        item.title = capture.phase.isBusy ? "Demo Capture — \(capture.phase == .recording ? "Recording" : "Working")…" : "Demo Capture…"
        item.isHidden = !Self.shouldShow(optionHeld: optionHeld(), isCapturing: capture.phase.isBusy)
        // Recording remains discoverable even if the capture panel is closed.
        if capture.phase.isBusy, statusItem == nil {
            let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            status.button?.title = "● REC"
            status.button?.toolTip = "Vibe Controller Demo Capture — show recording controls"
            status.button?.target = self
            status.button?.action = #selector(showCapture)
            statusItem = status
        } else if !capture.phase.isBusy, let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        statusItem?.button?.title = capture.phase == .recording ? "● REC" : capture.phase == .preparing ? "● Preparing" : "● Saving"
    }

    @objc private func menuOpened(_ notification: Notification) {
        // AppKit posts tracking notifications for NSApp.mainMenu, not the
        // app-name submenu. Filtering on that submenu leaves the item hidden.
        guard let menu = notification.object as? NSMenu, menu === mainMenuProvider() else { return }
        trackedMenu = menu
        refresh()
        trackingTimer?.invalidate()
        let timer = Timer(timeInterval: 0.06, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .eventTracking)
        trackingTimer = timer
    }

    @objc private func menuClosed(_ notification: Notification) {
        // Match the root which began tracking, even if SwiftUI has replaced
        // NSApp.mainMenu in the meantime. Unrelated popup menus are ignored.
        guard let menu = notification.object as? NSMenu, menu === trackedMenu else { return }
        trackingTimer?.invalidate()
        trackingTimer = nil
        trackedMenu = nil
    }

    @objc private func showCapture() { capture?.show() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let capture, capture.phase.isBusy else { return .terminateNow }
        guard !awaitingTermination else { return .terminateLater }
        awaitingTermination = true
        Task {
            await capture.finishBeforeQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
