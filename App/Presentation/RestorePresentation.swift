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
    /// The stop-managing form's committer, `Stop Managing`: forgets the note.
    case confirmStopManaging
    case cancel
    case done
    case tryAgain
    case showInFinder
    case openNetworkSettings
    case copyTheseSteps
    /// R19's, R28's and R30's `Stop Managing…`: the Port menu's command under
    /// its own name, which opens the stop-managing form (§6.2 R19).
    case stopManaging
    case setUpAgain
    case removeServiceOnly
    case copyDetails
    /// §6.2 R12's default: look again, rather than ask for another password.
    case checkAgain

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .restore: "Restore"
        case .returnToBridge: "Return to Bridge"
        case .confirmStopManaging: "Stop Managing"
        case .cancel: "Cancel"
        case .done: "Done"
        case .tryAgain: "Try Again"
        case .showInFinder: "Show in Finder"
        case .openNetworkSettings: "Open Network Settings"
        case .copyTheseSteps: "Copy These Steps"
        case .stopManaging: "Stop Managing…"
        case .setUpAgain: "Set Up Again…"
        case .removeServiceOnly: "Remove Service Only"
        case .copyDetails: "Copy Details"
        case .checkAgain: "Check Again"
        }
    }

    /// The sheet's way out, which Escape presses (§2.6, §8.3: "every cancel
    /// is `.cancelAction`"). `Cancel` is this sheet's `Back` (§6.1 rule 10),
    /// and the one word any sheet gives it (§2.6). Every row has exactly one.
    var isCancel: Bool { self == .cancel }

    /// §2.6: "A sheet's default button is never an action that removes
    /// something the user didn't ask to remove." R21's `Remove Service Only`
    /// deletes a service when the user asked for the port to be put back
    /// whole; R19's and R28's `Stop Managing…` forget the note that makes
    /// putting it back possible; and R30's adopted-note form, whose row is
    /// `Stop Managing…` · `Cancel`, forgets the note when the user asked for
    /// a Restore — no default there either. The stop-managing form's own
    /// `Stop Managing` is asked by the form itself, from Core's answer about
    /// the note (`StopManaging.forgetsTheWayBack`).
    var removesUnasked: Bool {
        self == .removeServiceOnly || self == .stopManaging
    }

    /// §2.6's order for a sheet's button row: the trailing slot is the
    /// default's and `Cancel` sits just before it; a row with no default puts
    /// `Cancel` in the trailing slot. `others` are the rest, leading to
    /// trailing.
    static func row(_ others: [RestoreAction], default primary: RestoreAction?) -> [RestoreAction] {
        others + [.cancel] + (primary.map { [$0] } ?? [])
    }

    /// A form's own row before anything happens — `Restore` · `Cancel`,
    /// `Return to Bridge` · `Cancel`, `Stop Managing` · `Cancel` — with its
    /// committer the default, unless committing forgets the only way back:
    /// then it is `Stop Managing` · `Cancel` with `Cancel` trailing and no
    /// default (§S10, §2.6).
    static func formRow(committer: RestoreAction, isDefault: Bool) -> [RestoreAction] {
        isDefault ? row([], default: committer) : row([committer], default: nil)
    }

    /// The button Return presses in a row: the last, which is where AppKit
    /// puts the default and where every other sheet in this app puts it —
    /// unless the last is the way out, which is how a row with no default is
    /// drawn (`row(_:default:)`), or removes something unasked, which is
    /// never a default (§2.6, §6.2 R21, R28).
    static func defaultAction(in row: [RestoreAction]) -> RestoreAction? {
        guard let last = row.last, !last.isCancel, !last.removesUnasked else { return nil }
        return last
    }
}

