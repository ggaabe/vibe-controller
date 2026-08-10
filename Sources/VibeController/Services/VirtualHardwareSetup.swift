import Foundation

enum VirtualHardwareSetupPhase: String, Sendable {
    case checking
    case needsAccessibility
    case needsSupportInstall
    case missingBundledInstaller
    case driverVersionMismatch
    case needsDriverApproval
    case startingVirtualHardware
    case ready

    var title: String {
        switch self {
        case .checking:
            return "Checking setup"
        case .needsAccessibility:
            return "Grant Accessibility"
        case .needsSupportInstall:
            return "Install virtual input support"
        case .missingBundledInstaller:
            return "Support installer is missing"
        case .driverVersionMismatch:
            return "Virtual input support needs an update"
        case .needsDriverApproval:
            return "Approve the Driver Extension"
        case .startingVirtualHardware:
            return "Starting virtual input"
        case .ready:
            return "Cross-Mac input is ready"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            return "Vibe Controller is checking the permissions and virtual devices required by Universal Control."
        case .needsAccessibility:
            return "Approve the macOS Accessibility request so controller input can move the pointer and send actions."
        case .needsSupportInstall:
            return "Approve the bundled one-time installer. It contains Vibe Controller's bridge and the signed Karabiner virtual mouse and keyboard driver."
        case .missingBundledInstaller:
            return "This app build does not include Virtual Hardware Support. Rebuild it with Scripts/package_app.sh."
        case .driverVersionMismatch:
            return "Run the bundled installer again so the app and Karabiner driver use matching versions."
        case .needsDriverApproval:
            return "Enable the Karabiner Driver Extension in System Settings. macOS requires a physical Touch ID or password approval."
        case .startingVirtualHardware:
            return "The extension is enabled. Vibe Controller is connecting its virtual mouse and keyboard."
        case .ready:
            return "Virtual mouse and keyboard reports will continue through Universal Control after the pointer crosses to another Mac."
        }
    }

    var stepNumber: Int? {
        switch self {
        case .needsAccessibility:
            return 1
        case .needsSupportInstall, .missingBundledInstaller, .driverVersionMismatch:
            return 2
        case .needsDriverApproval, .startingVirtualHardware:
            return 3
        case .checking, .ready:
            return nil
        }
    }
}

struct VirtualHardwareSetupSnapshot: Equatable, Sendable {
    var accessibilityTrusted: Bool
    var helperInstalledSecurely: Bool
    var driverManagerInstalled: Bool
    var bundledInstallerAvailable: Bool
    var driverStatusKnown: Bool
    var driverActivated: Bool
    var driverVersionMismatched: Bool
    var virtualHardwareReady: Bool

    var phase: VirtualHardwareSetupPhase {
        if !accessibilityTrusted {
            return .needsAccessibility
        }
        if virtualHardwareReady {
            return .ready
        }
        if !helperInstalledSecurely || !driverManagerInstalled {
            return bundledInstallerAvailable ? .needsSupportInstall : .missingBundledInstaller
        }
        if !driverStatusKnown {
            return .checking
        }
        if driverVersionMismatched {
            return .driverVersionMismatch
        }
        if !driverActivated {
            return .needsDriverApproval
        }
        return .startingVirtualHardware
    }
}
