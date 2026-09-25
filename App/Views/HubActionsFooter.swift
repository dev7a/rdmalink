//
//  HubActionsFooter.swift
//
//  Band 4 of the assistant column on the hub: §S1's link row under the port
//  list, the reason the primary is unavailable when it is, and the button row
//  itself — `Quit` at the leading edge, then `Set Up Port…` as the default
//  with `Restore…` beside it whenever a note exists (§S1, §2.3, §2.8).
//

import SwiftUI

struct HubActionsFooter: View {
    let footer: HubFooterModel
    let hub: HubActionsModel
    let router: HubRouter
    /// Whether the primary is the window's default. Not while §S11 or §S8
    /// holds the working area: that screen's `Done` is then the one default,
    /// and the primary stays here as a plain button (§S1), so Return never
    /// has two buttons to choose between.
    var primaryIsDefault = true

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
                if let primary = footer.primary {
                    let button = Button(footer.primaryTitle) { hub.perform(primary) }
                        .disabled(!footer.isPrimaryEnabled)
                    if primaryIsDefault {
                        button
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    } else {
                        button
                    }
                }
            }
            .padding(.top, 10)
        }
        .animation(.smooth(duration: 0.18), value: footer)
    }

    /// §S1's `.caption` link row, directly under the list, in the link color
    /// `.link` gives it — a link drawn gray is a label nobody clicks.
    private var linkRow: some View {
        HStack(spacing: 14) {
            Button("Change Log") { hub.perform(.changeLog) }
            Button("What This All Means") { router.sheet = .whatThisAllMeans }
            Spacer(minLength: 0)
        }
        .buttonStyle(.link)
        .font(.caption)
    }
}
