//
//  WizardFooter.swift
//
//  Band 4 while the assistant is up (UX_SPEC §2.3): a separator, `Back`
//  leading and the primary trailing with `.keyboardShortcut(.defaultAction)`,
//  contextual `.caption` secondary text between them, and — directly **above**
//  the separator — the reason the primary is unavailable, in `.callout`
//  `.orange`.
//
//  The primary is **absent**, not greyed, whenever a refusal has taken the
//  screen: a disabled button is still an invitation to hunt for the modifier
//  key (§1.3 rule 5, §6.1 rule 6). There is no `Continue Anyway` in this file.
//

import SwiftUI

struct WizardFooter: View {
    let flow: SetUpFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let reason = flow.disabledReason {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
            Divider()
            HStack(spacing: 12) {
                if flow.showsBack {
                    Button(flow.backTitle) { flow.goBack() }
                        .keyboardShortcut(.cancelAction)
                }
                if let caption = flow.footerCaption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let primary = flow.primary {
                    Button(primary.title) { flow.goForward() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!primary.isEnabled)
                }
            }
            .padding(.top, 10)
        }
        .animation(.smooth(duration: 0.18), value: flow.step)
    }
}
