//
//  ApplyRun.swift
//
//  S6 — Setting up (UX_SPEC §S6). The password is asked for by S5's default
//  button; this begins the moment macOS hands back the permission, and then
//  performs every write in a single burst inside the thirty-second credential
//  window, with real progress and never a cancel the app cannot honour.
//
//  **This file performs no writes and opens no session.** It consumes an
//  `AsyncThrowingStream` somebody else produces, which is the seam where
//  `RDMALinkCore.SetUpPorts.perform(session:environment:progress:)` plugs in.
//  Nothing in App/Flows can reach configd or raise the administrator prompt.
//
//  Every checklist string comes from Core's `OperationStep`, which holds the
//  §S6 table verbatim. Nothing in the app re-words a step.
//

import Foundation
import Observation
import RDMALinkCore

/// One checklist row.
struct ApplyStepRow: Sendable, Equatable, Identifiable {
    /// Unique across the whole run: two ports both save an undo note.
    var id: Int
    var step: OperationStep
    var state: StepState

    var text: String { step.text(state) }

    /// §S6: `circle.dotted` while pending, a `ProgressView` while running,
    /// `checkmark.circle.fill` when done. The view draws the spinner.
    var symbol: String? {
        switch state {
        case .pending: "circle.dotted"
        case .running: nil
        case .done: "checkmark.circle.fill"
        // §3.3's Restore symbol: this row is being put back right now.
        case .reversing: "arrow.uturn.backward"
        }
    }
}

/// The rows one port's writes own, in the order they run.
struct ApplyPortGroup: Sendable, Equatable {
    var bsdName: String
    var rows: [Int]
}

/// What the runner reports back. Values only: it crosses actor boundaries.
enum ApplyEvent: Sendable {
    case step(OperationStep, StepState)
    case finished(SetUpPortsResult)
}

/// S6's live state.
///
/// While the OS dialog is up the review screen is still the one showing,
/// dimmed 20 % and saying nothing over it (§S5). From the first write on
/// there are no buttons at all — there is no control the app could honour
/// once macOS has handed back a permission that lasts about thirty seconds.
@MainActor
@Observable
final class ApplyRun {
    enum Phase: Sendable, Equatable {
        /// The OS password dialog is up. Nothing has been written.
        case authorizing
        /// The permission landed and the burst is running: S6 proper.
        case running
        /// Every step landed. S7 follows about 400 ms later.
        case finished
        /// A refusal took over. The footer's buttons stay gone.
        case refused
    }

    /// What produces the events. The app supplies one; there is no default,
    /// because a default would be a write path living in the view layer.
    typealias Runner = @Sendable (SetUpPortsPlan) -> AsyncThrowingStream<ApplyEvent, any Error>

    let plan: SetUpPortsPlan
    private(set) var phase: Phase = .authorizing
    /// The flow listens here: the permission landing is what moves the
    /// working area from S5 to S6, and a refusal before the first write is
    /// S5's to show (§S5 "back here with the selection intact").
    var onPhaseChange: (@MainActor (Phase) -> Void)?
    private(set) var rows: [ApplyStepRow]
    /// Which rows belong to which port, so §S6's ring can close in step with
    /// the checklist on the receptacle the writes are about.
    private(set) var groups: [ApplyPortGroup]
    /// Printed under the last checkmark before the screen advances.
    private(set) var completionLine: String?
    private(set) var refusal: WizardRefusal?
    /// The ports that landed before the run stopped, in physical order.
    ///
    /// A later port's failure rolls back only that port, so a refusal is never
    /// the whole story: §S10's rule that a summary never rounds up applies to
    /// set-up too, and the screen states both.
    private(set) var landed: [String] = []

    private let runner: Runner
    private var task: Task<Void, Never>?

    init(plan: SetUpPortsPlan, runner: @escaping Runner) {
        self.plan = plan
        self.runner = runner
        let built = Self.build(plan)
        self.rows = built.rows
        self.groups = built.groups
    }

    /// How far each port has got, for the stage. `step` counts rows that have
    /// landed, so it is never ahead of what the user can read.
    var ringProgress: [(bsdName: String, step: Int, total: Int)] {
        groups.map { group in
            let done = group.rows.reduce(into: 0) { count, index in
                if rows[index].state == .done { count += 1 }
            }
            return (group.bsdName, done, group.rows.count)
        }
    }

    // MARK: - Copy

    static let runningBody: LocalizedStringResource =
        "A few seconds. Your other network connections stay up the whole time."
    static let statusLine: LocalizedStringResource =
        "You can undo all of this afterwards, from the main window."
    /// §S6's rollback status line, shown while rows are being un-ticked. It is
    /// driven by the operation's own reversing events — the app never animates
    /// a rollback it has not observed (§1.3 rule 10).
    static let rollbackLine: LocalizedStringResource =
        "Something didn't take. Putting the port back exactly as it was…"

    /// True while the burst is undoing what it did.
    var isReversing: Bool { rows.contains { $0.state == .reversing } }

