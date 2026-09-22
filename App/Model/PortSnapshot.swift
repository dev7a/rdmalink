//
//  PortSnapshot.swift
//
//  One receptacle and everything the hub knows about it at one moment: what is
//  plugged in (UX_SPEC §4.2's inner track), which kernel bridges it belongs to,
//  what its network configuration is, and whether RDMALink has a note for it
//  (§4.3's outer track).
//
//  Pure values, no SwiftUI. The two tracks are kept apart here exactly as the
//  spec keeps them apart, so nothing in the interface can conflate them.
//

import Foundation
import RDMALinkCore

/// What the configuration says about a port — UX_SPEC §4.3's outer track,
/// reduced to the six answers the hub can actually observe.
enum PortReadiness: Sendable, Equatable {
    /// Nothing to say beyond what is plugged in. Also the honest answer when
    /// the stored network configuration could not be read this time round: the
    /// app states what it observed and no more (§1.3 rule 10).
    case plain
    /// Set up by RDMALink, and still exactly as RDMALink left it.
    case managed
    /// Already set up by hand, then adopted, and still matching.
    case adopted
    /// Exactly what RDMALink would have made, but RDMALink did not make it.
    case setUpElsewhere
    /// RDMALink has a note for this port and the setup it describes is gone.
    case drifted
    /// RDMALink itself put this port back into the Thunderbolt Bridge (§7.5),
    /// its note is still there, and the port still has what the note
    /// describes: it is in that bridge and has no service. Not drift (§4.3),
    /// and never a situation row.
    case returned

    /// True for the ports §S1 counts under "Ports ready for RDMA".
    ///
    /// `.setUpElsewhere` is **not** one of them. §7.3 is explicit that it is
    /// *adopting* that makes a port "appear in the status, the change log and
    /// the address list alongside ports RDMALink set up" — so before Adopt it
    /// must not, and counting it would make the hub print "Nothing else on this
    /// Mac was changed" about a change RDMALink never made (§1.3 rule 10).
    /// §4.3 keeps the two apart by ring geometry for the same reason.
    var isReady: Bool {
        switch self {
        case .managed, .adopted: true
        case .plain, .setUpElsewhere, .drifted, .returned: false
        }
    }

    /// §4.3 and §S9: exactly what RDMALink would have made, made by somebody
    /// else. It is the one state `Adopt…` is offered from.
    var isAdoptable: Bool { self == .setUpElsewhere }
}

/// One receptacle, joined with everything read about it.
struct PortSnapshot: Sendable, Equatable, Identifiable {
    var port: ThunderboltPort
    /// Every kernel bridge this port is a member of, switched on or not.
    var bridges: [ThunderboltPort.BridgeMembership]
    /// What the stored network configuration says, or nil when this read could
    /// not open it. Nil is not "unconfigured"; it is "not observed".
    var configuration: PortConfiguration?
    /// RDMALink's undo note for this port, when there is one.
    var baseline: PortBaseline?

    var id: String { port.id }

    var readiness: PortReadiness {
        guard let configuration else { return .plain }
        let matches: Bool
        if case .readyForRDMA = configuration { matches = true } else { matches = false }
        guard let baseline else { return matches ? .setUpElsewhere : .plain }
        // §7.5 step 5: a return record is not drift. While the port is still
        // in the bridge it was put back into, bare, the row says so. Once it
        // has moved on the record describes nothing current, so it is read
        // as no note at all and what *is* observed decides: an exact match is
        // "Set up outside RDMALink" and can be adopted (§S9 replaces the
        // record with the adopted note), anything else is plain. It never
        // reaches the drift line below.
        if baseline.isReturned {
            let holds = baseline.describesTheReturnedPort(
                bridges: bridges.map(\.name), hasService: hasServiceOfItsOwn)
            if holds { return .returned }
            return matches ? .setUpElsewhere : .plain
        }
        guard matches else { return .drifted }
        return baseline.isAdopted ? .adopted : .managed
    }

