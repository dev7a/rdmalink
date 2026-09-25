//
//  WizardFooter.swift
//
//  Band 4 while the assistant is up (UX_SPEC §2.3): a separator, `Back` —
//  `Cancel` on the run's first screen, where it leaves the assistant —
//  leading, and the primary trailing with `.keyboardShortcut(.defaultAction)`,
//  the screen's other buttons just before it, contextual `.caption` secondary
//  text after `Back`, and — directly **above** the separator — the reason the
//  primary is unavailable, in `.callout` `.primary` behind an orange attention
//  symbol. Every button a screen owns is here; band 2 keeps none of its own.
//
//  The primary is **absent**, not greyed, whenever a refusal has taken the
//  screen: a disabled button is still an invitation to hunt for the modifier
//  key (§1.3 rule 5, §6.1 rule 6). There is no `Continue Anyway` in this file.
//

import AppKit
import SwiftUI

struct WizardFooter: View {
    let flow: SetUpFlow
    /// What a secondary button does — the same `WizardPerformer` band 2's
    /// cards press.
    let perform: (WizardAction) -> Void

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
                    // §8.3: this is Escape's button. On the picker with a card
                    // up, Escape puts the card away first (`SetUpFlow.escape`)
                    // while a click keeps the button's words and its meaning:
                    // it is still `Cancel`. One button and one key
                    // equivalent, told apart by the event that pressed it.
                    Button(flow.backTitle) {
                        if Self.pressedByEscape { flow.escape() } else { flow.goBack() }
                    }
                    .keyboardShortcut(.cancelAction)
                }
                if let caption = flow.footerCaption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                // §2.3 band 4: the screen's other buttons, just before the
                // default — S4b's and S7's.
                ForEach(flow.footerSecondaries) { action in
                    Button(action.title) { perform(action) }
                }
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

    /// Whether the button's action is running because of Escape — or
    /// ⌘-period, the other key AppKit gives `.cancelAction` — rather than a
    /// click, or Space on the focused button, which press `Cancel` as its
    /// title says. SwiftUI's button action does not describe what pressed it,
    /// so the event still current while it runs is read, as the port list
    /// reads a click's modifiers (`PortGroupSection.isExtendingClick`).
    private static var pressedByEscape: Bool {
        guard let event = NSApp.currentEvent, event.type == .keyDown else { return false }
        return event.keyCode == 53  // kVK_Escape
            || (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == ".")
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
