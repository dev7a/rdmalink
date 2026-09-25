//
//  WizardReview.swift
//
//  S5 — Here's what will change (UX_SPEC §S5). The promise screen: everything
//  the app is about to do, in plain words, with the technical truth one
//  checkbox away, and the last chance to back out before any password —
//  which its default button asks for straight away.
//
//  Every string in the sections is Core's `SetUpPortsPlan`, which holds §S5's
//  table verbatim. Above them: §S3's four checks as the Checked group — and
//  never a pre-selection line, because the choice was made before this
//  screen, on the picker or by the control that named the port (§S4). A refusal
//  **replaces** the sections and the footer's primary button is removed
//  entirely rather than disabled (§6.1 rule 6) — which `SetUpFlow.primary`
//  does by returning `nil` — while a check that said no only disables it.
//

import SwiftUI
import RDMALinkCore

struct WizardReview: View {
    let flow: SetUpFlow
    let model: InventoryModel
    let preview: (ReviewPreview?, String) -> Void
    /// Takes any preview off the model, whichever port it was about.
    var clearPreview: () -> Void = {}
    let perform: (WizardAction) -> Void

    @AppStorage(AppSettings.showTechnicalNames) private var showsTechnicalNames = false
    @State private var showsWhatRDMALinkWontTouch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let refusal = flow.reviewRefusal {
                // A card replaces the screen, headline and all (§6.1 rule 3).
                // While macOS's password dialog is up it is inert: the burst
                // is waiting on the dialog, and no button here could cancel
                // it (`SetUpFlow.goBack`) — the screen "says nothing over it"
                // (§S5).
                WizardRefusalCard(refusal: refusal, model: model, perform: perform)
                    .disabled(flow.isAuthorizing)
            } else {
                // §S5: the headline and the body depend on nothing the plan
                // says, so they are drawn at once, and the spinner stands
                // where the Checked group and the sections will go — the app
                // never states a change it has not worked out yet (§1.3 rule
                // 10).
                WizardHeadline(
                    headline: LocalizedStringResource(core: SetUpPortsPlan.headline),
                    message: LocalizedStringResource(core: SetUpPortsPlan.body))
                if let plan = flow.reviewPlan {
                    sections(plan)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.18), value: showsWhatRDMALinkWontTouch)
        .animation(.smooth(duration: 0.18), value: showsTechnicalNames)
        // The pointer does not have to move for this screen to go away, so the
        // preview is cleared outright rather than by a row's hover ending.
        .onDisappear { clearPreview() }
    }

    private func sections(_ plan: SetUpPortsPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WizardChecksGroup(report: flow.checks, perform: perform)
            ForEach(plan.ports, id: \.port.bsdName) { port in
                WizardReviewSection(plan: port) { change, isHovering in
                    preview(isHovering ? ReviewPreview(change) : nil, port.port.bsdName)
                }
            }
            Text(SetUpPortsPlan.footnote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup(isExpanded: $showsWhatRDMALinkWontTouch) {
                Text(SetUpPortsPlan.whatRDMALinkWontTouch)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } label: {
                Text(SetUpPortsPlan.whatRDMALinkWontTouchLabel).font(.callout)
            }
            // §S5: a checkbox, not a disclosure, because that is what it is —
            // bound to the same preference as Settings' switch and the View
            // menu's item, so turning it on here turns technical names on
            // everywhere (§1.3 rule 6), which a disclosure triangle never
            // does. The technical lines sit beneath it while it is on.
            Toggle(isOn: $showsTechnicalNames) {
                Text("Show technical names").font(.callout)
            }
            .toggleStyle(.checkbox)
            if showsTechnicalNames {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(technicalLines(plan), id: \.id) { line in
                        Text(line.text)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
        }
    }

    private func technicalLines(_ plan: SetUpPortsPlan) -> [TechnicalLine] {
        plan.ports.flatMap { port in
            port.technicalNames.enumerated().map {
                TechnicalLine(id: "\(port.port.bsdName)-\($0.offset)", text: $0.element)
            }
        }
    }

    struct TechnicalLine: Identifiable {
        var id: String
        var text: String
    }
}

/// One selected port, headed by its position name.
struct WizardReviewSection: View {
    let plan: SetUpPortPlan
    let hover: (ReviewChange, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The header is the position name, which Core has already
            // localized, so it is drawn rather than looked up again.
            VStack(alignment: .leading, spacing: 5) {
                Text(plan.header)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                GroupedSection {
                    ForEach(Array(plan.rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { RowDivider(leadingInset: 42) }
                        WizardReviewRow(row: row, change: ReviewChange(rowIndex: index)) {
                            guard let change = ReviewChange(rowIndex: index) else { return }
                            hover(change, $0)
                        }
                    }
                }
            }
            ForEach(Array(plan.warnings.enumerated()), id: \.offset) { _, warning in
                // Never blocking and never scary: a line, not an alarm. The
                // orange symbol because the user has something to do — switch
                // RDMA on (§3.1).
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(warning)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // What is plugged in only informs: drawn as the picker draws the
            // same sentence, `.callout` secondary with no symbol (§S4, §S5).
            ForEach(Array(plan.informationalLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A symbol, a title, a `.callout` secondary sentence, and a before → after
/// pair of chips. Hovering it previews the change on the model, silently and
/// reversibly — you can watch each sentence mean something before you agree.
struct WizardReviewRow: View {
    let row: ReviewRow
    let change: ReviewChange?
    let hover: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PortRowSymbol(name: change?.symbol ?? "circle.dotted", style: .secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(row.title)
                Text(row.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                WizardChipPair(before: row.before, after: row.after)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(.rect)
        .onHover(perform: hover)
    }
}

/// §S5's "before → after pair of chips".
///
/// The pair is one line when the column has room for it and stacks when it
/// does not — the after chip under the before chip, the arrow leading it —
/// and either way every word is drawn. Row 4's pair is 60-odd characters,
/// which no working area between §2.1's 840 pt minimum and its 1000 pt
/// default can hold on one line; the old single `HStack` answered that by
/// cutting both chips to an ellipsis, which §8.5 forbids ("nothing is
/// truncated") and which turned the one row that names the real change
/// into "IPv4 automatic, IPv6 auto…".
///
/// `ViewThatFits` measures the one-line pair at its ideal width, so a chip
/// never wraps on its own inside the line; the stacked pair lets each chip
/// wrap in the ordinary way should a translation outgrow even that.
struct WizardChipPair: View {
    let before: String
    let after: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                WizardChip(text: before).fixedSize()
                arrow
                WizardChip(text: after, isAfter: true).fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                WizardChip(text: before)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    arrow
                    WizardChip(text: after, isAfter: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .imageScale(.small)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

/// A before or after chip. §3.1: no colour carries meaning — the difference
/// between the two is weight, and the arrow between them is the sentence.
///
/// `.callout`, the smallest role §3.2 gives a row's own words; a chip that
/// wraps is read at the same size as the sentence above it.
struct WizardChip: View {
    let text: String
    var isAfter = false

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(isAfter ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.background.secondary, in: .rect(cornerRadius: 10))
    }
}
