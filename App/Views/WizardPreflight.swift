//
//  WizardPreflight.swift
//
//  S3 — Before we change anything (UX_SPEC §S3).
//
//  Nothing on this screen is a checkbox and nothing here can be waved through.
//  Every row states a finding the app measured; a row that has not been
//  measured yet says so with `circle.dotted` rather than claiming to be fine.
//

import SwiftUI

struct WizardPreflight: View {
    let flow: SetUpFlow
    let model: InventoryModel
    let perform: (WizardAction) -> Void

    var body: some View {
        // Worked out once per body evaluation, not once per line.
        let report = flow.preflight
        VStack(alignment: .leading, spacing: 14) {
            if let replacement = report.replacement {
                // R13 replaces the whole list. Identify, the model and the
                // port list all keep working, so the app is still a map.
                WizardRefusalCard(refusal: replacement, model: model, perform: perform)
            } else {
                WizardHeadline(
                    headline: PreflightReport.headline, message: PreflightReport.body)
                GroupedSection {
                    ForEach(Array(report.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { RowDivider(leadingInset: 42) }
                        WizardCheckRow(row: row, perform: perform)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One check row: a symbol, a title, the actual finding, and a trailing
/// borderless button only where one helps.
struct WizardCheckRow: View {
    let row: PreflightRow
    let perform: (WizardAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PortRowSymbol(name: row.state.symbol, style: style)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                if let finding = row.finding {
                    Text(finding)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action = row.action {
                Button(action.wizardAction.title) { perform(action.wizardAction) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        // §S3: "rows animate individually" as the world changes underneath.
        .animation(.smooth(duration: 0.18), value: row)
    }

    private var style: PortSymbolStyle {
        switch row.state {
        case .checking: .tertiary
        case .satisfied: .accent
        case .unsatisfied: .attention
        }
    }
}