/// §S10's question headlines, which name no port (the body does), as the
/// sheet shows one before its plan is read (§S10: "While the sheet reads this
/// Mac, its headline is already there, over a small spinner").
enum RestoreSheetHeadline {
    /// The question the plan will ask. It depends on the form alone — and,
    /// for `Restore…`, on whether the note has anything to put back: an
    /// adopted note goes to Return to Bridge's form (§7.3), as the plan does.
    static func whileReading(_ subject: RestoreSubject, note: PortBaseline?) -> String {
        switch subject {
        case .restore:
            if let note, !note.isReturned, RestorePort.describesNothingToUndo(note) {
                return ReturnToBridge.headline()
            }
            return RestorePort.headline
        case .returnToBridge: return ReturnToBridge.headline()
        case .stopManaging: return StopManaging.headline
        case .all: return RestoreAll.headline
        }
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

    /// The paragraph the card prints: Core's, except R28's over the picker.
    /// There the row has no `Stop Managing…` — a sheet over the assistant
    /// opens no second sheet (§2.6) — so the body must not point at it, and
    /// Core's own form without it is used (§6.2 R28). A plan's refusal and a
    /// burst's both come through here.
    static func message(
        for refusal: Refusal, port: ObservedPort?, overTheAssistant: Bool
    ) -> String {
        guard overTheAssistant, refusal.code == .createdServiceEdited, let port else {
            return refusal.body
        }
        return Refusals.createdServiceEdited(
            port: port, differences: [], offersStopManaging: false).body
    }

    /// `.orange` is the panel's warning tint (§3.1) and R20 is the one state
    /// here that is genuinely half-done.
    static func isAttention(_ code: RefusalCode) -> Bool {
        code == .notBackInBridge
    }

    /// §6.2's own rows, laid out by §2.6's one rule (`RestoreAction.row`):
    /// the default in the trailing slot with `Cancel` just before it, or
    /// `Cancel` trailing where a row has no default — R21's and R28's, whose
    /// one action removes something the user didn't ask to remove. The spec
    /// lists each row default first; where each button sits is the rule's. A
    /// row too wide for the sheet keeps its last two on the bottom line (§2.6,
    /// `RestoreSheet`).
    ///
    /// Each row keeps `Cancel`, because §6.1 rule 10 leaves a way out on
    /// every refusal and `Cancel` is this sheet's. `Copy Details` is §6.1
    /// rule 8's, and rule 8 puts it on **failure** refusals — a write that
    /// went wrong, with a failing step to report. A refusal raised before
    /// anything is written (R19, R21, R28, R30) has none, and §6.2 gives
    /// those rows no `Copy Details`.
    ///
    /// Two things about where the sheet stands take buttons out of a row,
    /// and never put one in:
    /// - `offersSetUpAgain` — R30's `Set Up Again…` is the port row's own
    ///   set-up action, on the footer's terms (§S1,
    ///   `HubActionsModel.setUpAction(forRowOf:)`); without it the row is
    ///   `Stop Managing…` · `Cancel`, with no default, like R30's adopted form.
    /// - `overTheAssistant` — the sheet was opened over the picker, by the one
    ///   route the picker names (§2.6). It opens no second sheet and no second
    ///   run from there, so `Stop Managing…`, which replaces this sheet with
    ///   another, and `Set Up Again…` are left out; what remains is the
    ///   refusal's own advice. R28 then has something to press that removes
    ///   nothing, and `Open Network Settings` is its default.
    static func actions(
        for code: RefusalCode, offersSetUpAgain: Bool = true, overTheAssistant: Bool = false
    ) -> [RestoreAction] {
        let stopManaging: [RestoreAction] = overTheAssistant ? [] : [.stopManaging]
        switch code {
        case .volumeMounted:
            return RestoreAction.row([], default: .showInFinder)
        // §6.2 R19: `Open Network Settings` (default) · `Cancel` · `Copy These
        // Steps` · `Stop Managing…` — the same command R28 and R30 offer,
        // under the same name.
        case .undoNoteMissing:
            return RestoreAction.row(stopManaging + [.copyTheseSteps], default: .openNetworkSettings)
        // R20 comes after writes, and `Cancel` loses nothing: the note is
        // kept and the hub still offers `Restore…`.
        case .notBackInBridge:
            return RestoreAction.row([.copyTheseSteps, .openNetworkSettings], default: .tryAgain)
        // §6.2 R21: `Remove Service Only` · `Cancel`, and no default —
        // Return presses nothing, and Escape leaves everything alone (§2.6).
        case .originalBridgeGone:
            return RestoreAction.row([.removeServiceOnly], default: nil)
        case .noBridgeToReturnTo:
            return RestoreAction.row([], default: .openNetworkSettings)
        // §6.2 R28: `Stop Managing…` · `Open Network Settings` · `Cancel`,
        // and no default: `Stop Managing…` forgets the note a Restore needs,
        // which the user didn't ask for (§2.6), so Return presses nothing.
        // Over the picker there is no `Stop Managing…`, and `Open Network
        // Settings`, which removes nothing, is the default.
        case .createdServiceEdited:
            return overTheAssistant
                ? RestoreAction.row([], default: .openNetworkSettings)
                : RestoreAction.row([.stopManaging, .openNetworkSettings], default: nil)
        // §6.2 R30's return-record row: `Set Up Again…` (default) · `Stop
        // Managing…` · `Cancel`. R30's adopted form never reaches this sheet —
        // the plan sends an adopted note to Return to Bridge before Core's
        // preview is asked (§7.3) — so the CLI is the only place it is shown.
        case .noteIsAReturnRecord:
            return RestoreAction.row(
                stopManaging,
                default: offersSetUpAgain && !overTheAssistant ? .setUpAgain : nil)
        // §6.2 R12: macOS doesn't say when the other writer lets go, so
        // `Check Again` puts back the sheet's plan and the button asks again
        // — its default looks again rather than asking for another password.
        case .networkBusy:
            return RestoreAction.row([], default: .checkAgain)
        case .credentialExpired:
            return RestoreAction.row([.copyDetails], default: .tryAgain)
        default:
            return RestoreAction.row([.copyDetails], default: nil)
        }
    }
}
