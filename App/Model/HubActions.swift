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
    /// The footer's default button and the Port menu's ⌘N. The port is the one
    /// already selected, when there is one.
    case setUpAPort(portID: String?)
    case identifyAPort(portID: String?)
    case adopt(portID: String)
    case restore(portID: String)
    case returnToBridge(portID: String)
    case stopManaging(portID: String)
    case setItUpAgain(portID: String)
    case forgetThisPort(portID: String)
    case showMe(portID: String)
    case restoreAll
    case changeLog
    /// §S11: a note for a port that is not on this Mac any more. Keyed by the
    /// interface name, because that is what a note is filed under and the port
    /// itself is gone.
    case forgetThisNote(port: String)

    var id: String {
        switch self {
        case .setUpAPort(let port): "setUp:\(port ?? "")"
        case .identifyAPort(let port): "identify:\(port ?? "")"
        case .adopt(let port): "adopt:\(port)"
        case .restore(let port): "restore:\(port)"
        case .returnToBridge(let port): "return:\(port)"
        case .stopManaging(let port): "stop:\(port)"
        case .setItUpAgain(let port): "again:\(port)"
        case .forgetThisPort(let port): "forget:\(port)"
        case .showMe(let port): "showMe:\(port)"
        case .restoreAll: "restoreAll"
        case .changeLog: "changeLog"
        case .forgetThisNote(let port): "forgetNote:\(port)"
        }
    }

    /// The button's words, verbatim from §S1, §S10 and §S11.
    ///
    /// `Set Up a Port…` has a second form once a port is ready — the footer
    /// picks between them, because only the footer knows (§S1's primary
    /// action); the Port menu's item is always the first form.
    var title: LocalizedStringResource {
        switch self {
        case .setUpAPort: "Set Up a Port…"
        case .identifyAPort: "Identify a Port…"
        case .adopt: "Adopt…"
        case .restore: "Restore…"
        case .returnToBridge: "Return to Bridge…"
        case .stopManaging: "Stop Managing…"
        case .setItUpAgain: "Set It Up Again"
        case .forgetThisPort: "Forget This Port"
        case .showMe: "Show Me"
        case .restoreAll: "Restore All Ports…"
        case .changeLog: "Change Log"
        case .forgetThisNote: "Forget This Note"
        }
    }
}

/// §2.6's sheets that belong to this slice: Adopt, Restore and Restore All
/// Ports. The other two are the system's authorization dialog and S13.
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
    /// An adopted port: RDMALink forgets its note and changes nothing.
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

/// The hub's hand-off to the set-up flow (S3–S7), which is its own slice. The
/// footer, the Port menu and `Set It Up Again` set this and nothing else.
struct SetUpRequest: Sendable, Equatable {
    /// The port the user already had in hand, when there was one.
    var portID: String?
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
