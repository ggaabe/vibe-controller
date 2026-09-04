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

enum SetupActionID: String, Equatable, Hashable, Sendable {
    case openAccessibilitySettings
    case requestAccessibility
    case openSupportInstaller
    case openDriverSettings
    case refresh
    case retry
}

struct SetupActionPresentation: Equatable, Sendable {
    var id: SetupActionID
    var title: String
    var isProminent: Bool = false
}

enum SetupBannerTone: Equatable, Sendable {
    case neutral
    case attention
    case progress
}

struct SetupBannerPresentation: Equatable, Sendable {
    var title: String
    var detail: String
    var stepLabel: String?
    var symbolName: String
    var tone: SetupBannerTone
    var instructions: [String]
    var actions: [SetupActionPresentation]
}

extension VirtualHardwareSetupPhase {
    func bannerPresentation(accessibilityRepairRecommended: Bool) -> SetupBannerPresentation? {
        switch self {
        case .checking:
            return SetupBannerPresentation(
                title: "Checking cross-Mac setup",
                detail: "Vibe Controller is checking the virtual mouse and keyboard required by Universal Control.",
                stepLabel: nil,
                symbolName: "gearshape.2.fill",
                tone: .progress,
                instructions: [],
                actions: [.init(id: .refresh, title: "Check Again")]
            )

        case .needsAccessibility:
            let detail = accessibilityRepairRecommended
                ? "macOS remembers an older Accessibility approval that no longer matches this copy of Vibe Controller."
                : "Allow Vibe Controller to move the pointer and send clicks and keyboard shortcuts."
            return SetupBannerPresentation(
                title: accessibilityRepairRecommended ? "Refresh Accessibility access" : "Accessibility access required",
                detail: detail,
                stepLabel: "Step 1 of 3",
                symbolName: "accessibility",
                tone: .attention,
                instructions: [
                    "Open Privacy & Security → Accessibility and enable Vibe Controller.",
                    "If it already looks enabled, select that row, click −, reopen Vibe Controller, and enable the newly added row."
                ],
                actions: [
                    .init(id: .openAccessibilitySettings, title: "Open Accessibility Settings", isProminent: true),
                    .init(id: .requestAccessibility, title: "Request Again"),
                    .init(id: .refresh, title: "Check Again")
                ]
            )

        case .needsSupportInstall:
            return SetupBannerPresentation(
                title: "Install Virtual Hardware Support",
                detail: "Approve the bundled one-time installer so Universal Control can treat controller input like a physical mouse and keyboard.",
                stepLabel: "Step 2 of 3",
                symbolName: "shippingbox.fill",
                tone: .attention,
                instructions: ["Complete the Installer window, then return to Vibe Controller."],
                actions: [
                    .init(id: .openSupportInstaller, title: "Open Installer", isProminent: true),
                    .init(id: .refresh, title: "Check Again")
                ]
            )

        case .missingBundledInstaller:
            return SetupBannerPresentation(
                title: "Virtual Hardware Support is missing",
                detail: "This app copy does not contain the support installer. Install a signed release build from GitHub.",
                stepLabel: "Step 2 of 3",
                symbolName: "exclamationmark.triangle.fill",
                tone: .attention,
                instructions: [],
                actions: [.init(id: .retry, title: "Run Setup Again")]
            )

        case .driverVersionMismatch:
            return SetupBannerPresentation(
                title: "Update Virtual Hardware Support",
                detail: "The installed bridge and bundled driver are from different versions. Run the bundled installer again.",
                stepLabel: "Step 2 of 3",
                symbolName: "arrow.triangle.2.circlepath",
                tone: .attention,
                instructions: ["Complete the Installer window, then return to Vibe Controller."],
                actions: [
                    .init(id: .openSupportInstaller, title: "Open Installer", isProminent: true),
                    .init(id: .refresh, title: "Check Again")
                ]
            )

        case .needsDriverApproval:
            return SetupBannerPresentation(
                title: "Enable the virtual input Driver Extension",
                detail: "macOS requires you to approve the Karabiner Driver Extension before Vibe Controller can cross Universal Control edges.",
                stepLabel: "Step 3 of 3",
                symbolName: "switch.2",
                tone: .attention,
                instructions: [
                    "In Login Items & Extensions, open Extensions.",
                    "Find .Karabiner‑VirtualHIDDevice‑Manager Driver Extension and click Show Detail.",
                    "Enable “Provides additional functionality for system drivers,” then approve with Touch ID or your password."
                ],
                actions: [
                    .init(id: .openDriverSettings, title: "Open Driver Settings", isProminent: true),
                    .init(id: .refresh, title: "Check Again")
                ]
            )

        case .startingVirtualHardware:
            return SetupBannerPresentation(
                title: "Starting virtual input",
                detail: "The Driver Extension is enabled. Vibe Controller is connecting its virtual mouse and keyboard.",
                stepLabel: "Step 3 of 3",
                symbolName: "hourglass",
                tone: .progress,
                instructions: [],
                actions: [.init(id: .refresh, title: "Check Again")]
            )

        case .ready:
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
        if driverVersionMismatched {
            return .driverVersionMismatch
        }
        if !driverStatusKnown {
            return .checking
        }
        if !driverActivated {
            return .needsDriverApproval
        }
        return .startingVirtualHardware
    }
}
