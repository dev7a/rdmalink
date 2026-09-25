//
//  PortPresentation.swift
//
//  Every string and symbol a port row draws, derived from one `PortSnapshot`.
//  Pure, value-typed and free of SwiftUI layout, so the row view stays a
//  renderer and the copy stays checkable against docs/UX_SPEC.md §S1 and §3.3.
//

import Foundation
import RDMALinkCore

/// How a row's symbol is tinted. UX_SPEC §3.3 names four treatments and no
/// more; nothing here ever reaches the 3D model, where no colour carries
/// meaning at all (§3.1).
enum PortSymbolStyle: Sendable, Equatable {
    case secondary
    /// USB-only receptacles and other quiet rows.
    case tertiary
    /// The user's system accent: a port that is ready.
    case accent
    /// `.orange`, in the panel only: a port that needs a look.
    case attention
}

/// The detail line under a row title.
///
/// `address` is split out of `state` rather than interpolated into it because
/// UX_SPEC §3.2 gives the `fe80::` address its own style — `.body.monospaced()`,
/// selectable — and §8.5 forbids ever truncating it. The middle dot between
/// them is drawn by the row.
struct PortRowDetail: Sendable, Equatable {
    var state: LocalizedStringResource
    /// §S1's link-state subtitle, appended after a middle dot when `state`
    /// is something else: a port RDMALink returned to the bridge keeps it.
    var link: LocalizedStringResource?
    /// Appended after a middle dot on a port that has no setup of its own.
    var membership: LocalizedStringResource?
    /// `fe80::a2d1:73b4:9e0c:5f16%en6`, scope suffix included.
    var address: String?

    /// The whole detail line as one string, joined with the same middle dots
    /// the row draws — "Nothing plugged in · In the Thunderbolt Bridge" — for
    /// the places that quote the row without the row's typography: §4.8's
    /// receptacle callout. The address goes on the end exactly as the row
    /// puts it.
    var line: String {
        var parts = [String(localized: state)]
        parts.append(contentsOf: [link, membership].compactMap { $0 }.map { String(localized: $0) })
        if let address { parts.append(address) }
        return parts.joined(separator: " · ")
    }
}

/// UX_SPEC §4.8's receptacle callout: "the row's title and detail line,
/// verbatim — and, when technical names are on, the row's technical line
/// too." Built from the row's own presentation, so the words cannot differ
/// from the list's; a USB-only receptacle's detail is the row's own subtitle,
/// **USB only — this one isn't Thunderbolt**, because that is what the row
/// says.
struct StageCalloutText: Sendable, Equatable {
    /// The position name (§4.7).
    var title: String
    /// `PortRowDetail.line`.
    var detail: String
    /// `en6 · bridge0 · Thunderbolt Bridge`, only while Show Technical Names
    /// is on, and only when the row has one.
    var technical: String?

    init(presentation: PortRowPresentation, showsTechnicalNames: Bool) {
        self.init(
            title: presentation.positionName,
            detail: presentation.detail.line,
            technical: showsTechnicalNames ? presentation.technicalSuffix : nil
        )
    }

    init(title: String, detail: String, technical: String?) {
        self.title = title
        self.detail = detail
        self.technical = technical
    }
}

/// Which screen is drawing the row.
///
/// UX_SPEC §S1 and §S4 ask two different things of the same row. On the hub it
/// is **status**: what this port is, with §S1's trailing buttons beside it. On
/// S4 it is a **picker**, where "every row is a selection target;
/// non-selectable rows are dimmed with an explanatory subtitle" — so a row
/// that cannot be chosen says why instead of what it is, and carries no button
/// offering a different journey mid-choice.
///
/// One mode for the whole list rather than a decision per row: which screen is
/// up is the only thing that changes, and §2.3 band 3's promise that the list
/// "never reorders and never resizes a row" is easier to keep when the
/// difference between the two is one switch.
enum PortRowMode: Sendable, Equatable {
    case status
    case picker

    /// Which screen this is, worked out once: the picker is S4 and nothing
    /// else. S4b is S4 still choosing, so its list is the picker's too, and
    /// the hub (`nil`), the review, the apply and the payoff are all status —
    /// "the list and the model are status there, not a picker" (§S4).
    ///
    /// The list asks this, and so does ``StageInput``: §4.8's callout quotes
    /// "the row's title and detail line, verbatim", so both have to be reading
    /// the same row (§2.4, §8.2).
    init(step: WizardStep?) {
        self = step == .choose ? .picker : .status
    }
}

