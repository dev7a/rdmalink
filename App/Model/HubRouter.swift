//
//  HubRouter.swift
//
//  Which sheet is up. It lives above the window rather than inside it because
//  the Help menu opens two of them and menus are built in the `App` body, not
//  in the view (UX_SPEC §2.6, §2.7).
//

import Observation

@MainActor
@Observable
final class HubRouter {
    /// The sheets ML1 has. §2.6 allows exactly five in the finished app; the
    /// other three — Adopt, Restore and Restore All Ports — arrive with the
    /// write path in ML2.
    enum Sheet: String, Sendable, Identifiable {
        case whatThisAllMeans
        case otherMac

        var id: String { rawValue }
    }

    var sheet: Sheet?
}
