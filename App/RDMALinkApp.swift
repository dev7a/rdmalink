import SwiftUI

/// Keys shared between the window and the menu bar.
enum AppSettings {
    /// UX_SPEC §S12: adds `en6` and the exact service names to the row detail
    /// lines, and nothing else. Never drawn on the 3D model.
    static let showTechnicalNames = "ShowTechnicalNames"
}

@main
struct RDMALinkApp: App {
    @AppStorage(AppSettings.showTechnicalNames) private var showsTechnicalNames = false

    var body: some Scene {
        WindowGroup("RDMALink") {
            RootView()
        }
        .defaultSize(width: 1000, height: 660)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .toolbar) {
                Toggle("Show Technical Names", isOn: $showsTechnicalNames)
                    .keyboardShortcut("t", modifiers: .command)
            }
        }
    }
}