struct PortRowPresentation: Sendable, Equatable, Identifiable {
    let id: String
    /// SF Symbol from UX_SPEC §3.3.
    let symbol: String
    let symbolStyle: PortSymbolStyle
    /// The physical position name, already localized by Core (§4.7).
    let positionName: String
    let detail: PortRowDetail
    /// Interface, bridge and service names, shown only with "Show technical
    /// names" on (§1.3 rule 6).
    let technicalSuffix: String?
    let accessibilityLabel: String
    /// VoiceOver reads the address as the element's value, not its label (§8.2).
    let accessibilityValue: String?
    /// §S1's trailing buttons, in the order the row draws them.
    let actions: [HubAction]
    /// §2.3's compact density is "symbol, title, and a short trailing badge
    /// only". §S7 names the badge for a port that is ready — **Ready** — and
    /// §S5 names the one the review screen adds; no other state has a badge in
    /// the spec, so no other state is given one here.
    /// **Owed from the spec owner:** the compact badge for the remaining rows.
    let compactBadge: LocalizedStringResource?
    /// §S4: this row cannot be chosen on the picker, so it is drawn at the
    /// same 45 % a USB-only row is. False everywhere else — a row that is
    /// status is never dimmed for being status.
    let isDimmed: Bool

    init(snapshot: PortSnapshot, mode: PortRowMode = .status) {
        // §S4 "Layout": "non-selectable rows are dimmed with an explanatory
        // subtitle". Non-selectable is exactly what `ChoosePortReport` already
        // decides for the screen and the model, so the row asks it rather than
        // working the states out a second time and drifting from it.
        let route = mode == .picker ? ChoosePortReport.route(for: snapshot) : nil
        let port = snapshot.port
        let detail = Self.detail(for: snapshot, dimmedBy: route)
        self.id = port.id
        self.symbol = Self.symbol(for: snapshot)
        self.symbolStyle = Self.symbolStyle(for: snapshot)
        self.positionName = port.positionName
        self.detail = detail
        self.technicalSuffix = Self.technicalSuffix(for: snapshot)
        self.accessibilityLabel = Self.accessibilityLabel(for: snapshot, detail: detail)
        self.accessibilityValue = detail.address
        // §S4: a row the picker lets you choose carries no button — choosing
        // it is the action, and the hub's `Set Up…` or `Set Up Again…`
        // would be a second way into the run already under way.
        self.actions = mode == .picker && route == nil
            ? [] : Self.actions(for: snapshot, dimmedBy: route)
        self.compactBadge = snapshot.readiness.isReady ? "Ready" : nil
        self.isDimmed = route != nil
    }

    /// §S1's "Trailing buttons, by state", with §7.5's addition: any port that
    /// is out of the bridge carries `Return to Bridge…`, "so putting a port
    /// back never depends on how it was removed".
    ///
    /// A port RDMALink set up is the one exception, and deliberately: its
    /// `Restore…` is the same journey with the destination the note remembers,
    /// and offering both would be two buttons for one thing (§1.3 rule 5).
    /// A drifted port has nothing to put back — its note describes a world
    /// that moved — so it is offered the way forward instead, unless it has
    /// a service of its own (§S1): set-up routes a near match to Adopt and
    /// never plans it, and refuses a fixed IPv4 address (R16), so the row
    /// offers what the picker would name for it — `Restore…` for RDMALink's
    /// own service edited since, which raises R28 and says what changed,
    /// `Adopt…` for a new near match made by hand, and nothing where neither
    /// can take it. A port that needs a hand offers `Restore…` and never a
    /// set-up.
    ///
    /// On §S4's picker a dimmed row keeps the route §S4 names for it and
    /// nothing else (`ChoosePortReport.namedAction`): `Restore…`, `Return to
    /// Bridge…` or `Adopt…`, the one sheet the picker lets open over the
    /// assistant (§2.6), which is
    /// also exactly what the Port menu offers there (§2.7). A USB-only row
    /// and R16's keep none — the card their click raises is their answer —
    /// and no dimmed row ever carries a set-up button, which would be a
    /// second way into the run already under way (§S4 "Layout").
    private static func actions(
        for snapshot: PortSnapshot, dimmedBy route: ChooseRefusalRoute?
    ) -> [HubAction] {
        let id = snapshot.id
        if let route {
            return ChoosePortReport.namedAction(for: route, snapshot: snapshot).map { [$0] } ?? []
        }
        switch snapshot.readiness {
        case .managed: return [.restore(portID: id)]
        case .adopted: return [.returnToBridge(portID: id), .stopManaging(portID: id)]
        case .setUpElsewhere: return [.adopt(portID: id), .returnToBridge(portID: id)]
        case .needsAHand: return [.restore(portID: id)]
        case .drifted:
            switch ChoosePortReport.route(for: snapshot) {
            case nil: return [.setUpAgain(portID: id)]
            case .editedService?: return [.restore(portID: id)]
            case .adopt?: return [.adopt(portID: id)]
            // A service RDMALink didn't make that neither Adopt nor set-up
            // can take — a fixed IPv4 address, or a service of its own on a
            // port back in a bridge (§S1, R16): the row offers nothing, and
            // the drift row keeps only `Stop Managing…`. A port set-up can't
            // take is never offered a set-up control (§S4).
            default: return []
            }
        // §4.3 and §S1 give the returned row one button. Its note is cleared
        // with the Port menu's `Stop Managing…` (§7.5 step 5), which the
        // model offers for this state too.
        case .returned: return [.setUpAgain(portID: id)]
        case .plain:
            // §S1: a port that has never been set up carries `Set Up…`, first,
            // so every port that can be set up visibly can be. §S9's near
            // match is reached from the row's `Adopt…` — the sheet is where it
            // says it cannot adopt this one *yet*, and what to change so it
            // can — but only where the sheet has a form for it: a service of
            // its own on a port still in a bridge has none (§S9, R16), and a
            // button that could only close again is not drawn. A port that is
            // out of every bridge can always be put back (§7.5), whoever took
            // it out and whether it was given a service or left bare — §S10
            // has a form for each.
            var actions: [HubAction] = []
            if offersSetUp(snapshot) { actions.append(.setUpPort(portID: id)) }
            if case .nearMatch? = snapshot.configuration, AdoptForm(snapshot) != nil {
                actions.append(.adopt(portID: id))
            }
            if snapshot.isOutOfEveryBridge { actions.append(.returnToBridge(portID: id)) }
            return actions
        }
    }

