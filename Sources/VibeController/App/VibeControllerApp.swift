import SwiftUI

@main
struct VibeControllerApp: App {
    @NSApplicationDelegateAdaptor(DemoCaptureAppMenu.self) private var appMenu
    @StateObject private var appModel = AppModel()

    private static let displayName = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleDisplayName"
    ) as? String ?? "Vibe Controller"

    var body: some Scene {
        Window(Self.displayName, id: "main") {
            MainWindowView()
                .environmentObject(appModel)
                .onAppear { appMenu.connect(appModel.demoCapture) }
                .frame(
                    minWidth: MainWindowLayoutMetrics.minimumWidth,
                    minHeight: MainWindowLayoutMetrics.minimumHeight
                )
        }
        .defaultSize(
            width: MainWindowLayoutMetrics.defaultWidth,
            height: MainWindowLayoutMetrics.defaultHeight
        )
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
