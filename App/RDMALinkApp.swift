import SwiftUI
import RDMALinkCore

/// Keys shared between the window, the menu bar and Settings.
enum AppSettings {
    /// UX_SPEC §S12: adds `en6` and the exact service names to the row detail
    /// lines, and nothing else. Never drawn on the 3D model.
    static let showTechnicalNames = "ShowTechnicalNames"
    /// UX_SPEC §4.8: the legend over the stage, hidden with View › Hide
    /// Legend ⌘K, "and the choice is remembered".
    static let showsLegend = "ShowLegend"
    /// §2.3: where the divider sits, remembered between launches.
    static let stageSplitFraction = "StageSplitFraction"
    /// §S8: which Mac the ghost second Mac is drawn as — an
    /// `OtherMacChoice` — and "the choice is remembered across launches".
    static let otherMac = "OtherMac"
}

@main
struct RDMALinkApp: App {
    /// §2.1: one window, no tabs, no document model. `Window` rather than
    /// `WindowGroup` is what removes File › New Window.
    static let mainWindowID = "rdmalink.main"

    /// §S6, §S10: quitting waits for a burst to land (`BurstGate`).
    @NSApplicationDelegateAdaptor(RDMALinkAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var router = HubRouter()
    @AppStorage(AppSettings.showTechnicalNames) private var showsTechnicalNames = false
    @AppStorage(AppSettings.showsLegend) private var showsLegend = true

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
                // §2.7: the app's View items follow the system's toolbar
                // items — `Check Again` ⌘R first, then a divider, then the
                // stage's items.
                CheckAgainCommand()
                Divider()
                StageViewCommands()
                Divider()
                // §2.7: both switches here are one idiom — an item whose
                // title says what it will do, never a checkmark. Settings
                // keeps its own switch for the same preference.
                Button(showsTechnicalNames ? "Hide Technical Names" : "Show Technical Names") {
                    showsTechnicalNames.toggle()
                }
                .keyboardShortcut("t", modifiers: .command)
                // §2.7 and §4.8: `Hide Legend`, "which then reads `Show
                // Legend`".
                Button(showsLegend ? "Hide Legend" : "Show Legend") { showsLegend.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                ChangeLogCommand()
            }
            CommandGroup(replacing: .help) {
                // §2.7: `RDMALink Help` opens §S13, whose first section is
                // what RDMA over Thunderbolt is, so the menu has no second
                // item for it. §2.2 makes the toolbar's Help button open this
                // item too. It carries ⌘? and a divider sets it apart from
                // the rest, as in every Mac app's Help menu.
                // It waits while one of the window's sheets is up, and only
                // then (§2.6).
                HelpCommand { show(.whatThisAllMeans) }
                Divider()
                // §S8: a screen in the working area, not a sheet, so it is
                // routed like the change log and not like the item above it —
                // and, like it, unavailable while the assistant holds the
                // working area (§2.7).
                OtherMacCommand(router: router) { showOtherMac() }
                // §S12's save, the same one Settings and the change log use —
                // unavailable while a sheet or the assistant is up (§2.7).
                SaveDiagnosticsCommand(router: router)
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

    /// §S8 from the Help menu. The window is brought back first for the same
    /// reason a sheet's is: the screen is drawn in it.
    private func showOtherMac() {
        openWindow(id: Self.mainWindowID)
        router.showOtherMacFromHelp()
    }
}


/// §2.7's View menu, the half of it that drives the stage.
///
/// The stage itself is reached through the focused scene value, so these items
/// act on whichever window is front and do nothing at all when none is. A face
/// this Mac has no ports on is offered and unavailable rather than missing, so
/// the menu is the same shape on every machine. On an unrecognized Mac there
/// is no chassis and so no camera (§6.2 R31: "No selector, legend, callout or
/// view buttons"), and every item here is unavailable the same way.
///
/// The faces are one group of views of which one is showing, as Finder's
/// View › as Icons … as Gallery are: nouns, in the port list's own face names
/// (§2.3 band 3), with a checkmark on the face the stage is turned to (§2.7).
private struct StageViewCommands: View {
    @FocusedValue(\.stageModel) private var stage: StageModel?

    var body: some View {
        face("Back", .back, "1")
        face("Front", .front, "2")
        face("Left Side", .left, "3")
        face("Right Side", .right, "4")
        Divider()
        // Both camera items follow the face items: unavailable, not missing,
        // when there is no chassis to move the camera around (§6.2 R31, §2.7).
        Button("Fit") { stage?.fit() }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(stage?.chassis == nil)
        // §2.3: "Reset View returns the split to 58/42 and the camera to its
        // resting pose." §2.7 gives it ⇧⌘0 and gives ⌘0 to Fit, which is the
        // pairing followed here.
        Button("Reset View") {
            HubSplitDefaults.reset()
            stage?.reset()
        }
        .keyboardShortcut("0", modifiers: [.shift, .command])
        .disabled(stage?.chassis == nil)
    }

    /// A menu `Toggle` draws the checkmark. Choosing the face already
    /// showing leaves it showing — a view is chosen, never switched off.
    private func face(
        _ title: LocalizedStringResource, _ face: PortFace, _ key: KeyEquivalent
    ) -> some View {
        let isRelevant = stage?.relevantFaces.contains(face) == true
        return Toggle(title, isOn: Binding(
            get: { isRelevant && stage?.currentFace == face },
            set: { _ in stage?.turnTo(face) }))
            .keyboardShortcut(key, modifiers: .command)
            .disabled(!isRelevant)
    }
}
