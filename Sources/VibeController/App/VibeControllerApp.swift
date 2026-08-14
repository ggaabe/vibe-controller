import SwiftUI

@main
struct VibeControllerApp: App {
    @StateObject private var appModel = AppModel()

    private static let displayName = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleDisplayName"
    ) as? String ?? "Vibe Controller"

    var body: some Scene {
        Window(Self.displayName, id: "main") {
            MainWindowView()
                .environmentObject(appModel)
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
