//
//  RestoreSheet.swift
//
//  S10 — put a port back, in every form the spec gives it: a port RDMALink set
//  up, a port somebody else set up (§7.5's Return to Bridge), an adopted port
//  RDMALink should simply stop looking after, and every noted port at once.
//
//  After the button the sheet's content is replaced by the same live checklist
//  as S6, driven by the operation's own `OperationStep`s — the words the user
//  watches are the ones the writes report, not a second list that could
//  disagree.
//
//  §6.1 rule 1's one exception lives here: a refusal raised inside this sheet
//  stays in this sheet. R4, R19, R20, R21, R29 and R30 all land here, each with
//  the button row §6.2 gives its number, and none of them with a way around it.
//

import AppKit
import SwiftUI
import RDMALinkCore

struct RestoreSheet: View {
    let subject: RestoreSubject
    let hub: HubActionsModel
    /// `Copy Details` carries the same payload as a diagnostics file (§6.1
    /// rule 8), and the window's model is where that payload comes from.
    let model: InventoryModel
    @Environment(\.dismiss) private var dismiss
    /// The plan the button was pressed under.
    ///
    /// Everything else here is derived from the live world, which is right up
    /// until the writes land: a successful Restore All deletes every note, a
    /// successful Restore deletes this port's, and the plan they were built
    /// from evaporates underneath the answer it produced — taking the success
    /// message and its `Done` button with it. Once a run exists the sheet keeps
    /// the plan it acted on until it is dismissed.
    @State private var running: RestorePlan?

