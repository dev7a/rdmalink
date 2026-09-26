//
//  WizardChoosePort.swift
//
//  S4 — Choose a port (UX_SPEC §S4), with S4b as a modal state inside it.
//
//  The list is the canonical answer and the model is the accelerator, so
//  nothing here duplicates the port list: it states the reason for the
//  pre-selection, offers Identify, and prints the informational lines a
//  chosen port earns.
//

import SwiftUI

struct WizardChoosePort: View {
    let flow: SetUpFlow
    let model: InventoryModel
    let perform: (WizardAction) -> Void

    var body: some View {
        // §S4b is a modal *state* within S4: the working area swaps, the stage
        // stays fully live, and the port list stays where it is.
        if flow.identify != nil {
            WizardIdentify(flow: flow)
                .transition(.opacity)
        } else {
            chooser(flow.choose)
                .transition(.opacity)
        }
    }

    /// The report is worked out once per body evaluation, not once per line.
    private func chooser(_ report: ChoosePortReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WizardHeadline(headline: ChoosePortReport.headline, message: report.body)
            if let line = report.preSelectionLine {
                Text(line)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // §3.3: Identify is `hand.point.up.left`, offered above the list —
            // which is also where §4.7 promotes it on a recognized Mac whose
            // port names are only macOS's numbering. In the accent, at its
            // regular size (§2.3 band 3): borderless, it would otherwise draw
            // in the same gray as the lines around it. No shortcut of its
            // own: ⌘I is the Port menu's, which starts this same Identify on
            // this screen (§S4, §2.7) — one declaration, so AppKit never has
            // two to choose between.
            Button {
                perform(.identifyPort)
            } label: {
                Label(WizardAction.identifyPort.title, systemImage: "hand.point.up.left")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(report.informationalLines) { line in
                Text(line.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = report.multiSelectNote {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let line = flow.liveChangeLine {
                Text(line)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if let line = flow.routingLine {
                // R27 — routing, not refusing. No card, no closed door.
                Text(line)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            // §6.1 rule 3: both cards sit under the picker's own headline, so
            // theirs steps down to `.headline`.
            if let refusal = flow.refusal {
                WizardRefusalCard(refusal: refusal, model: model, perform: perform, isNested: true)
            }
            if let occupied = report.everyPortOccupied, flow.refusal == nil {
                // R26 — a dead end handled kindly. No buttons: it watches and
                // clears itself.
                WizardRefusalCard(
                    refusal: occupied, model: model, perform: perform, isNested: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.18), value: flow.refusal)
        .animation(.smooth(duration: 0.18), value: flow.liveChangeLine == nil)
        .animation(.smooth(duration: 0.18), value: flow.routingLine == nil)
    }
}
