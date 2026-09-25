//
//  HubActions.swift
//
//  What the hub can be asked to do, and the one object that routes it
//  (UX_SPEC §S1, §S9, §S10, §S11). A row, the footer, the Port menu and the
//  change log all raise the same actions; this decides which sheet each one
//  opens, which camera move it is, or which note it clears.
//
//  Nothing here writes network configuration. The two things it does write are
//  RDMALink's own notes and its own log, which need no password and change
//  nothing on the system (§7.1, §7.3).
//

import Foundation
import Observation
import RDMALinkCore

/// One thing the hub offers. Every title is the spec's own.
enum HubAction: Sendable, Equatable, Identifiable {
    /// With no port, the footer's default button and the Port menu's ⌘N,
    /// which open the picker — with the port selected on the hub chosen when
    /// set-up can take it; with one, a row's `Set Up…` or a double-click,
    /// which name their port and open Review for it (§S1, §S4).
    case setUpPort(portID: String?)
    case identifyPort(portID: String?)
    case adopt(portID: String)
    case restore(portID: String)
    case returnToBridge(portID: String)
    /// §S1: forgets the note of a port still on this Mac — adopted,
    /// returned, or drifted — through S10's stop-managing form.
    case stopManaging(portID: String)
    /// A drifted or returned row's `Set Up Again…`: the same run as `Set
    /// Up…`, for a port that has been set up before (§S1).
    case setUpAgain(portID: String)
    case showMe(portID: String)
    case restoreAll
    case changeLog
    /// §S11: a note for a port that is not on this Mac any more. Keyed by the
    /// interface name, because that is what a note is filed under and the port
    /// itself is gone.
    case forgetThisNote(port: String)

    var id: String {
        switch self {
        case .setUpPort(let port): "setUp:\(port ?? "")"
        case .identifyPort(let port): "identify:\(port ?? "")"
        case .adopt(let port): "adopt:\(port)"
        case .restore(let port): "restore:\(port)"
        case .returnToBridge(let port): "return:\(port)"
        case .stopManaging(let port): "stop:\(port)"
        case .setUpAgain(let port): "again:\(port)"
        case .showMe(let port): "showMe:\(port)"
        case .restoreAll: "restoreAll"
        case .changeLog: "changeLog"
        case .forgetThisNote(let port): "forgetNote:\(port)"
        }
    }

    /// The button's words, verbatim from §S1, §S10 and §S11. Every one that
    /// opens somewhere the user still decides — a sheet, the set-up
    /// assistant, Identify's watch — ends in an ellipsis, and the rest act on
    /// the click (§1.3 rule 11). The footer draws this title too, so it and
    /// the Port menu's ⌘N can never name one command two ways (§S1).
    var title: LocalizedStringResource {
        switch self {
        case .setUpPort: "Set Up Port…"
        case .identifyPort: "Identify Port…"
        case .adopt: "Adopt…"
        case .restore: "Restore…"
        case .returnToBridge: "Return to Bridge…"
        case .stopManaging: "Stop Managing…"
        case .setUpAgain: "Set Up Again…"
        case .showMe: "Show Me"
        case .restoreAll: "Restore All Ports…"
        case .changeLog: "Change Log"
        case .forgetThisNote: "Forget This Note"
        }
    }

    /// The words on a port row's trailing button (§S1 "Copy — buttons"). The
    /// row already names the port, so `Set Up Port…` is `Set Up…` there; the
    /// footer and the Port menu keep `title`. Every other action reads the
    /// same on a row as anywhere else.
    var rowTitle: LocalizedStringResource {
        switch self {
        case .setUpPort: "Set Up…"
        default: title
        }
    }

    /// A way into the set-up assistant (S4–S7): the footer's and the Port
    /// menu's `Set Up Port…`, a row's `Set Up…`, and `Set Up Again…`.
    /// §S1 offers every one of them on the footer's terms
    /// (`HubFooterModel.offers(_:)`), `HubActionsModel.perform` refuses every
    /// one the footer would not allow, and §S4 gives none of them to a row on
    /// the picker, where the run is already under way.
    var opensSetUp: Bool {
        switch self {
        case .setUpPort, .setUpAgain: true
        default: false
        }
    }
}

/// §2.6's sheets that belong to this slice: Adopt, Restore and Restore All
/// Ports, three of the four the app draws. S13 is the fourth, and the system
/// draws the authorization dialog and the diagnostics save panel and alert.
enum HubSheet: Sendable, Equatable, Identifiable {
    case adopt(portID: String)
    case restore(RestoreSubject)

    var id: String {
        switch self {
        case .adopt(let port): "adopt:\(port)"
        case .restore(let subject): "restore:\(subject.id)"
        }
    }
}

