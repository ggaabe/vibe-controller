import AppKit
@preconcurrency import ApplicationServices
import Combine
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var accessibilityTrusted: Bool
    @Published private(set) var accessibilityRepairRecommended: Bool

    private static let previouslyTrustedKey = "AccessibilityWasPreviouslyTrusted"

    private let userDefaults: UserDefaults
    private let trustStatus: () -> Bool
    private let promptRequest: () -> Bool
    private var refreshTimer: Timer?

    init(
        userDefaults: UserDefaults = .standard,
        pollingInterval: TimeInterval? = 1,
        trustStatus: @escaping () -> Bool = { AXIsProcessTrusted() },
        promptRequest: @escaping () -> Bool = {
            let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
    ) {
        self.userDefaults = userDefaults
        self.trustStatus = trustStatus
        self.promptRequest = promptRequest

        let trusted = trustStatus()
        self.accessibilityTrusted = trusted
        self.accessibilityRepairRecommended = !trusted && userDefaults.bool(forKey: Self.previouslyTrustedKey)
        if trusted {
            userDefaults.set(true, forKey: Self.previouslyTrustedKey)
        }
        if let pollingInterval {
            startPolling(interval: pollingInterval)
        }
    }

    func refresh() {
        updateTrust(trustStatus())
    }

    func requestAccessibilityPrompt() {
        updateTrust(promptRequest())
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func updateTrust(_ trusted: Bool) {
        accessibilityTrusted = trusted
        if trusted {
            userDefaults.set(true, forKey: Self.previouslyTrustedKey)
            accessibilityRepairRecommended = false
        } else {
            accessibilityRepairRecommended = userDefaults.bool(forKey: Self.previouslyTrustedKey)
        }
    }

    private func startPolling(interval: TimeInterval) {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }
}
