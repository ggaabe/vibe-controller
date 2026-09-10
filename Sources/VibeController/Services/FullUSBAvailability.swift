import Foundation

/// Exclusive USB capture is a development experiment, not a prerequisite for
/// native Universal Control. Public builds must not prompt for or start it.
enum FullUSBAvailability {
    static let developmentBundleIdentifier = "com.vibe-controller.app.dev"

    static var isAvailable: Bool {
        isAvailable(bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    static func isAvailable(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == developmentBundleIdentifier
    }

    static let unavailableMessage = "Full USB is limited to Vibe Controller Dev while input and vibration reliability are being tested. Native Universal Control does not require it."
}