    private var plan: RestorePlan? {
        running ?? RestorePlanning.plan(subject: subject, hub: hub)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let plan {
                content(plan)
            } else if hub.worldFailure != nil {
                unreadableWorld
            } else {
                // Reading this Mac takes a moment and the spec gives the sheet
                // no sentence for it, so it says nothing rather than something
                // of its own.
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(24)
        .frame(width: 500, alignment: .leading)
        .animation(.smooth(duration: 0.18), value: hub.run)
        .onDisappear { hub.sheetDismissed() }
    }

    /// A refusal standing in the way replaces the whole plan: it names the
    /// situation itself, and the primary is removed rather than disabled
    /// (§6.1 rules 3 and 6).
    @ViewBuilder
    private func content(_ plan: RestorePlan) -> some View {
        if let run = hub.run {
            // While the writes happen the sheet keeps the headline the user
            // pressed the button under. Once it has an answer, that answer is
            // the headline — a question that has been answered is not one.
            if run.isRunning {
                Text(plan.headline)
                    .font(.title2.weight(.semibold))
            }
            runContent(run, plan: plan)
        } else if let refusal = plan.refusal {
            refusalContent(refusal, plan: plan)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(plan.headline)
                    .font(.title2.weight(.semibold))
                if let body = plan.body {
                    Text(body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            planContent(plan)
        }
    }

    // MARK: - Before the button

    @ViewBuilder
    private func planContent(_ plan: RestorePlan) -> some View {
        if !plan.rows.isEmpty {
            GroupedSection {
                ForEach(Array(plan.rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { RowDivider() }
                    Text(row)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                }
            }
        }
        if !plan.notes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(plan.notes.enumerated()), id: \.offset) { _, note in
                    Text(note)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        buttonRow([.cancel, plan.primary], plan: plan, refusal: nil)
    }

    // MARK: - After the button

    @ViewBuilder
    private func runContent(_ run: OperationRun, plan: RestorePlan) -> some View {
        switch run.outcome {
        case .none:
            // Stop Managing is one note and no writes, so it has no checklist
            // to draw — §S10 gives it none either.
            if run.steps.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                RestoreChecklist(run: run)
            }
        case .succeeded(let headline, let body):
            VStack(alignment: .leading, spacing: 8) {
                if let headline {
                    Text(headline).font(.title2.weight(.semibold))
                }
                Text(body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttonRow([.done], plan: plan, refusal: nil)
        case .refused(let refusal):
            refusalContent(refusal, plan: plan)
        case .failed(let details):
            VStack(alignment: .leading, spacing: 8) {
                // §6.1's shared strings. There is no numbered refusal for "it
                // failed for another reason", and inventing a headline for one
                // is not on: the sheet keeps its own, states plainly that
                // nothing was changed, and hands over the details.
                Text("Nothing has been changed.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: details)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            buttonRow([.copyDetails, .cancel], plan: plan, refusal: nil)
        }
    }

    @ViewBuilder
    private func refusalContent(_ refusal: Refusal, plan: RestorePlan) -> some View {
        RefusalCard(
            symbol: RestoreRefusals.symbol(for: refusal.code),
            tint: RestoreRefusals.isAttention(refusal.code) ? .attention : .secondary,
            headline: LocalizedStringResource(core: refusal.headline),
            message: LocalizedStringResource(core: refusal.body),
            extraMessage: refusal.detail.map { LocalizedStringResource(core: $0) }
        ) {
            buttons(RestoreRefusals.actions(for: refusal.code), plan: plan, refusal: refusal)
        }
        // §8.2: "Refusals are announced assertively, once, because they stop
        // the flow."
        .task(id: refusal.code) {
            AccessibilityNotification.Announcement(
                String(localized: LocalizedStringResource(core: refusal.headline))).post()
        }
    }

    private var unreadableWorld: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing has been changed.")
                .font(.body)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                CopyDetailsButton { model.diagnosticsText(failingStep: "reading this Mac") }
                Button(RestoreAction.cancel.title) { dismiss() }
            }
        }
    }

    // MARK: - Buttons

    private func buttonRow(
        _ actions: [RestoreAction], plan: RestorePlan, refusal: Refusal?
    ) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            buttons(actions, plan: plan, refusal: refusal)
        }
    }

    /// The last action is the default, which is where AppKit puts it and where
    /// every other sheet in this app puts it.
    @ViewBuilder
    private func buttons(
        _ actions: [RestoreAction], plan: RestorePlan, refusal: Refusal?
    ) -> some View {
        ForEach(actions) { action in
            button(action, isDefault: action == actions.last, plan: plan, refusal: refusal)
        }
    }

    @ViewBuilder
    private func button(
        _ action: RestoreAction, isDefault: Bool, plan: RestorePlan, refusal: Refusal?
    ) -> some View {
        switch action {
        case .copyDetails:
            CopyDetailsButton {
                model.diagnosticsText(failingStep: refusal?.code.rawValue ?? "putting a port back")
            }
        case .copyTheseSteps:
            CopyButton(title: action.title) { refusal?.detail ?? refusal?.body ?? "" }
        default:
            if isDefault {
                Button(action.title) { perform(action, plan: plan) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(action.title) { perform(action, plan: plan) }
            }
        }
    }

    private func perform(_ action: RestoreAction, plan: RestorePlan) {
        switch action {
        case .cancel, .done, .leaveEverythingAlone:
            dismiss()
        case .restore, .returnToBridge, .stopManaging, .tryAgain:
            running = plan
            run(plan)
        case .checkAgain:
            running = nil
            hub.recheck()
        case .showInFinder:
            if let volume = plan.volumes.first { WizardFinder.showVolume(named: volume.name) }
        case .openNetworkSettings:
            WizardSettingsPane.open(WizardSettingsPane.network)
        case .stopManagingThisPort, .stopManagingEllipsis:
            if let port = plan.port { hub.perform(.stopManaging(portID: port.id)) }
        // §6.2 R30's default: the note stays, and the port goes back through
        // the set-up assistant. That is a different window, so this sheet
        // closes behind it rather than being replaced the way `Stop Managing
        // This Port` is.
        case .setItUpAgain:
            if let port = plan.port { hub.perform(.setItUpAgain(portID: port.id)) }
            dismiss()
        case .removeMyServiceOnly:
            running = plan
            runServiceOnly(plan)
        case .copyDetails, .copyTheseSteps:
            break
        }
    }

    // MARK: - Running it

    /// Every call below is an RDMALinkCore operation type, performed in one
    /// burst inside the credential window `OperationHost` opens (§2.6: the
    /// macOS authorization dialog is the one sheet this app does not draw).
    /// The checklist advances from the operation's own progress reports.
    private func run(_ plan: RestorePlan) {
        let environment = hub.environment
        switch plan.kind {
        case .restore:
            guard let port = plan.port else { return }
            let operationPort = OperationPort(port.port)
            let fallbackBridge = plan.bridgeName
            hub.start(steps: plan.steps, portID: port.id) { progress in
                let result = try await OperationHost.burst { session in
                    try RestorePort(port: operationPort).perform(
                        session: session, environment: environment, progress: progress)
                }
                let bridgeName = result.rejoinedBridges.first ?? fallbackBridge ?? ""
                return .succeeded(
                    headline: LocalizedStringResource(core: result.successHeadline),
                    body: LocalizedStringResource(core: result.successBody(bridgeName: bridgeName)))
            }
        case .returnToBridge:
            guard let port = plan.port else { return }
            let operationPort = OperationPort(port.port)
            hub.start(steps: plan.steps, portID: port.id) { progress in
                let result = try await OperationHost.burst { session in
                    try ReturnToBridge(port: operationPort).perform(
                        session: session, environment: environment, progress: progress)
                }
                return .succeeded(
                    headline: LocalizedStringResource(core: result.successHeadline),
                    body: LocalizedStringResource(core: result.successBody))
            }
        case .stopManaging:
            guard let port = plan.port else { return }
            let operationPort = OperationPort(port.port)
            // §7.3: forgetting a note needs no password and writes nothing to
            // the network, so no credential is taken for it.
            hub.start(steps: []) { _ in
                let confirmation = try await OperationHost.withoutACredential {
                    try StopManaging(port: operationPort).perform(environment: environment)
                }
                return .succeeded(
                    headline: nil, body: LocalizedStringResource(core: confirmation))
            }
        case .all:
            let operationPorts = plan.ports.map { OperationPort($0.port) }
            hub.start(steps: plan.steps) { progress in
                let outcome = try await OperationHost.burst { session in
                    RestoreAll(ports: operationPorts).perform(
                        session: session, environment: environment, progress: progress)
                }
                // §S10: the summary never rounds up. When one port did not
                // finish, that is what the sheet says; a refusal with nothing
                // restored is the refusal itself.
                if let summary = outcome.summary {
                    if outcome.results.isEmpty, let first = outcome.unfinished.first {
                        // A failure with no number of its own keeps its own
                        // text: §6.1's "Nothing has been changed." with
                        // `Copy Details`, never a refusal it did not raise.
                        guard let refusal = first.refusal else {
                            return .failed(details: first.details ?? "")
                        }
                        return .refused(refusal)
                    }
                    return .succeeded(headline: nil, body: LocalizedStringResource(core: summary))
                }
                return .succeeded(
                    headline: "Everything is back",
                    body: "Nothing else on this Mac was touched.")
            }
        }
    }

    /// R21's `Remove My Service Only`: RDMALink deletes the service it made —
    /// "that part is squarely its own" — and keeps the note, because the
    /// bridge it came from is somebody else's to rebuild.
    private func runServiceOnly(_ plan: RestorePlan) {
        guard let port = plan.port else { return }
        let operationPort = OperationPort(port.port)
        let environment = hub.environment
        let steps = plan.steps.filter {
            if case .deleteCreatedService = $0 { return true }
            return false
        }
        hub.start(steps: steps, portID: port.id) { progress in
            _ = try await OperationHost.burst { session in
                try RestorePort(port: operationPort, mode: .serviceOnly).perform(
                    session: session, environment: environment, progress: progress)
            }
            return .succeeded(
                headline: nil,
                body: LocalizedStringResource(core: RestorePort.serviceOnlyConfirmation))
        }
    }
}

/// S6's checklist, reused by §S10: one row per write, `circle.dotted` while
/// pending, a small `ProgressView` while running, `checkmark.circle.fill` when
/// done. While it is up the sheet has no buttons at all — there is no control
/// the app could honour once the burst has started.
struct RestoreChecklist: View {
    let run: OperationRun

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupedSection {
                ForEach(Array(run.steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 { RowDivider(leadingInset: 42) }
                    RestoreChecklistRow(step: step, state: run.states[index])
                }
            }
            // §8.2: "the apply and restore checklists announce each step as its
            // checkmark lands", politely, so they never interrupt mid-sentence.
            .onChange(of: run.states) { previous, current in
                for index in current.indices
                where current[index] == .done && previous.indices.contains(index)
                    && previous[index] != .done {
                    AccessibilityNotification.Announcement(
                        String(localized: LocalizedStringResource(
                            core: run.steps[index].done))).post()
                }
            }
            // §S10's own promise, kept on screen while the writes happen.
            Text("Leave every other setting alone")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct RestoreChecklistRow: View {
    let step: OperationStep
    let state: StepState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            symbol
                .frame(width: 20, alignment: .center)
                .accessibilityHidden(true)
            Text(LocalizedStringResource(core: step.text(state)))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .animation(.smooth(duration: 0.18), value: state)
    }

    @ViewBuilder
    private var symbol: some View {
        switch state {
        case .pending:
            Image(systemName: "circle.dotted")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
        case .reversing:
            // §3.3's Restore symbol, which is what a reversing row is doing.
            Image(systemName: "arrow.uturn.backward")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
    }
}
