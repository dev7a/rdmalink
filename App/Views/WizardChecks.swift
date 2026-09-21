//
//  WizardChecks.swift
//
//  S3 — The four checks, as S5's **Checked** group (UX_SPEC §S3, §S5): one
//  collapsed disclosure line when every check is satisfied, the four rows
//  when one is not, and `Check Again` in the header only while something is
//  left to sort out.
//
//  Nothing here is a checkbox and nothing here can be waved through. Every
//  row states a finding the app measured; a row that has not been measured
//  yet says so with `circle.dotted` rather than claiming to be fine.
//

import SwiftUI

struct WizardChecksGroup: View {
    let report: PreflightReport
    let perform: (WizardAction) -> Void

    /// Opened by hand, to read the four findings behind the one line.
    @State private var isOpened = false

    /// §S3: "collapsed when every one is satisfied and expanded when one is
    /// not" — a fact about the checks before it is a preference, so a row
    /// that said no opens the group whatever the chevron was left at.
    private var isExpanded: Binding<Bool> {
        Binding(
            get: { report.isExpanded || isOpened },
            set: { isOpened = $0 })
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            GroupedSection {
                ForEach(Array(report.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { RowDivider(leadingInset: 42) }
                    WizardCheckRow(row: row, perform: perform)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let label = report.groupLabel {
                    Text(label)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // A row is still checking, and the label claims nothing
                    // it has not verified (§1.3 rule 10).
                    ProgressView().controlSize(.small)
                }
                Spacer(minLength: 0)
                if report.unsatisfiedCount > 0 {
                    Button(WizardAction.checkAgain.title) { perform(.checkAgain) }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.smooth(duration: 0.18), value: report.isExpanded)
        .animation(.smooth(duration: 0.18), value: report.groupLabel == nil)
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