/// Which of §S10's forms the Restore sheet is in.
enum RestoreSubject: Sendable, Equatable, Identifiable {
    /// A port RDMALink set up, put back the way its note remembers it.
    case restore(portID: String)
    /// §7.5: any port that is out of the bridge, whoever took it out.
    case returnToBridge(portID: String)
    /// An adopted, returned or drifted port: RDMALink forgets its note and
    /// changes nothing.
    case stopManaging(portID: String)
    /// Every note there is, one password, one at a time.
    case all

    var id: String {
        switch self {
        case .restore(let port): "restore:\(port)"
        case .returnToBridge(let port): "return:\(port)"
        case .stopManaging(let port): "stop:\(port)"
        case .all: "all"
        }
    }

    var portID: String? {
        switch self {
        case .restore(let port), .returnToBridge(let port), .stopManaging(let port): port
        case .all: nil
        }
    }
}

/// The hub's hand-off to the set-up flow (S4–S7), which is its own slice. The
/// footer, the Port menu, a row's `Set Up…` and `Set Up Again…` set this
/// and nothing else.
///
/// The run's shape is fixed here, when it starts, and never changes (§2.3
/// band 1, §S4 "When this screen appears").
enum SetUpRequest: Sendable, Equatable {
    /// The footer's `Set Up Port…` and ⌘N, which name no port: the picker,
    /// step 1 of 3. `suggested` is the port selected on the hub, which the
    /// picker opens with chosen when set-up can take it.
    case choose(suggested: String?)
    /// A control that names its port — a row's `Set Up…` or `Set Up
    /// Again…`, the drift row, the change log, R30, a double-click: Review,
    /// step 1 of 2, with no picker in the run.
    case port(String)
}

/// What of the set-up assistant is up, as the menus and the hub's own door
/// see it (§2.6, §2.7: nothing re-enters a run).
enum AssistantPresence: Sendable, Equatable {
    /// S4 with Identify down: the one screen a sheet may open over, and only
    /// for the route the picker names; `Identify Port…` starts its S4b.
    /// `routed` is the dimmed row whose click printed R27's line — the row
    /// the Port menu's `Restore…` and `Adopt…` mean here (§2.7).
    case picker(routed: String?)
    /// S4b, S5, S6 or S7: the Port menu offers nothing.
    case underWay
}

/// How an operation ended.
enum OperationOutcome: Sendable, Equatable {
    /// Some confirmations are a headline and a body (§S10's "Everything is
    /// back"); others are one sentence (§S9's and §S10's stop-managing
    /// confirmations), and inventing a headline for those is not on.
    case succeeded(headline: LocalizedStringResource?, body: LocalizedStringResource)
    /// One of §6.2's refusals, raised by Core as a value carrying its own copy.
    case refused(Refusal)
    /// Anything else the operation threw. §6.2 has no numbered refusal for
    /// "it failed for some other reason", so the sheet prints §6.1's shared
    /// line — **Nothing has been changed.** — and offers `Copy Details`.
    case failed(details: String)
}

/// One run of one operation: the live checklist S6 draws and §S10 reuses, how
/// far it has got, and how it ended.
///
/// The rows are ``RDMALinkCore/OperationStep``, so the words the user reads
/// while a write happens are the same values the operation reports — there is
/// no second list in the app that could disagree with the first.
struct OperationRun: Sendable, Equatable {
    var steps: [OperationStep]
    /// One state per step, in the same order.
    var states: [StepState]
    var outcome: OperationOutcome?

    init(steps: [OperationStep]) {
        self.steps = steps
        self.states = Array(repeating: .pending, count: steps.count)
    }

    var isRunning: Bool { outcome == nil }

    /// §S10: the checklist has started and the burst is writing — the first
    /// step has been reported, which only happens once macOS has handed back
    /// the permission. While only the password dialog is up every row is
    /// still pending, nothing has been written, and closing or quitting
    /// cancels as it always did.
    var isWriting: Bool { isRunning && states.contains { $0 != .pending } }

    /// Restore All runs the same step once per port — three ports means three
    /// `checkBackInBridge` rows, all equal values — so a report lands on the
    /// first row of its kind that has not finished yet, which for a sequential
    /// burst is the one it is about.
    mutating func mark(_ step: OperationStep, _ state: StepState) {
        guard let index = steps.indices.first(
            where: { steps[$0] == step && states[$0] != .done }
        ) else { return }
        states[index] = state
    }

    /// Everything that was running has landed.
    mutating func finishAllSteps() {
        states = Array(repeating: .done, count: steps.count)
    }
}
