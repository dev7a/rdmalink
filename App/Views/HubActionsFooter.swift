//
//  HubActionsFooter.swift
//
//  Band 4 of the assistant column on the hub: §S1's link row under the port
//  list, the reason the primary is unavailable when it is, and the button row
//  itself — `Quit` at the leading edge, then `Set Up Port…` as the default
//  with `Restore…` beside it whenever a note exists (§S1, §2.3, §2.8). While
//  §S8 or §S11 holds the working area this steps aside for that screen's own
//  footer (`ScreenFooter`), so the window has one button row and one default.
//

import SwiftUI

struct HubActionsFooter: View {
    let footer: HubFooterModel
    let hub: HubActionsModel
    let router: HubRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            linkRow
            // §S1: with two Macs connected the primary is disabled "with the
            // reason printed above the footer separator".
            if let reason = footer.disabledReason {
                FooterReason(reason: reason)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
            // §2.8: "Restore is never hidden." Whenever any note exists it
            // is here, so nobody has to find a row first — any note it can
            // put something back from, which leaves out a return record
            // (§7.5). With only those, there is nothing to offer. R31 is
            // the one exception: on a Mac RDMALink does not recognize, the
            // footer holds `Quit` and nothing else, note or no note.
            let offersRestore = footer.offersRestore && hub.hasRestorableNote
            // The separator always rules off a row that always has `Quit` in
            // it — §S1 keeps it "present in every hub state, R23 and R31
            // included", so even the two read-only modes have a button under
            // the rule.
            Divider()
                .padding(.top, 10)
            HStack(spacing: 10) {
                // §S1: "the hub is the place people arrive back at when the
                // work is done", so the way out is here and not only in the
                // menu. The app's one way out, shared with §6.2's refusals,
                // so a change to what quitting means happens in one place.
                // No second ⌘Q: the menu item already carries it, and this
                // is the same `terminate` it sends.
                QuitButton()
                Spacer(minLength: 0)
                if offersRestore {
                    Button("Restore…") { hub.perform(hub.restoreAction) }
                }
                // R23 and R31 remove the primary rather than disabling it
                // (§1.3 rule 5: a disabled button is still an invitation).
                // §S1: `Set Up Port…`, the Port menu's ⌘N's own title, so the
                // two can never name one command two ways.
                if let primary = footer.primary {
                    Button(primary.title) { hub.perform(primary) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!footer.isPrimaryEnabled)
                }
            }
            .padding(.top, 10)
        }
        .animation(.smooth(duration: 0.18), value: footer)
    }

    /// §S1's `.caption` link row, directly under the list, drawn as every
    /// other inline action in the column is — in the user's accent, not the
    /// system's link blue — so every clickable word here is one color
    /// (§2.3 band 3). A link drawn gray is a label nobody clicks.
    private var linkRow: some View {
        HStack(spacing: 14) {
            Button("Change Log") { hub.perform(.changeLog) }
                .inlineAction()
            Button("What This All Means") { router.sheet = .whatThisAllMeans }
                .inlineAction()
            Spacer(minLength: 0)
        }
        .font(.caption)
    }
}

/// §2.3 band 4 for a screen that holds the working area on its own — §S8 and
/// §S11 — while the hub's footer steps aside: a separator, then the screen's
/// own buttons trailing, its default last. The same rule and the same place
/// as the assistant's footer (`WizardFooter`), so the default is always
/// bottom-trailing and there is only ever one.
struct ScreenFooter<Buttons: View>: View {
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                buttons
            }
            .padding(.top, 10)
        }
    }
}
