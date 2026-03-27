import AppKit
@preconcurrency import ApplicationServices
import Combine
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var accessibilityTrusted: Bool

    private var refreshTimer: Timer?

    init() {
        self.accessibilityTrusted = AXIsProcessTrusted()
        startPolling()
    }

    func refresh() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    func requestAccessibilityPrompt() {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }
}
