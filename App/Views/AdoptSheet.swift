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
    /// Which form the sheet opened in, resolved once.
    ///
    /// Adopting writes the note that makes `AdoptForm(port)` return nil, so
    /// deriving the form from the live port empties the sheet the moment the
    /// adopt succeeds — during the very beat §S9 keeps it up to show the
    /// confirmation. The live port is still read for the findings rows.
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
                fullMatchContent(port)
            case .nearMatch:
                nearMatchContent(port)
            }
        }
    }

    // MARK: - Full match

    @ViewBuilder
    private func fullMatchContent(_ port: PortSnapshot) -> some View {
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
        // them two ways.
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringResource(core: AdoptPort.note))
                .fixedSize(horizontal: false, vertical: true)
            Text(LocalizedStringResource(core: AdoptPort.honestyNote))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        // §2.6's row: `Cancel` just before the default.
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Adopt") { adopt(port) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
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
        guard let world = hub.world, let environment = hub.environment else { return }
        let operationPort = OperationPort(port.port)
        hub.start(steps: []) { _ in
            let confirmation = try await OperationHost.withoutACredential {
                try AdoptPort(port: operationPort).perform(
                    world: world, environment: environment)
            }
            return .succeeded(headline: nil, body: LocalizedStringResource(core: confirmation))
        }
    }
}
