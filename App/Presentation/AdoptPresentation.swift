//
//  AdoptPresentation.swift
//
//  Which of §S9's forms a port is in, and the words each form says. Pure —
//  Foundation and RDMALinkCore only — so the hub's model, which asks the same
//  question before it offers `Adopt…`, compiles in script/test_presentation.sh
//  alongside it. The sheet itself is App/Views/AdoptSheet.swift.
//

import Foundation
import RDMALinkCore

/// Which of §S9's two forms a port is in. A port that is not a match at all is
/// neither, and is never offered this sheet.
enum AdoptForm: Sendable, Equatable {
    /// `replacing` is the note adopting replaces, which the honesty note owns
    /// up to (§S9): RDMALink's from setting the port up before — §S1's
    /// drifted port, the service RDMALink made gone and this one made by
    /// hand — or a return record whose port has moved on (§7.5 step 5).
    /// `nil` when there is no note at all.
    case fullMatch(replacing: PortBaseline?)
    case nearMatch([ConfigurationDifference])

    init?(_ port: PortSnapshot) {
        switch port.configuration {
        case .readyForRDMA?:
            // §S9's full match over the note RDMALink kept from setting the
            // port up, whose service is gone: adopting looks after the one
            // made by hand and replaces that note, and the honesty note says
            // so. Core's `AdoptPort.preview` makes the same call.
            if port.hasRDMALinksServiceReplacedByAMatch {
                self = .fullMatch(replacing: port.baseline)
                return
            }
            // Any other port RDMALink already looks after has nothing to
            // adopt. A return record is not that: its port has left the
            // bridge and been given a matching service since, so the record
            // describes nothing current, and adopting replaces it with the
            // adopted note (the same replacement §7.5 step 5 describes for
            // set-up) — which the honesty note owns up to, since RDMALink did
            // see this port before.
            guard port.baseline?.isReturned != false else { return nil }
            self = .fullMatch(replacing: port.baseline)
        case .nearMatch(_, let differences)?:
            // §7.3: Adopt is for a port that is "out of every bridge, its own
            // service". A port still in a bridge is not that case, and §S9's
            // near-match body opens by saying it is — so it is not offered
            // this sheet rather than shown a sentence that contradicts itself.
            // Nor is the service RDMALink made, edited by hand since: it is
            // RDMALink's own, `Restore…` answers for it (R28), and the body's
            // "RDMALink didn't make this service" would be false (§S1).
            // Core's `AdoptPort.preview` makes the same calls.
            guard !differences.contains(where: \.isBridgeMembership),
                !port.hasRDMALinksOwnServiceEdited,
                AdoptFindings.clause(for: differences) != nil
            else { return nil }
            self = .nearMatch(differences)
        case .unconfigured?, .foreign?, nil:
            return nil
        }
    }

    /// The form a sheet showing `current` moves to when the port changes
    /// under it, or `nil` to stay as it is (§S9, "The sheet follows the
    /// port").
    ///
    /// A near match put right in System Settings with the sheet still up
    /// becomes the full match, `Adopt` and all — the watcher line's promise,
    /// kept where the user is looking. A port that stops being either form
    /// keeps the one on screen: a near match its steps, which still apply,
    /// and a full match its `Adopt`, because the run reads the port again
    /// and Core adopts only what that reading finds, refusing a port that no
    /// longer matches with nothing written. A reading that fails for a moment
    /// resolves to no form too, and is no change to the port. Nothing moves
    /// once `Adopt` is pressed, because the note it writes makes the port no
    /// form at all and the sheet's answer is what it shows then.
    static func following(_ current: AdoptForm, live: AdoptForm?, adopting: Bool) -> AdoptForm? {
        guard !adopting, let live, live != current else { return nil }
        return live
    }

    /// §S9's honesty note, in Core's words: `AdoptPort.preview` hands the
    /// command-line tool the same one. `nil` on a near match, which has none.
    var honestyNote: LocalizedStringResource? {
        guard case .fullMatch(let replaced) = self else { return nil }
        return LocalizedStringResource(core: AdoptPort.honestyNote(replacing: replaced))
    }

    /// Whether `Adopt` is the sheet's default. It is not when adopting forgets
    /// the only record of the bridges the port came from — the old note
    /// records them — so `Cancel` takes the trailing slot and Return presses
    /// nothing (§2.6, §S9), as in the stop-managing form for the same note.
    var adoptIsDefault: Bool {
        guard case .fullMatch(let replaced) = self else { return false }
        return !AdoptPort.forgetsTheWayBack(replacing: replaced)
    }

    var headline: LocalizedStringResource {
        switch self {
        case .fullMatch: "This port is already set up"
        case .nearMatch: "Nearly a match"
        }
    }

    func body(_ port: PortSnapshot) -> LocalizedStringResource {
        let name = port.port.positionName
        switch self {
        case .fullMatch:
            return "\(name) isn't in any bridge and already has its own service with IPv4 off and IPv6 link-local only. That's exactly what RDMALink would have made. Adopt it and RDMALink will keep an eye on it — without changing a thing."
        case .nearMatch(let differences):
            let clause = AdoptFindings.clause(for: differences) ?? ""
            return "\(name) is out of every bridge and has its own service, but \(clause). RDMALink didn't make this service, so it won't rewrite it — but here's exactly what to change, and RDMALink adopts the port the moment it matches."
        }
    }
}

/// §S9's four findings rows, its steps, and the one clause its near-match body
/// names the difference in.
enum AdoptFindings {
    /// **Service — Thunderbolt Bridge Free** · **IPv4 — Off** ·
    /// **IPv6 — Link-local only** · **Bridge membership — None**.
    static func rows(_ port: PortSnapshot) -> [LocalizedStringResource] {
        [
            "Service — \(port.serviceName ?? port.port.bsdName)",
            "IPv4 — Off",
            "IPv6 — Link-local only",
            "Bridge membership — None",
        ]
    }

    static func steps(_ port: PortSnapshot) -> LocalizedStringResource {
        "In System Settings, open Network, choose \(port.serviceName ?? port.port.bsdName), then Details, then TCP/IP. Set Configure IPv6 to Link-local only. Set Configure IPv4 to Off."
    }

    /// §S9 writes the near-match body for one difference — IPv6 set to
    /// Automatic — and the sentence it writes has a shape the other
    /// differences fit: *"\<what\> is set to \<this\> rather than \<that\>"*.
    /// The clauses are Core's, so the sheet and `AdoptPort.preview` can never
    /// name the difference two different ways.
    ///
    /// Bridge membership is never one of them: the body's own first clause
    /// says the port is out of every bridge (§1.3 rule 10).
    /// **Owed from the spec owner:** the near-match body for each of them.
    static func clause(for differences: [ConfigurationDifference]) -> String? {
        ConfigurationDifference.serviceClause(in: differences)
    }
}
