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

import AppKit
import SwiftUI
import RDMALinkCore

struct ChangeLogView: View {
    let hub: HubActionsModel
    /// §S11: "Hovering a log entry lights the receptacle it refers to."
    let stage: StageModel
    let model: InventoryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What RDMALink has changed on this Mac")
                .font(.title2.weight(.semibold))
            let rows = ChangeLogRows.rows(
                entries: hub.log, ports: hub.ports, noted: hub.noted)
            if rows.isEmpty {
                Text("Nothing yet. When RDMALink changes something, it'll be listed here with a way back.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
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
            Text("RDMALink keeps one small note per port, in your Library folder. They're only notes — they don't change anything on their own.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Show the Notes in Finder") { WizardFinder.showNotesFolder() }
                SaveDiagnosticsButton()
                Spacer(minLength: 0)
                Button("Done") { hub.closeChangeLog() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await hub.reloadLog() }
        .onDisappear { stage.hover(nil) }
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
            if let action = row.action {
                Button(action.title) { hub.perform(action) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
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

/// §S11's and §S12's `Save a Diagnostics File…`, on the payload §6.1 rule 8
/// shares with every `Copy Details`.
struct SaveDiagnosticsButton: View {
    var body: some View {
        Button("Save a Diagnostics File…") {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = Diagnostics.suggestedFileName()
            panel.allowedContentTypes = [.plainText]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            Task {
                let text = await Task.detached(priority: .userInitiated) {
                    Diagnostics.live()
                }.value
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

/// One line of §S11, ready to draw.
struct ChangeLogRow: Sendable, Equatable, Identifiable {
    var id: UUID
    /// `3 September, 14:21 — Back, far left`.
    var head: String
    /// The sentence as it was written at the time. The record is kept, never
    /// rewritten.
    var sentence: String
    /// What happened to it since, when something did.
    var note: LocalizedStringResource?
    var action: HubAction?
    /// The receptacle to light on hover, or `nil` when the port has gone.
    var portID: String?
    var isDimmed: Bool
}

enum ChangeLogRows {
    /// Newest first, each entry answered by whatever happened to it later.
    static func rows(
        entries: [ChangeEntry], ports: [PortSnapshot], noted: Set<String>
    ) -> [ChangeLogRow] {
        // §S11 lists entry sentences for set-up and adopt, and writes "Already
        // put back on…" only as the **note** an undone entry carries. A
        // restore, a stop and a forget are each already shown as that note on
        // the entry they answer, so drawing them again as rows of their own
        // would print one moment twice — the second time as a row that repeats
        // its own timestamp and has no action. The entries stay in the file:
        // the log is append-only and `laterAnswer` matches on them.
        // **Owed from the spec owner:** an entry sentence of their own, if
        // they are meant to be rows.
        entries.filter { $0.kind == .setUp || $0.kind == .adopted }.map { entry in
            let port = ports.first { $0.port.bsdName == entry.port }
            let head: String.LocalizationValue =
                "\(Moments.dayAndTime(entry.date)) — \(entry.positionName)"
            let later = laterAnswer(to: entry, in: entries)
            return ChangeLogRow(
                id: entry.id,
                head: String(localized: head),
                sentence: entry.sentence,
                note: note(for: entry, answeredBy: later, portIsHere: port != nil),
                action: action(for: entry, answeredBy: later, port: port, noted: noted),
                portID: port?.id,
                isDimmed: later != nil)
        }
    }

    /// The later entry that answers this one — a restore, a stop, or a note
    /// cleared. Only entries that *did* something are answered.
    private static func laterAnswer(to entry: ChangeEntry, in entries: [ChangeEntry])
        -> ChangeEntry?
    {
        guard entry.kind == .setUp || entry.kind == .adopted else { return nil }
        return entries.first {
            $0.port == entry.port && $0.date > entry.date
                && ($0.kind == .restored || $0.kind == .stoppedManaging || $0.kind == .forgotten)
        }
    }

    private static func note(
        for entry: ChangeEntry, answeredBy later: ChangeEntry?, portIsHere: Bool
    ) -> LocalizedStringResource? {
        if let later {
            let moment = Moments.dayAtTime(later.date)
            return later.kind == .restored
                ? LocalizedStringResource(core: ChangeSentence.alreadyPutBack(moment: moment))
                : LocalizedStringResource(
                    core: ChangeSentence.stoppedLookingAfter(moment: moment))
        }
        guard !portIsHere, entry.kind == .setUp || entry.kind == .adopted else { return nil }
        return LocalizedStringResource(core: ChangeSentence.portIsGone)
    }

    private static func action(
        for entry: ChangeEntry,
        answeredBy later: ChangeEntry?,
        port: PortSnapshot?,
        noted: Set<String>
    ) -> HubAction? {
        guard later == nil else { return nil }
        guard let port else {
            // §S11: the note for a port that has gone stays until it is
            // cleared, and clearing it is the only thing left to offer.
            return noted.contains(entry.port) ? .forgetThisNote(port: entry.port) : nil
        }
        guard port.baseline != nil else { return nil }
        switch entry.kind {
        case .setUp: return .restore(portID: port.id)
        case .adopted: return .stopManaging(portID: port.id)
        case .restored, .stoppedManaging, .forgotten: return nil
        }
    }
}
