//
//  WizardFooter.swift
//
//  Band 4 while the assistant is up (UX_SPEC §2.3): a separator, `Back` —
//  `Cancel` on the picker, where it leaves the assistant — leading, and the
//  primary trailing with `.keyboardShortcut(.defaultAction)`,
//  contextual `.caption` secondary text between them, and — directly **above**
//  the separator — the reason the primary is unavailable, in `.callout`
//  `.primary` behind an orange attention symbol.
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
                FooterReason(reason: reason)
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

/// §2.3 band 4: why the primary is unavailable, directly above the separator.
/// The words are `.callout` `.primary` and carry the meaning, so the orange
/// symbol in front of them is hidden from VoiceOver. The text is never orange
/// itself: system orange measures 2.3:1 on the light window background, and
/// text needs 4.5:1 (§3.1). The hub's footer prints its reason the same way.
struct FooterReason: View {
    let reason: LocalizedStringResource

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(reason)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}
