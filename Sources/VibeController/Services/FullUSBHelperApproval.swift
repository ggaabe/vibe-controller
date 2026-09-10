import Foundation
import ServiceManagement

/// Approval persists independently of the USB session. Merely inspecting this
/// state never registers a service, prompts, or captures a controller.
enum FullUSBHelperStatus: Equatable {
    case unavailable, notRegistered, requiresApproval, enabled

    var buttonTitle: String {
        switch self {
        case .unavailable: "Helper unavailable"
        case .notRegistered: "Set up Full USB"
        case .requiresApproval: "Open Approval Settings"
        case .enabled: "Enable full USB"
        }
    }

    var detail: String {
        switch self {
        case .unavailable: "Use the packaged, signed app to set up its USB helper."
        case .notRegistered: "Approve the signed USB helper once in System Settings. Later sessions reuse that approval; your password is never stored."
        case .requiresApproval: "In System Settings → General → Login Items & Extensions, allow Vibe Controller Dev under App Background Activity (Allow in the Background on older macOS). Return here and enable Full USB."
        case .enabled: "USB helper approved. No password prompt is needed for each session. You can revoke approval below or in System Settings."
        }
    }

    static func resolve(_ status: SMAppService.Status, isPackaged: Bool) -> Self {
        guard isPackaged else { return .unavailable }
        switch status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        // The bundle assets have been checked above. A first launch or moved
        // development bundle may not yet have a service record; allow an
        // explicit registration attempt and surface its actual error.
        case .notFound: return .notRegistered
        @unknown default: return .unavailable
        }
    }
}

/// Keep the original failure visible when successful cleanup follows it.
struct FullUSBSessionOutcome {
    private(set) var failure: String?
    private(set) var cleanup: String?
    mutating func receive(kind: UInt8, message: String) {
        guard !message.isEmpty else { return }
        if kind == 3 {
            if failure == nil { failure = message }
            else if cleanup == nil, failure != message { cleanup = message }
        } else if kind == 4 { cleanup = message }
    }
    var message: String {
        [failure, cleanup].compactMap { $0 }.joined(separator: " ")
    }
    func ending(with fallback: String) -> String { message.isEmpty ? fallback : message }
}