    /// Whether set-up can take this port — for a port with nothing to say
    /// about it (`.plain`), §S1's "a Thunderbolt port with no setup and no
    /// service of its own", which the row offers `Set Up…`. The stage's
    /// double-click asks the same question (`RootView.doubleClickSetUp`), so
    /// the row and the receptacle agree on which port is "configurable" (§S1),
    /// and so does the footer's `Set Up Port…` before it chooses the hub's
    /// selection for the picker (`SetUpFlow.open(_:)`).
    ///
    /// It is the picker's own test: a USB-only receptacle, a ready port, a
    /// port that needs a hand, a service of the port's own — R16's static
    /// address, or a near match Core would route to Adopt and never plan —
    /// are routes, never set-ups.
    ///
    /// Whether the hub is taking set-ups at all right now — R1, R23, R31 — is
    /// the footer's answer, and the row asks it where it draws the button
    /// (`HubFooterModel.offers(_:)`).
    static func offersSetUp(_ snapshot: PortSnapshot) -> Bool {
        ChoosePortReport.route(for: snapshot) == nil
    }

    private static func symbol(for snapshot: PortSnapshot) -> String {
        switch snapshot.readiness {
        case .managed: return "checkmark.circle.fill"
        case .adopted: return "checkmark.seal.fill"
        case .setUpElsewhere: return "checkmark.circle"
        case .drifted: return "exclamationmark.circle"
        // §3.3: "Needs putting back by hand — `hand.raised`, `.orange`".
        case .needsAHand: return "hand.raised"
        case .returned: return "arrow.uturn.backward.circle"
        case .plain: break
        }
        guard snapshot.port.isThunderbolt else { return "cable.connector.horizontal" }
        switch snapshot.port.link {
        case .empty: return "circle.dashed"
        case .device: return "cable.connector"
        case .macLinkComingUp: return "bolt.horizontal.circle"
        case .macLinked: return "bolt.horizontal.circle.fill"
        }
    }

    private static func symbolStyle(for snapshot: PortSnapshot) -> PortSymbolStyle {
        switch snapshot.readiness {
        case .managed, .adopted: .accent
        case .setUpElsewhere, .returned: .secondary
        case .drifted, .needsAHand: .attention
        case .plain: snapshot.port.isThunderbolt ? .secondary : .tertiary
        }
    }

