//
//  ChangeLogView.swift
//
//  S11 — an always-available, timestamped, plain-English, append-only record
//  of everything RDMALink has done to this Mac, each with its own way back.
//
//  It replaces the working area rather than opening a sheet, so the port list
//  and the model stay beside it: hovering an entry lights the receptacle it
//  refers to, and history becomes spatial. An entry whose port is not on this
//  Mac any more lights nothing and says so, rather than leaving you hunting.
//
//  Nothing here edits an entry. An entry that has been undone is answered by a
//  later entry, never by rewriting the old one.
//
//  Its buttons are band 4's while it is up (`ChangeLogFooter`): the hub's
//  footer and link row step aside, so the window has one button row and one
//  default (§2.3 band 4).
//

import SwiftUI
import RDMALinkCore

struct ChangeLogView: View {
    let hub: HubActionsModel
    /// §S11: "Hovering a log entry lights the receptacle it refers to."
    let stage: StageModel
    let model: InventoryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let rows = ChangeLogRows.rows(
                entries: hub.log, ports: hub.ports, noted: hub.noted)
            // §S11: a headline and one body line, like every other screen —
            // where the notes live, or the empty sentence in its place.
            VStack(alignment: .leading, spacing: 8) {
                Text(ChangeLogRows.headline)
                    .font(.title2.weight(.semibold))
                Text(ChangeLogRows.body(isEmpty: rows.isEmpty))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !rows.isEmpty {
                ScrollView {
                    GroupedSection {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { RowDivider() }
                            ChangeLogEntryRow(row: row, hub: hub, stage: stage)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await hub.reloadLog() }
        .onDisappear { stage.hover(nil) }
    }
}

/// §S11's buttons, in band 4 while the log holds the working area:
/// `Show Notes in Finder` · `Save Diagnostics File…` · `Done`, `Done` the
/// default and trailing, the others just before it (§2.3 band 4).
struct ChangeLogFooter: View {
    let hub: HubActionsModel

    var body: some View {
        ScreenFooter {
            Button("Show Notes in Finder") { WizardFinder.showNotesFolder() }
            Button("Save Diagnostics File…") { DiagnosticsFile.save() }
            Button("Done") { hub.closeChangeLog() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}

struct ChangeLogEntryRow: View {
    let row: ChangeLogRow
    let hub: HubActionsModel
    let stage: StageModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.head)
                    .font(.callout.weight(.medium))
                Text(row.sentence)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = row.note {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // §6.2 R31: "the change log still work[s]" — as a record. Its
            // way back for each entry writes, so on a Mac RDMALink does not
            // recognize the entries are read and the buttons are absent.
            // §S1: an entry's set-up button is the port row's own, on the
            // footer's terms — absent where the footer offers no set-up (R23),
            // disabled while two Macs are connected (R1) — and it reads as
            // the row's does.
            if let action = row.action, !hub.isUnrecognized, hub.footer.offers(action) {
                Button(action.rowTitle) { hub.perform(action) }
                    .inlineAction()
                    .disabled(!hub.footer.allows(action))
            }
        }
        // §S11: undone entries stay, greyed, with the action replaced by a note.
        .opacity(row.isDimmed ? 0.55 : 1)
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .contentShape(.rect)
        .onHover { isInside in
            // An entry for a port that is not here any more produces no
            // highlight, and the row has already said why.
            stage.hover(isInside ? row.portID : nil)
        }
    }
}
