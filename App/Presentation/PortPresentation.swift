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
    /// `fe80::1c3d:5aff:fe22:9b04%en6`, scope suffix included.
    var address: String?
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

    init(snapshot: PortSnapshot) {
        let port = snapshot.port
        let detail = Self.detail(for: snapshot)
        self.id = port.id
        self.symbol = Self.symbol(for: snapshot)
        self.symbolStyle = Self.symbolStyle(for: snapshot)
        self.positionName = port.positionName
        self.detail = detail
        self.technicalSuffix = Self.technicalSuffix(for: snapshot)
        self.accessibilityLabel = Self.accessibilityLabel(for: snapshot, detail: detail)
        self.accessibilityValue = detail.address
        self.actions = Self.actions(for: snapshot)
        self.compactBadge = snapshot.readiness.isReady ? "Ready" : nil
    }

    /// §S1's "Trailing buttons, by state", with §7.5's addition: any port that
    /// is out of the bridge carries `Return to Bridge…`, "so putting a port
    /// back never depends on how it was removed".
    ///
    /// A port RDMALink set up is the one exception, and deliberately: its
    /// `Restore…` is the same journey with the destination the note remembers,
    /// and offering both would be two buttons for one thing (§1.3 rule 5).
    /// A drifted port has nothing to put back — its note describes a world
    /// that moved — so it is offered the way forward instead.
    private static func actions(for snapshot: PortSnapshot) -> [HubAction] {
        let id = snapshot.id
        switch snapshot.readiness {
        case .managed: return [.restore(portID: id)]
        case .adopted: return [.returnToBridge(portID: id), .stopManaging(portID: id)]
        case .setUpElsewhere: return [.adopt(portID: id), .returnToBridge(portID: id)]
        case .drifted: return [.setItUpAgain(portID: id)]
        // §4.3 and §S1 give the returned row one button. `Forget This Port`
        // clears its note (§7.5) and lives in the Port menu's `Stop
        // Managing…`, which the model offers for this state too.
        case .returned: return [.setItUpAgain(portID: id)]
        case .plain:
            // §S9's near match is reached from the row's `Adopt…` — the sheet
            // is where it says it cannot adopt this one *yet*, and what to
            // change so it can. A port that is out of every bridge can always
            // be put back (§7.5), whoever took it out and whether it was given
            // a service or left bare — §S10 has a form for each.
            var actions: [HubAction] = []
            if case .nearMatch? = snapshot.configuration { actions.append(.adopt(portID: id)) }
            if snapshot.isOutOfEveryBridge { actions.append(.returnToBridge(portID: id)) }
            return actions
        }
    }

    private static func symbol(for snapshot: PortSnapshot) -> String {
        switch snapshot.readiness {
        case .managed: return "checkmark.circle.fill"
        case .adopted: return "checkmark.seal.fill"
        case .setUpElsewhere: return "checkmark.circle"
        case .drifted: return "exclamationmark.circle"
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
        case .drifted: .attention
        case .plain: snapshot.port.isThunderbolt ? .secondary : .tertiary
        }
    }

    private static func detail(for snapshot: PortSnapshot) -> PortRowDetail {
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
        case .returned:
            // §S1: "the link-state subtitle and the membership phrase stay".
            return PortRowDetail(
                state: "Back in the bridge",
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
