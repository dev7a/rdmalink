//
//  AssistantColumn.swift
//
//  The right-hand column: four fixed bands, top to bottom — header row,
//  working area, the permanent port list, footer (UX_SPEC §2.3).
//

import SwiftUI

struct AssistantColumn: View {
    let model: InventoryModel
    let showsTechnicalNames: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Absent on the hub by design (§2.3 band 1); the wizard steps in
            // ML1 pass a title and a `Step n of 5` caption.
            AssistantHeaderRow(title: nil, stepCaption: nil)
            WorkingArea(
                phase: model.phase,
                isSlowProbe: model.isSlowProbe,
                rdma: model.rdma,
                ports: model.ports
            )
            .padding(.bottom, 20)
            PortList(
                ports: model.ports,
                isProbing: model.phase == .probing,
                showsTechnicalNames: showsTechnicalNames
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            AssistantFooter(showsPrimaryButton: model.phase == .ready)
                .padding(.top, 16)
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

/// Band 4. A separator, then the primary button on the trailing edge.
struct AssistantFooter: View {
    let showsPrimaryButton: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer(minLength: 0)
                if showsPrimaryButton {
                    Button("Set Up a Port…") {
                        // ML1 opens the preflight step here.
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(true)
                }
            }
            .padding(.top, 12)
        }
    }
}
