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
        VStack(alignment: .leading, spacing: 6) {
            Text("Adopting changes nothing and needs no password. RDMALink is only writing itself a note.")
                .fixedSize(horizontal: false, vertical: true)
            Text("One thing to be straight about: RDMALink never saw this port before, so it doesn't know which bridge it came from. There's no exact \"put it back\" for an adopted port — Return to Bridge does the ordinary thing instead, and \"stop looking after it\" leaves the port exactly as it is.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Button("Leave As Is") { dismiss() }
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
        Text("I'll keep looking. When it matches, I'll offer to adopt it.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Button("Leave As Is") { dismiss() }
            CopyButton(title: "Copy These Steps") { String(localized: AdoptFindings.steps(port)) }
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
                extraMessage: refusal.detail.map { LocalizedStringResource(core: $0) }
            ) {
                CopyDetailsButton { model.diagnosticsText(failingStep: refusal.code.rawValue) }
                Button("Leave As Is") { dismiss() }
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
                    Button("Leave As Is") { dismiss() }
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

/// Which of §S9's two forms a port is in. A port that is not a match at all is
/// neither, and is never offered this sheet.
enum AdoptForm: Sendable, Equatable {
    case fullMatch
    case nearMatch([ConfigurationDifference])

    init?(_ port: PortSnapshot) {
        switch port.configuration {
        case .readyForRDMA?:
            // A port RDMALink already looks after has nothing to adopt. A
            // return record is not that: its port has left the bridge and been
            // given a matching service since, so the record describes nothing
            // current, and adopting replaces it with the adopted note (the
            // same replacement §7.5 step 5 describes for set-up).
            guard port.baseline?.isReturned != false else { return nil }
            self = .fullMatch
        case .nearMatch(_, let differences)?:
            // §7.3: Adopt is for a port that is "out of every bridge, its own
            // service". A port still in a bridge is not that case, and §S9's
            // near-match body opens by saying it is — so it is not offered
            // this sheet rather than shown a sentence that contradicts itself.
            // Core's `AdoptPort.preview` makes the same call.
            guard !differences.contains(where: \.isBridgeMembership),
                AdoptFindings.clause(for: differences) != nil
            else { return nil }
            self = .nearMatch(differences)
        case .unconfigured?, .foreign?, nil:
            return nil
        }
    }

    var headline: LocalizedStringResource {
        switch self {
        case .fullMatch: "This port is already set up"
        case .nearMatch: "Nearly a match"
        }
    }

    func body(_ port: PortSnapshot) -> LocalizedStringResource {
        let name = port.port.positionName
        switch self {
        case .fullMatch:
            return "\(name) isn't in any bridge and already has its own service with IPv4 off and IPv6 link-local only. That's exactly what RDMALink would have made. Adopt it and RDMALink will keep an eye on it — without changing a thing."
        case .nearMatch(let differences):
            let clause = AdoptFindings.clause(for: differences) ?? ""
            return "\(name) is out of every bridge and has its own service, but \(clause). RDMALink didn't make this service, so it won't rewrite it — but here's exactly what to change, and it'll adopt the port the moment it matches."
        }
    }
}

/// §S9's four findings rows, its steps, and the one clause its near-match body
/// names the difference in.
enum AdoptFindings {
    /// **Service — Thunderbolt Bridge Free** · **IPv4 — Off** ·
    /// **IPv6 — Link-local only** · **Bridge membership — None**.
    static func rows(_ port: PortSnapshot) -> [LocalizedStringResource] {
        [
            "Service — \(port.serviceName ?? port.port.bsdName)",
            "IPv4 — Off",
            "IPv6 — Link-local only",
            "Bridge membership — None",
        ]
    }

    static func steps(_ port: PortSnapshot) -> LocalizedStringResource {
        "In System Settings, open Network, choose \(port.serviceName ?? port.port.bsdName), then Details, then TCP/IP. Set Configure IPv6 to Link-local only. Set Configure IPv4 to Off."
    }

    /// §S9 writes the near-match body for one difference — IPv6 set to
    /// Automatic — and the sentence it writes has a shape the other
    /// differences fit: *"\<what\> is set to \<this\> rather than \<that\>"*.
    /// The clauses are Core's, so the sheet and `AdoptPort.preview` can never
    /// name the difference two different ways.
    ///
    /// Bridge membership is never one of them: the body's own first clause
    /// says the port is out of every bridge (§1.3 rule 10).
    /// **Owed from the spec owner:** the near-match body for each of them.
    static func clause(for differences: [ConfigurationDifference]) -> String? {
        ConfigurationDifference.serviceClause(in: differences)
    }
}
