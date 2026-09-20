//
//  WizardRefusalCard.swift
//
//  A `WizardRefusal` drawn in the one shape §6.1 gives every refusal, reusing
//  the hub's `RefusalCard` so a refusal raised in the assistant and a refusal
//  raised on the hub are the same object on screen.
//
//  The first action is the default. A refusal with no actions is one that
//  watches itself and clears (rule 5), and it says so instead of offering a
//  button it would have to take away again.
//

import SwiftUI

struct WizardRefusalCard: View {
    let refusal: WizardRefusal
    let model: InventoryModel
    let perform: (WizardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // §6.1 rule 7: a refusal that follows a partial write states the
            // rollback first, before explaining anything else.
            if let rollbackLine = refusal.rollbackLine {
                Text(rollbackLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            RefusalCard(
                symbol: refusal.symbol,
                tint: refusal.isAttention ? .attention : .secondary,
                headline: refusal.headline,
                message: refusal.body,
                extraMessage: refusal.detail
            ) {
                ForEach(Array(refusal.actions.enumerated()), id: \.element) { index, action in
                    button(action, isDefault: index == 0)
                }
            }
            if let watchingLine = refusal.watchingLine {
                Text(watchingLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // §8.2: "Refusals are announced assertively, once, because they stop
        // the flow." Keyed on the code, so a card that stays put through a
        // live re-read is not announced again.
        .task(id: refusal.code) {
            AccessibilityNotification.Announcement(String(localized: refusal.headline)).post()
        }
    }

    @ViewBuilder
    private func button(_ action: WizardAction, isDefault: Bool) -> some View {
        if action.isCopyDetails {
            // §6.1 rule 8: the payload carries the technical names whatever
            // the toggle says, and it is the same text as a diagnostics file.
            CopyButton(title: action.title) {
                model.diagnosticsText(failingStep: refusal.code)
            }
        } else if isDefault {
            Button(action.title) { perform(action) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        } else {
            Button(action.title) { perform(action) }
        }
    }
}
