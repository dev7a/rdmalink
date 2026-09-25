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
    /// does, and is reached from S7's footer and from the Help menu.
    var showsOtherMac = false
}
