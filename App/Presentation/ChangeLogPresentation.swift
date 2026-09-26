//
//  ChangeLogPresentation.swift
//
//  §S11's rows as values: each entry's head, its sentence, what happened to it
//  since, and the one action it offers. Pure — Foundation and RDMALinkCore
//  only — so script/test_presentation.sh can hold the log to the row's terms
//  (§S1: an entry's set-up button is the port row's own). The view is
//  App/Views/ChangeLogView.swift.
//

import Foundation
import RDMALinkCore

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
    static let headline: LocalizedStringResource = "What RDMALink has changed on this Mac"

    /// §S11's body line: where the notes live — or, with nothing listed
    /// yet, the empty sentence in its place.
    static func body(isEmpty: Bool) -> LocalizedStringResource {
        isEmpty
            ? "Nothing yet. When RDMALink changes something, it'll be listed here with a way back."
            : "RDMALink keeps one small note per port, in your Library folder. They're only notes — they don't change anything on their own."
    }

    /// Newest first, each entry answered by whatever happened to it later.
    static func rows(
        entries: [ChangeEntry], ports: [PortSnapshot], noted: Set<String>
    ) -> [ChangeLogRow] {
        // §S11 lists entry sentences for set-up, adopt and a return to the
        // bridge, and writes "Already put back on…" and its kin only as the
        // **note** an answered entry carries. A restore, a stop and a forget
        // are each already shown as that note on the entry they answer, so
        // drawing them again as rows of their own would print one moment
        // twice — the second time as a row that repeats its own timestamp and
        // has no action. The entries stay in the file: the log is append-only
        // and `ChangeLog.answer` matches on them. **Owed from the spec
        // owner:** an entry sentence of their own, if they are meant to be
        // rows.
        entries.filter { isARow($0.kind) }.map { entry in
            let port = ports.first { $0.port.bsdName == entry.port }
            let head: String.LocalizationValue =
                "\(Moments.dayAndTime(entry.date)) — \(entry.positionName)"
            // Core decides what answers what and which of §S11's notes that
            // is, so the app and the `rdmalink changes` tool read the same
            // log the same way.
            let later = ChangeLog.answer(to: entry, in: entries)
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

    private static func isARow(_ kind: ChangeKind) -> Bool {
        switch kind {
        case .setUp, .adopted, .returned: true
        case .restored, .stoppedManaging, .forgotten: false
        }
    }

    private static func note(
        for entry: ChangeEntry, answeredBy later: ChangeEntry?, portIsHere: Bool
    ) -> LocalizedStringResource? {
        if let later {
            return LocalizedStringResource(core: ChangeLog.note(for: entry, answeredBy: later))
        }
        guard !portIsHere else { return nil }
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
        switch entry.kind {
        // §S11's returned entry offers `Set Up Again…`, which needs no note
        // — but only as the port's own row offers it (§S1): the same set-up
        // action, or none. A port re-configured by hand since — a near match,
        // a ready setup, R16's static address — is one set-up can't take,
        // and its row offers something else or nothing; the log never offers
        // a Review that would have nothing to press. Whether the hub is
        // taking set-ups at all is the footer's answer, asked where it is
        // drawn.
        case .returned:
            return PortRowPresentation(snapshot: port).actions.first(where: \.opensSetUp)
        case .setUp: return port.baseline != nil ? .restore(portID: port.id) : nil
        case .adopted: return port.baseline != nil ? .stopManaging(portID: port.id) : nil
        case .restored, .stoppedManaging, .forgotten: return nil
        }
    }
}
