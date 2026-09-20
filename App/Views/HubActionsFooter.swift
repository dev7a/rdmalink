//
//  HubActionsFooter.swift
//
//  Band 4 of the assistant column on the hub: §S1's link row under the port
//  list, the reason the primary is unavailable when it is, and the button row
//  itself — `Set Up a Port…` as the default, with `Restore…` beside it
//  whenever a note exists (§S1, §2.3, §2.8).
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
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
            Divider()
                .padding(.top, 10)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                // §2.8: "Restore is never hidden." Whenever any note exists it
                // is here, so nobody has to find a row first.
                if hub.hasAnyNote {
                    Button("Restore…") { hub.perform(hub.restoreAction) }
                }
                // R23 removes the primary rather than disabling it (§6.1
                // rule 5: a disabled control is still an invitation).
                if let primary = footer.primary {
                    Button(footer.primaryTitle) { hub.perform(primary) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!footer.isPrimaryEnabled)
                }
            }
            .padding(.top, 10)
        }
        .animation(.smooth(duration: 0.18), value: footer)
    }

    /// §S1's `.caption` secondary link row, directly under the list.
    private var linkRow: some View {
        HStack(spacing: 14) {
            Button("Change Log") { hub.perform(.changeLog) }
            Button("What This All Means") { router.sheet = .whatThisAllMeans }
            Spacer(minLength: 0)
        }
        .buttonStyle(.link)
        .foregroundStyle(.secondary)
        .font(.caption)
    }
}
