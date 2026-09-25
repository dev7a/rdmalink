//
//  RestorePresentation.swift
//
//  The Restore sheet's buttons and the row §6.2 gives each refusal raised
//  inside it. Pure: Foundation and RDMALinkCore only, so
//  script/test_presentation.sh compiles it against the Core module and
//  asserts every row against the spec's own strings. The copy itself is
//  Core's and is never re-decided here.
//

import Foundation
import RDMALinkCore

/// A button in the Restore sheet. Every title is §S10's or §6.2's.
///
/// `WizardAction` carries the set-up side's buttons; these are the undo
/// side's, and the two sets barely overlap. **Owed:** one table, once the two
/// slices meet.
enum RestoreAction: String, Sendable, Equatable, Identifiable, CaseIterable {
    case restore
    case returnToBridge
    case stopManaging
    case cancel
    case done
    case tryAgain
    case showInFinder
    case openNetworkSettings
    case copyTheseSteps
    case stopManagingThisPort
    /// §6.2 R28's and R30's `Stop Managing…`: the Port menu's title for
    /// forgetting a note, with its ellipsis, where R19 spells the port out.
    case stopManagingEllipsis
    case setItUpAgain
    case removeServiceOnly
    case leaveEverythingAlone
    case copyDetails
    /// §6.2 R12's default: look again, rather than ask for another password.
    case checkAgain

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .restore: "Restore"
        case .returnToBridge: "Return to Bridge"
        case .stopManaging: "Stop Managing"
        case .cancel: "Cancel"
        case .done: "Done"
        case .tryAgain: "Try Again"
        case .showInFinder: "Show in Finder"
        case .openNetworkSettings: "Open Network Settings"
        case .copyTheseSteps: "Copy These Steps"
        case .stopManagingThisPort: "Stop Managing This Port"
        case .stopManagingEllipsis: "Stop Managing…"
        case .setItUpAgain: "Set It Up Again"
        case .removeServiceOnly: "Remove Service Only"
        case .leaveEverythingAlone: "Leave Everything Alone"
        case .copyDetails: "Copy Details"
        case .checkAgain: "Check Again"
        }
    }

    /// The sheet's way out, which Escape presses (§2.6, §8.3: "every cancel
    /// is `.cancelAction`"). `Cancel` is this sheet's `Back` (§6.1 rule 10);
    /// `Leave Everything Alone` is R21's and R28's. Every row has exactly one.
    var isCancel: Bool {
        self == .cancel || self == .leaveEverythingAlone
    }

    /// §2.6: "A sheet's default button is never an action that removes
    /// something the user didn't ask to remove." R21's `Remove Service Only`
    /// deletes a service when the user asked for the port to be put back
    /// whole; R28's `Stop Managing…`, and R19's `Stop Managing This Port`,
    /// forget the note that makes putting it back possible; and R30's
    /// adopted-note form, whose row is `Stop Managing…` · `Cancel`, forgets
    /// the note when the user asked for a Restore — no default there either.
    var removesUnasked: Bool {
        self == .removeServiceOnly || self == .stopManagingEllipsis
            || self == .stopManagingThisPort
    }

    /// The button Return presses in a row: the last, which is where AppKit
    /// puts the default and where every other sheet in this app puts it —
    /// unless the last is the way out, which Escape presses instead, or
    /// removes something unasked, in which case the row has no default at
    /// all (§2.6, §6.2 R21, R28).
    static func defaultAction(in row: [RestoreAction]) -> RestoreAction? {
        guard let last = row.last, !last.isCancel, !last.removesUnasked else { return nil }
        return last
    }
}

/// The symbol, the tint and the button row §6.2 gives each refusal that can be
/// raised inside this sheet. The copy itself is Core's and is never re-decided
/// here.
enum RestoreRefusals {
    static func symbol(for code: RefusalCode) -> String {
        switch code {
        case .volumeMounted: "externaldrive"
        default: "exclamationmark.circle"
        }
    }

    /// `.orange` is the panel's warning tint (§3.1) and R20 is the one state
    /// here that is genuinely half-done.
    static func isAttention(_ code: RefusalCode) -> Bool {
        code == .notBackInBridge
    }

    /// §6.2's own rows, each written in the spec's order **reversed**: the
    /// spec writes the default first, and `RestoreAction.defaultAction(in:)`
    /// makes the last element the default at the trailing edge — except
    /// R21's and R28's, whose last elements are ones §2.6 never lets be a
    /// default. A row too wide for the sheet keeps its last two on the
    /// bottom line (§2.6, `RestoreSheet`).
    ///
    /// Each row keeps a way out, because §6.1 rule 10 leaves `Back` on every
    /// refusal and `Cancel` is this sheet's `Back`. Where the spec writes it
    /// next to the default (R8, R19, R20), it sits beside the default here
    /// too, as a Mac's `Cancel` does. `Copy Details` is §6.1
    /// rule 8's, and rule 8 puts it on **failure** refusals — a write that
    /// went wrong, with a failing step to report. A refusal raised before
    /// anything is written (R19, R21, R28, R30) has none, and §6.2 gives
    /// those rows no `Copy Details`.
    static func actions(for code: RefusalCode) -> [RestoreAction] {
        switch code {
        case .volumeMounted:
            [.cancel, .showInFinder]
        case .undoNoteMissing:
            [.stopManagingThisPort, .copyTheseSteps, .cancel, .openNetworkSettings]
        // R20 comes after writes, and `Cancel` loses nothing: the note is
        // kept and the hub still offers `Restore…`.
        case .notBackInBridge:
            [.copyTheseSteps, .openNetworkSettings, .cancel, .tryAgain]
        // §6.2 R21: `Remove Service Only` · `Leave Everything Alone`, and
        // no default — Return presses nothing, and Escape leaves everything
        // alone (§2.6).
        case .originalBridgeGone:
            [.leaveEverythingAlone, .removeServiceOnly]
        case .noBridgeToReturnTo:
            [.cancel, .openNetworkSettings]
        // §6.2 R28: `Stop Managing…` · `Open Network Settings` · `Leave
        // Everything Alone` (Escape), reversed like every other row, and no
        // default: `Stop Managing…` forgets the note a Restore needs, which
        // the user didn't ask for (§2.6), so Return presses nothing. `Leave
        // Everything Alone` is the way out at the leading edge, as for R21.
        // R28 and R30 both write `Stop Managing…`; only R19 spells the port
        // out. The three do the same thing.
        case .createdServiceEdited:
            [.leaveEverythingAlone, .openNetworkSettings, .stopManagingEllipsis]
        // §6.2 R30's return-record row: `Set It Up Again` · `Stop Managing…`
        // · `Cancel`. R30's adopted form never reaches this sheet — the plan
        // sends an adopted note to Return to Bridge before Core's preview is
        // asked (§7.3) — so the CLI is the only place it is shown.
        case .noteIsAReturnRecord:
            [.cancel, .stopManagingEllipsis, .setItUpAgain]
        // R12 polls quietly and clears itself when the lock does, so its
        // default looks again rather than asking for another password.
        case .networkBusy:
            [.cancel, .checkAgain]
        case .credentialExpired:
            [.copyDetails, .cancel, .tryAgain]
        default:
            [.copyDetails, .cancel]
        }
    }
}
