//
//  WizardApply.swift
//
//  S6 — Setting up (UX_SPEC §S6). The burst, which begins the moment macOS
//  hands back the permission S5's button asked for, and which has **no
//  buttons at all** — there is no control the app could honour once that
//  thirty-second permission is in hand.
//
//  `SetUpFlow.primary` returns `nil` here, so the footer's trailing button is
//  gone rather than greyed, and `showsBack` turns the leading one off with
//  it — for good: a refused S6's card holds every way out (§S6).
//

import SwiftUI
import RDMALinkCore

struct WizardApply: View {
    let flow: SetUpFlow
    let model: InventoryModel
    let perform: (WizardAction) -> Void

    var body: some View {
        if let run = flow.apply {
            content(run)
        }
    }

    @ViewBuilder
    private func content(_ run: ApplyRun) -> some View {
        switch run.phase {
        case .authorizing:
            // Never drawn: the flow keeps S5 on screen, dimmed, until the
            // permission lands (§S5), and only then moves here.
            EmptyView()
        case .refused:
            VStack(alignment: .leading, spacing: 12) {
                // §S6, §2.3 band 1: the card replaces the screen, so its
                // headline leads it and carries the step label.
                if let refusal = flow.applyRefusal {
                    WizardRefusalCard(refusal: refusal, model: model, perform: perform)
                }
                // §S10's rule, applied to set-up: the summary never rounds up.
                // The ports that landed are listed under the card, and the
                // card leaves off its "Nothing has been changed." then
                // (`SetUpFlow.applyRefusal`), so "Put back, safely" is never
                // read as a claim about a Mac that is half-changed (§S6).
                if !run.landedLines.isEmpty {
                    GroupedSection {
                        ForEach(Array(run.landedLines.enumerated()), id: \.offset) { index, line in
                            if index > 0 { RowDivider(leadingInset: 42) }
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                PortRowSymbol(name: "checkmark.circle.fill", style: .accent)
                                Text(line)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 7)
                            .padding(.horizontal, 12)
                        }
                    }
                }
            }
        case .running, .finished:
            checklist(run)
        }
    }

    private func checklist(_ run: ApplyRun) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WizardHeadline(headline: run.runningHeadline, message: ApplyRun.runningBody)
            GroupedSection {
                ForEach(Array(run.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { RowDivider(leadingInset: 42) }
                    WizardApplyRow(row: row)
                }
            }
            Text(run.isReversing ? ApplyRun.rollbackLine : ApplyRun.statusLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let completion = run.completionLine {
                Text(completion)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.18), value: run.phase)
        // §8.2: "the apply and restore checklists announce each step as its
        // checkmark lands", politely — they never interrupt mid-sentence.
        .onChange(of: run.rows.map(\.state)) { previous, current in
            for index in current.indices
            where current[index] == .done && previous.indices.contains(index)
                && previous[index] != .done {
                AccessibilityNotification.Announcement(run.rows[index].text).post()
            }
        }
        .task(id: run.phase) {
            // §S6: S7 follows about 400 ms after the last checkmark settles.
            guard run.phase == .finished else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            flow.advanceToReady()
        }
    }
}

/// One checklist row: `circle.dotted` while pending, a small `ProgressView`
/// while running, `checkmark.circle.fill` when done, and a returning symbol
/// while a rollback reverses it.
struct WizardApplyRow: View {
    let row: ApplyStepRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            symbol
            Text(row.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .animation(.smooth(duration: 0.18), value: row)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var symbol: some View {
        if let name = row.symbol {
            PortRowSymbol(name: name, style: style)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20, alignment: .center)
        }
    }

    private var style: PortSymbolStyle {
        switch row.state {
        case .pending: .tertiary
        case .running: .secondary
        case .done: .accent
        // §3.1: no colour carries meaning here either — a reversing row is
        // quieter than a done one, not louder.
        case .reversing: .secondary
        }
    }
}
