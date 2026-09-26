//
//  AdoptSheet.swift
//
//  S9 — recognise a port somebody already configured by hand and take
//  responsibility for it **without touching it**.
//
//  Two forms and no third: a full match, which can be adopted with a note and
//  no password, and a near match, which is never adjusted — RDMALink did not
//  make that service and will not rewrite it, so it shows exactly what
//  differs, hands over the steps, and keeps watching (§7.3).
//

import AppKit
import SwiftUI
import RDMALinkCore

struct AdoptSheet: View {
    let portID: String
    let hub: HubActionsModel
    /// `Copy Details` carries the same payload as a diagnostics file (§6.1
    /// rule 8).
    let model: InventoryModel
    @Environment(\.dismiss) private var dismiss
    /// The form on screen: the one the sheet opened in, then whatever the
    /// port becomes while nothing is running (§S9, "The sheet follows the
    /// port"; `AdoptForm.following`).
    ///
    /// Kept, not derived from the live port on every read: adopting writes
    /// the note that makes `AdoptForm(port)` return nil, so a derived form
    /// would empty the sheet the moment the adopt succeeds — during the very
    /// beat §S9 keeps it up to show the confirmation. The live port is still
    /// read for the findings rows.
    @State private var form: AdoptForm?

    private var port: PortSnapshot? { hub.snapshot(id: portID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let port, let form {
                content(port: port, form: form)
            }
        }
        .padding(24)
        .frame(width: 500, alignment: .leading)
        .animation(.smooth(duration: 0.18), value: hub.run)
        // §2.6: Escape closes the sheet, but not while the note is being
        // written — its answer would land on nothing.
        .interactiveDismissDisabled(hub.run?.isRunning == true)
        .task {
            // §S9: "Not a match at all (no `Adopt…` button is ever offered)".
            // If one is somehow reached anyway, there is nothing here to say.
            guard let port, let resolved = AdoptForm(port) else { return dismiss() }
            form = resolved
        }
        // §S9: a near match put right while the sheet is up becomes the full
        // match, `Adopt` and all. Never once `Adopt` has been pressed: its
        // answer is the sheet's then.
        .onChange(of: port.flatMap { AdoptForm($0) }) { _, live in
            guard let form,
                let next = AdoptForm.following(form, live: live, adopting: hub.run != nil)
            else { return }
            self.form = next
        }
        .onDisappear { hub.sheetDismissed() }
    }

    @ViewBuilder
    private func content(port: PortSnapshot, form: AdoptForm) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(form.headline)
                .font(.title2.weight(.semibold))
            Text(form.body(port))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let run = hub.run {
            outcome(run, port: port)
        } else {
            switch form {
            case .fullMatch:
                fullMatchContent(port, form: form)
            case .nearMatch:
                nearMatchContent(port)
            }
        }
    }

    // MARK: - Full match

    @ViewBuilder
    private func fullMatchContent(_ port: PortSnapshot, form: AdoptForm) -> some View {
        GroupedSection {
            ForEach(Array(AdoptFindings.rows(port).enumerated()), id: \.offset) { index, row in
                if index > 0 { RowDivider(leadingInset: 42) }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(row)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
            }
        }
        // §S9's two notes are Core's, which `AdoptPort.preview` hands the
        // command-line tool too, so the sheet and the tool can never word
        // them two ways — the honesty note in whichever form the port needs.
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringResource(core: AdoptPort.note))
                .fixedSize(horizontal: false, vertical: true)
            if let honesty = form.honestyNote {
                Text(honesty)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            if form.adoptIsDefault {
                // §2.6's row: `Cancel` just before the default.
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Adopt") { adopt(port) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                // §2.6: adopting here forgets the only record of the bridges
                // the port came from, so the row has no default — `Cancel`
                // takes the trailing slot and Return presses nothing.
                Button("Adopt") { adopt(port) }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    // MARK: - Near match

    @ViewBuilder
    private func nearMatchContent(_ port: PortSnapshot) -> some View {
        GroupedSection {
            Text(AdoptFindings.steps(port))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
        }
        Text(LocalizedStringResource(core: AdoptPort.watcherLine))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        // §2.6's row: `Cancel` just before the default.
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            CopyButton(title: "Copy These Steps") { String(localized: AdoptFindings.steps(port)) }
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Open Network Settings") {
                WizardSettingsPane.open(WizardSettingsPane.network)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Adopting

    @ViewBuilder
    private func outcome(_ run: OperationRun, port: PortSnapshot) -> some View {
        switch run.outcome {
        case .none:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .center)
        case .succeeded(_, let body):
            Text(body)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .task { hub.closeAfterConfirmation { dismiss() } }
        case .refused(let refusal):
            RefusalCard(
                symbol: RestoreRefusals.symbol(for: refusal.code),
                tint: RestoreRefusals.isAttention(refusal.code) ? .attention : .secondary,
                headline: LocalizedStringResource(core: refusal.headline),
                message: LocalizedStringResource(core: refusal.body),
                extraMessage: refusal.detail.map { LocalizedStringResource(core: $0) },
                buttonRowAlignment: .trailing,
                // §6.1 rule 3: the sheet's own headline stays above it.
                isNested: true
            ) {
                // No default here, so `Cancel` takes the trailing slot
                // (§2.6): the question the sheet asked is no longer on screen.
                CopyDetailsButton { model.diagnosticsText(failingStep: refusal.code.rawValue) }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        case .failed(let details):
            VStack(alignment: .leading, spacing: 8) {
                // §6.1's shared line. Adopting writes a note and nothing else,
                // so this is simply true.
                Text("Nothing has been changed.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(verbatim: details)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    CopyDetailsButton { model.diagnosticsText(failingStep: "adopting a port") }
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }

    /// §7.3: adopting changes nothing and needs no password — it writes a note
    /// and a log entry, which is why there is no checklist here.
    private func adopt(_ port: PortSnapshot) {
        // No reading is asked of the sheet: the run takes its own, and one
        // that fails is its answer, with details, so `Adopt` is never a
        // button that silently does nothing.
        guard let environment = hub.environment else { return }
        let operationPort = OperationPort(port.port)
        // Core asks the note what the sheet asked it: RDMALink's own service
        // is never adopted, and a note whose service is gone, or a return
        // record whose port has moved on, is replaced (§S9).
        let existingNote = port.baseline
        let hub = hub
        hub.start(steps: []) { _ in
            // §S9: the sheet follows the port, so the reading taken when it
            // opened may still describe the near match it was then, and Core
            // would refuse to adopt that. This Mac is read again first —
            // read-only, as every sheet's reading is — so the note is written
            // against the port the sheet is showing.
            await hub.readWorld()
            guard let world = await hub.world else {
                let failure = await hub.worldFailure ?? "no reading"
                throw NetworkConfigurationError.missing("a reading of this Mac: \(failure)")
            }
            let confirmation = try await OperationHost.withoutACredential {
                try AdoptPort(port: operationPort, existingNote: existingNote).perform(
                    world: world, environment: environment)
            }
            return .succeeded(headline: nil, body: LocalizedStringResource(core: confirmation))
        }
    }
}
