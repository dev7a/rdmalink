//
//  HubRouter.swift
//
//  Which of the Help menu's surfaces is up. It lives above the window rather
//  than inside it because menus are built in the `App` body, not in the view
//  (UX_SPEC §2.6, §2.7): §S13's sheet, and §S8's screen.
//

import Observation

@MainActor
@Observable
final class HubRouter {
    /// The one sheet the Help menu opens, and the fourth of the four §2.6
    /// lets the app draw; Adopt, Restore and Restore All Ports are the hub's
    /// own (`HubActionsModel.sheet`). The system draws the rest: the
    /// authorization dialog, and the diagnostics save panel and alert.
    enum Sheet: String, Sendable, Identifiable {
        case whatThisAllMeans

        var id: String { rawValue }
    }

    var sheet: Sheet?

    /// §S8 — "This is a screen, not a sheet, because the stage does the
    /// talking." It takes the working area's place the way §S11's change log
    /// does, and is reached from S7's footer and from the Help menu — and
    /// which of the two decides whose link it is about (§S8 "Whose link").
    /// `nil` while the screen is not up.
    var otherMac: OtherMacOrigin?

    var showsOtherMac: Bool { otherMac != nil }

    /// The window's stage, handed over once as `HubActionsModel` is handed
    /// it: the Help menu's §S8 is about the port selected there when the
    /// screen opens. Weak, because the router outlives the window.
    @ObservationIgnored private weak var stage: StageModel?

    func attach(stage: StageModel) { self.stage = stage }

    /// Help › `What to Do on the Other Mac`, and the review hook's route to
    /// it. A screen that is already up stays about the port it is about.
    func showOtherMacFromHelp() {
        guard otherMac == nil else { return }
        otherMac = .help(selected: stage?.selectedID)
    }

    /// Whether the set-up assistant holds the working area, mirrored by the
    /// window. The Help menu's `What to Do on the Other Mac` is unavailable
    /// while it does — never queued to appear when the run ends (§2.7) — and
    /// the menu has to know even when another window, Settings say, is front
    /// and the main window's focused values are out of reach.
    var isAssistantUp = false
}
