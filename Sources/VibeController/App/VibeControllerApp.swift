import SwiftUI

@main
struct VibeControllerApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        Window("Vibe Controller", id: "main") {
            MainWindowView()
                .environmentObject(appModel)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