    /// One line per port that landed, in §S7's words for a port that is ready.
    /// **Owed from the spec owner:** a sentence for "these landed, this one
    /// was put back" — §S10 writes one for restore and §S6 writes none.
    var landedLines: [LocalizedStringResource] {
        landed.map { LocalizedStringResource(core: "\($0) is ready") }
    }
    // §S6's rollback status line — "Something didn't take. Putting the port
    // back exactly as it was…" — has nowhere to be drawn: `OperationProgress`
    // reports `(OperationStep, StepState)` and has no rollback channel, so the
    // app cannot see a reversal happening and will not animate one it has not
    // observed (§1.3 rule 10). The rollback is stated by R10's own copy
    // instead. **Owed from Core:** a rollback event on the progress callback.

    /// §S6: "Setting up Back, far left" / "Setting up two ports". The spec
    /// writes the count in words for two and stops there; three or more takes
    /// the digit. **Owed from the spec owner:** the plural past two.
    var runningHeadline: LocalizedStringResource {
        switch plan.ports.count {
        case 1: "Setting up \(plan.ports[0].header)"
        case 2: "Setting up two ports"
        default: "Setting up \(plan.ports.count) ports"
        }
    }

    // MARK: - Driving

    /// S5's default button. The runner's first act is to ask macOS for the
    /// permission; everything after this point is the runner's, and the
    /// footer has nothing left to offer.
    func begin() {
        guard phase == .authorizing, task == nil else { return }
        task = Task { [runner, plan] in
            do {
                for try await event in runner(plan) {
                    await MainActor.run { self.apply(event) }
                }
            } catch let refusal as Refusal {
                await MainActor.run { self.fail(with: WizardRefusal(refusal)) }
            } catch let error as NetworkConfigurationError {
                await MainActor.run { self.fail(with: Self.refusal(for: error)) }
            } catch is CancellationError {
                // The window went away. Nothing to say and nobody to say it to.
            } catch {
                // §6.1 rule 7: the rollback is stated first, and R10's copy is
                // the spec's sentence for "put back, safely".
                await MainActor.run { self.fail(with: WizardRefusals.rolledBack) }
            }
        }
    }

    /// §6.2's refusal for what macOS said: R7 when the dialog was dismissed,
    /// R6 when the account can't, R12 when another writer holds the
    /// configuration — and R10 for a write that failed, because Core has put
    /// the port back by the time the error reaches here.
    private static func refusal(for error: NetworkConfigurationError) -> WizardRefusal {
        switch error {
        case .authorizationCancelled: WizardRefusals.noAuthorization
        case .authorizationDenied: WizardRefusals.notAnAdministrator
        case .busy: WizardRefusals.networkLockHeld(bySystemSettings: false)
        default: WizardRefusals.rolledBack
        }
    }

    private func fail(with refusal: WizardRefusal) {
        self.refusal = refusal
        enter(.refused)
    }

    private func enter(_ next: Phase) {
        guard phase != next else { return }
        phase = next
        onPhaseChange?(next)
    }

    func cancel() { task?.cancel() }

    private func apply(_ event: ApplyEvent) {
        switch event {
        case let .step(step, state):
            // The first step to be reported is the permission having landed:
            // nothing runs before it, and S6 begins here (§S6).
            if phase == .authorizing { enter(.running) }
            update(step, to: state)
        case let .finished(result):
            landed = result.ports.map(\.positionName)
            completionLine = result.completionLine
            // A run that stopped on a port has an answer per port, not one
            // answer: the ports above stand, and the refusal names only the
            // one that was put back.
            if let unfinished = result.unfinished {
                refusal = WizardRefusal(unfinished.refusal)
                enter(.refused)
                return
            }
            enter(.finished)
        }
    }

    /// Rows are matched by step, first one that has not finished — two ports
    /// both save an undo note and both check every bridge.
    private func update(_ step: OperationStep, to state: StepState) {
        let index: Int?
        switch state {
        case .reversing:
            // A row is only ever un-ticked after it was ticked, and a rollback
            // runs backwards, so the last one that landed is the one meant.
            index = rows.lastIndex { $0.step == step && $0.state == .done }
                ?? rows.lastIndex { $0.step == step }
        case .pending:
            index = rows.lastIndex { $0.step == step && $0.state == .reversing }
                ?? rows.lastIndex { $0.step == step }
        case .running, .done:
            index = rows.firstIndex { $0.step == step && $0.state != .done }
                ?? rows.lastIndex { $0.step == step }
        }
        guard let index else { return }
        rows[index].state = state
    }

    /// Every write the plan says will happen, pending, from the first frame of
    /// S6 — so the user sees the whole list and not a list that grows.
    private static func build(
        _ plan: SetUpPortsPlan
    ) -> (rows: [ApplyStepRow], groups: [ApplyPortGroup]) {
        var rows: [ApplyStepRow] = []
        var groups: [ApplyPortGroup] = []
        for port in plan.ports {
            var steps: [OperationStep] = [.saveUndoNote]
            steps.append(contentsOf: port.bridgeNames.map { OperationStep.leaveBridge(named: $0) })
            steps.append(.createService(named: port.serviceName))
            steps.append(.setAddresses)
            steps.append(.checkOutOfEveryBridge)
            let first = rows.count
            for step in steps {
                rows.append(ApplyStepRow(id: rows.count, step: step, state: .pending))
            }
            groups.append(
                ApplyPortGroup(bsdName: port.port.bsdName, rows: Array(first..<rows.count)))
        }
        return (rows, groups)
    }
}