    /// §S1's subtitle, or — on §S4's picker, for a row that cannot be chosen
    /// — the "explanatory subtitle" §S4 gives it instead: **USB only — this
    /// one isn't Thunderbolt** · **Already ready for RDMA** · **Set up
    /// outside RDMALink**. It is one sentence and no more: the address, the
    /// bridge membership and the middle dots belong to the row that is
    /// status, and a picker row's job is to say why the click will not land.
    ///
    /// A route §S4 has no sentence for keeps the hub's subtitle rather than
    /// being given a new one here (`dimmedSubtitle` returns nil for it), and
    /// the row is still dimmed — which is the honest half of the pair.
    private static func detail(
        for snapshot: PortSnapshot, dimmedBy route: ChooseRefusalRoute?
    ) -> PortRowDetail {
        if let route, let subtitle = ChoosePortReport.dimmedSubtitle(for: route) {
            return PortRowDetail(state: subtitle)
        }
        switch snapshot.readiness {
        case .managed:
            guard let address = snapshot.linkLocalAddress else {
                return PortRowDetail(
                    state: "Ready for RDMA · the address appears when a Mac arrives"
                )
            }
            return PortRowDetail(state: "Ready for RDMA", address: address)
        case .adopted:
            return PortRowDetail(state: "Ready for RDMA · set up by you, looked after by RDMALink")
        case .setUpElsewhere:
            return PortRowDetail(state: "Set up outside RDMALink")
        case .drifted:
            return PortRowDetail(state: "Not set up any more")
        case .needsAHand:
            return PortRowDetail(state: "Needs putting back by hand")
        case .returned:
            // §S1: "the link-state subtitle and the membership phrase stay".
            return PortRowDetail(
                state: "Returned by RDMALink",
                link: linkState(of: snapshot.port),
                membership: membership(of: snapshot)
            )
        case .plain:
            return PortRowDetail(
                state: linkState(of: snapshot.port),
                membership: membership(of: snapshot)
            )
        }
    }

    private static func linkState(of port: ThunderboltPort) -> LocalizedStringResource {
        guard port.isThunderbolt else { return "USB only — this one isn't Thunderbolt" }
        switch port.link {
        case .empty: return "Nothing plugged in"
        case .device: return "A device is connected — not a Mac"
        case .macLinkComingUp: return "Another Mac is here. The link is still coming up."
        case .macLinked: return "Linked to another Mac"
        }
    }

    /// §S1's three membership phrases, and only those three.
    ///
    /// "In two bridges, including one that isn't in use" is printed exactly
    /// when it is true — two bridges, one of them down — because
    /// `BridgeMembership.isUp` is observed. Every other shape (three bridges,
    /// or two that are both up) has no sentence in the spec, and the phrase is
    /// left off rather than minted here; the row still states the port's state,
    /// and **the missing strings are owed from the spec owner**.
    private static func membership(of snapshot: PortSnapshot) -> LocalizedStringResource? {
        guard snapshot.port.isThunderbolt else { return nil }
        let bridges = snapshot.bridges
        switch bridges.count {
        case 0: return "Not in any bridge"
        case 1: return "In the Thunderbolt Bridge"
        case 2 where bridges.count(where: { !$0.isUp }) == 1:
            return "In two bridges, including one that isn't in use"
        default:
            return nil
        }
    }

    /// `en6 · bridge0 · Thunderbolt Bridge` — the interface, bridge and service
    /// names §S12's help text promises, in that order, and nothing else.
    private static func technicalSuffix(for snapshot: PortSnapshot) -> String? {
        var parts: [String] = []
        // A USB-only receptacle has no interface name, and an empty suffix is
        // worse than none at all.
        if !snapshot.port.bsdName.isEmpty { parts.append(snapshot.port.bsdName) }
        parts.append(contentsOf: snapshot.bridges.map(\.name))
        if let serviceName = snapshot.serviceName, !serviceName.isEmpty {
            parts.append(serviceName)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func accessibilityLabel(
        for snapshot: PortSnapshot,
        detail: PortRowDetail
    ) -> String {
        let state = String(localized: detail.state)
        let kind: String.LocalizationValue = snapshot.port.isThunderbolt
            ? "\(snapshot.port.positionName). Thunderbolt port. \(state)."
            : "\(snapshot.port.positionName). USB port. \(state)."
        var label = String(localized: kind)
        for phrase in [detail.link, detail.membership].compactMap({ $0 }) {
            let joined: String.LocalizationValue = "\(label) \(String(localized: phrase))."
            label = String(localized: joined)
        }
        return label
    }
}

/// One face of the Mac and the receptacles on it, in physical order.
struct PortGroup: Sendable, Equatable, Identifiable {
    let id: String
    let header: LocalizedStringResource
    let ports: [PortSnapshot]
}

enum PortGrouping {
    /// Groups by face without reordering: faces come out in the order their
    /// first port appears, and ports keep the order Core reported (§2.3).
    static func groups(for ports: [PortSnapshot]) -> [PortGroup] {
        var order: [PortFace?] = []
        var buckets: [PortFace?: [PortSnapshot]] = [:]
        for port in ports {
            if buckets[port.port.face] == nil { order.append(port.port.face) }
            buckets[port.port.face, default: []].append(port)
        }
        return order.map { face in
            PortGroup(
                id: face?.rawValue ?? "unspecified",
                header: header(for: face),
                ports: buckets[face] ?? []
            )
        }
    }

    private static func header(for face: PortFace?) -> LocalizedStringResource {
        switch face {
        case .back: "Back"
        case .front: "Front"
        case .left: "Left side"
        case .right: "Right side"
        case nil: "Thunderbolt ports"
        }
    }
}