    /// The link-local address with its scope suffix, the way UX_SPEC §S1 prints
    /// it: `fe80::a2d1:73b4:9e0c:5f16%en6`. Core stores the address without the
    /// suffix; tools need every character of it, so it is put back here.
    var linkLocalAddress: String? {
        guard let address = port.linkLocal.first else { return nil }
        return "\(address)%\(port.bsdName)"
    }

    /// The name macOS has for this port's service, when it has one. Shown only
    /// with "Show technical names" on (§1.3 rule 6).
    var serviceName: String?

    /// §7.5's subject: a Thunderbolt port that is out of every bridge, as this
    /// reading observed it — with a service of its own or left bare, because
    /// §S10 has a form for each. The row's `Return to Bridge…`, the Port
    /// menu's and the snapshot route all ask this one question, so a port
    /// taken out of the bridge by hand can be put back from the app whether
    /// or not it was given a service. A configuration that could not be read
    /// is not "out of every bridge"; it is not observed (§1.3 rule 10).
    var isOutOfEveryBridge: Bool {
        port.isThunderbolt && configuration != nil && bridges.isEmpty
    }
}

extension Array where Element == PortSnapshot {
    /// The ports §S1's "Ports ready for RDMA" row names, in physical order.
    var ready: [PortSnapshot] { filter { $0.readiness.isReady } }

    /// The ports §S1 offers `Adopt…` on, and the ones its ready row counts as
    /// "set up outside RDMALink".
    var adoptable: [PortSnapshot] { filter { $0.readiness.isAdoptable } }

    /// Ports with an established link to another Mac.
    var withLinkedMac: [PortSnapshot] { filter { $0.port.link == .macLinked } }

    /// Ports with a Mac on the end whether or not the link has finished coming
    /// up. §4.2's inner-track states 3 and 4 both mean "a Mac is here", and the
    /// Ethernet forwarding loop §S13 and R1 warn about is a property of the
    /// cables, not of the link state — so the two-Macs tip counts these.
    var withAMac: [PortSnapshot] {
        filter { $0.port.link == .macLinked || $0.port.link == .macLinkComingUp }
    }

    /// The ports R1 names: those of `withAMac` that share a bridge, so this
    /// Mac could forward between the two cables. Core's rule decides, so the
    /// hub's tip, the footer and S3 agree with every refusal an operation
    /// raises; two cables on two standalone ports — a finished set-up — are
    /// not a loop and come back empty.
    var inALoop: [PortSnapshot] {
        let observed = withAMac.map {
            ObservedPort(bsdName: $0.port.bsdName, positionName: $0.port.positionName,
                         hasLinkedMac: true, bridges: $0.port.bridges.map(\.name),
                         loopedBackTo: $0.port.loopedBackTo)
        }
        let subjects = Set(Refusals.oneCableOnly(observed)?.subjects ?? [])
        return withAMac.filter { subjects.contains($0.port.bsdName) }
    }
}

extension PortSnapshot {
    /// True when the port has a service of its own, whoever made it. §7.5's
    /// "a bridge member can't keep its own service" is about this one, and so
    /// is the row that offers `Return to Bridge…`.
    var hasServiceOfItsOwn: Bool {
        switch configuration {
        case .readyForRDMA?, .nearMatch?, .foreign?: true
        case .unconfigured?, nil: false
        }
    }

    /// That service's identifier. Matching is by identifier, never by name
    /// (`docs/ARCHITECTURE.md`, rule 2).
    var serviceIdentifier: String? {
        switch configuration {
        case .readyForRDMA(let id)?: id
        case .nearMatch(let id, _)?: id
        case .foreign(let id, _)?: id
        case .unconfigured?, nil: nil
        }
    }

    /// The part of a port RDMALinkCore's refusals and operations take.
    var observed: ObservedPort {
        ObservedPort(
            bsdName: port.bsdName,
            positionName: port.positionName,
            hasLinkedMac: port.link == .macLinked,
            bridges: port.bridges.map(\.name),
            loopedBackTo: port.loopedBackTo
        )
    }
}
