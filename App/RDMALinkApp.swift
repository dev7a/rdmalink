import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RDMALinkCore

/// Keys shared between the window, the menu bar and Settings.
enum AppSettings {
    /// UX_SPEC §S12: adds `en6` and the exact service names to the row detail
    /// lines, and nothing else. Never drawn on the 3D model.
    static let showTechnicalNames = "ShowTechnicalNames"
    /// §2.3: where the divider sits, remembered between launches.
    static let stageSplitFraction = "StageSplitFraction"
    /// §S12: stored in ML1 and read by nothing. The release-page check itself
    /// is ML3, and RDMALink makes no network request before then.
    static let checksForUpdates = "ChecksForUpdatesAutomatically"
}

@main
struct RDMALinkApp: App {
    /// §2.1: one window, no tabs, no document model. `Window` rather than
    /// `WindowGroup` is what removes File › New Window.
    static let mainWindowID = "rdmalink.main"

    @Environment(\.openWindow) private var openWindow
    @State private var router = HubRouter()
    @AppStorage(AppSettings.showTechnicalNames) private var showsTechnicalNames = false

    var body: some Scene {
        Window("RDMALink", id: Self.mainWindowID) {
            RootView(router: router)
        }
        .defaultSize(width: 1000, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            // §2.7's Port menu. AppKit places a `CommandMenu` after the
            // built-in menus it knows about, so it lands beside View rather
            // than before it; the items and their shortcuts are the spec's.
            CommandMenu("Port") {
                PortCommands()
            }
            CommandGroup(after: .toolbar) {
                StageViewCommands()
                Divider()
                Toggle("Show Technical Names", isOn: $showsTechnicalNames)
                    .keyboardShortcut("t", modifiers: .command)
                ChangeLogCommand()
            }
            CommandGroup(replacing: .help) {
                // §2.7 lists four items. "RDMALink Help" and "What RDMA over
                // Thunderbolt Is" are meant to have different destinations, and
                // there is no help book yet — so the first item *is* §S13's
                // explainer, deliberately, and the second is not duplicated
                // onto the same sheet. §2.2 makes the toolbar's Help button
                // open the first item, which is therefore the explainer too.
                // **Owed:** a real help destination, and the second item back.
                Button("RDMALink Help") { show(.whatThisAllMeans) }
                Button("What to Do on the Other Mac") { show(.otherMac) }
                Button("Save a Diagnostics File…") { saveDiagnostics() }
            }
        }

        // §2.7: a separate small window with a single General pane and
        // therefore no tab bar, per HIG. ⌘, comes with the scene.
        Settings {
            SettingsWindow()
        }
    }

    /// Menu items reach the sheet through the window, so the window is brought
    /// back first if it was closed.
    private func show(_ sheet: HubRouter.Sheet) {
        openWindow(id: Self.mainWindowID)
        router.sheet = sheet
    }

    /// §2.7's fourth Help item, on the same payload Settings saves (§6.1
    /// rule 8: it is the same text `Copy Details` puts on the pasteboard).
    private func saveDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Diagnostics.suggestedFileName()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            let text = await Task.detached(priority: .userInitiated) { Diagnostics.live() }.value
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}


/// §2.7's View menu, the half of it that drives the stage.
///
/// The stage itself is reached through the focused scene value, so these items
/// act on whichever window is front and do nothing at all when none is. A face
/// this Mac has no ports on is offered and unavailable rather than missing, so
/// the menu is the same shape on every machine.
private struct StageViewCommands: View {
    @FocusedValue(\.stageModel) private var stage: StageModel?

    var body: some View {
        face("Back", .back, "1")
        face("Front", .front, "2")
        face("Left", .left, "3")
        face("Right", .right, "4")
        Divider()
        Button("Fit") { stage?.fit() }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(stage == nil)
        // §2.3: "Reset View returns the split to 58/42 and the camera to its
        // resting pose." §2.7 gives it ⇧⌘0 and gives ⌘0 to Fit, which is the
        // pairing followed here.
        Button("Reset View") {
            HubSplitDefaults.reset()
            stage?.reset()
        }
        .keyboardShortcut("0", modifiers: [.shift, .command])
        .disabled(stage == nil)
    }

    private func face(
        _ title: LocalizedStringResource, _ face: PortFace, _ key: KeyEquivalent
    ) -> some View {
        Button(title) { stage?.turnTo(face) }
            .keyboardShortcut(key, modifiers: .command)
            .disabled(stage?.relevantFaces.contains(face) != true)
    }
}
