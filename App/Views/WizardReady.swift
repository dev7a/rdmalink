//
//  WizardReady.swift
//
//  S7 — Ready (UX_SPEC §S7). The payoff.
//
//  The `fe80::` address is shown in full, always, whatever "Show technical
//  names" says, because tools need every character of it. It wraps at a colon
//  group and is never truncated with an ellipsis: a half-shown address is
//  worse than a wrapped one (§8.5).
//

import AppKit
import SwiftUI
import RDMALinkCore

struct WizardReady: View {
    let flow: SetUpFlow
    let model: InventoryModel

    var body: some View {
        // Worked out once per body evaluation, not once per line.
        let report = flow.ready
        VStack(alignment: .leading, spacing: 14) {
            WizardHeadline(headline: report.headline, message: report.body)
            ForEach(report.blocks) { block in
                WizardAddressBlock(block: block)
            }
            if !report.statusRows.isEmpty {
                GroupedSection {
                    ForEach(Array(report.statusRows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { RowDivider(leadingInset: 42) }
                        WizardStatusRow(row: row)
                    }
                }
            }
            Text(ReadyReport.footnote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // `What to Do on the Other Mac` and `Done` are the footer's
            // (§S7, §2.3 band 4).
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.25), value: report.blocks)
    }
}

/// The value block: a `.caption` secondary label, the address in
/// `.body.monospaced()` and selectable, and `Copy Address` on the trailing edge.
struct WizardAddressBlock: View {
    let block: ReadyValueBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(ReadyValueBlock.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let address = block.address {
                    CopyButton(title: "Copy Address") { address }
                        .inlineAction()
                }
            }
            if let address = block.address {
                Text(address)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(address))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(block.positionName))
    }
}

struct WizardStatusRow: View {
    let row: ReadyStatusRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            PortRowSymbol(name: row.symbol, style: row.isAttention ? .attention : .accent)
            Text(row.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if row.action == .turnItOn {
                Button("Turn It On…") {
                    NSWorkspace.shared.open(WizardSettingsPane.developerTools)
                }
                .inlineAction()
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
    }
}
