//
//  AssistantColumn.swift
//
//  The right-hand column: four fixed bands, top to bottom — header row,
//  working area, the permanent port list, footer (UX_SPEC §2.3).
//

import SwiftUI

struct AssistantColumn: View {
    let model: InventoryModel
    /// §2.4: the list is the write half of the two-way mapping, so it needs the
    /// same selection the stage draws from.
    let stage: StageModel
    let router: HubRouter
    let showsTechnicalNames: Bool
    /// The USB-only receptacle that raised R3, from either side of the
    /// mapping (§4.5).
    var usbTip: USBTip?
    var onUSBClick: (String) -> Void
    var dismissUSBTip: () -> Void
    var turnAndBreathe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Absent on the hub by design (§2.3 band 1); the wizard steps in
            // ML2 pass a title and a `Step n of 5` caption.
            AssistantHeaderRow(title: nil, stepCaption: nil)
            WorkingArea(
                model: model, stage: stage, usbTip: usbTip,
                dismissUSBTip: dismissUSBTip, turnAndBreathe: turnAndBreathe
            )
            .padding(.bottom, 12)
            PortList(
                ports: model.ports,
                stage: stage,
                isProbing: model.phase == .probing,
                showsTechnicalNames: showsTechnicalNames,
                onUSBClick: onUSBClick
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if model.phase == .ready {
                AssistantFooter(router: router)
                    .padding(.top, 12)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.windowBackground)
    }
}

/// Band 1. A label, never a progress bar.
struct AssistantHeaderRow: View {
    let title: LocalizedStringResource?
    let stepCaption: LocalizedStringResource?

    var body: some View {
        if let title {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 12)
                if let stepCaption {
                    Text(stepCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)
        }
    }
}

/// Band 4.
///
/// ML1 is the read-only hub, so the footer holds no primary button at all —
/// the same shape R23 describes, and for the same reason: a disabled default
/// button is still an invitation to hunt for the modifier key (§1.3 rule 5).
/// What it does carry is §S1's link row.
struct AssistantFooter: View {
    let router: HubRouter

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                // §S1's link row is `Change Log` · `What This All Means`. ML3
                // owns the change log, and §1.3 rule 5 is why the link is
                // absent rather than present and permanently unavailable: a
                // disabled control is still an invitation. The same reasoning
                // keeps `Change Log ⌘L` off §2.7's View menu for now.
                // **Owed:** both, with the log behind them.
                Button("What This All Means") {
                    router.sheet = .whatThisAllMeans
                }
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .buttonStyle(.link)
            .font(.caption)
            .padding(.top, 10)
        }
    }
}
