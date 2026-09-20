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
/// reduced to the five answers the ML1 hub can actually observe.
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
        case .plain, .setUpElsewhere, .drifted: false
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
        guard matches else { return .drifted }
        return baseline.isAdopted ? .adopted : .managed
    }

    /// The link-local address with its scope suffix, the way UX_SPEC §S1 prints
    /// it: `fe80::1c3d:5aff:fe22:9b04%en6`. Core stores the address without the
    /// suffix; tools need every character of it, so it is put back here.
    var linkLocalAddress: String? {
        guard let address = port.linkLocal.first else { return nil }
        return "\(address)%\(port.bsdName)"
    }

    /// The name macOS has for this port's service, when it has one. Shown only
    /// with "Show technical names" on (§1.3 rule 6).
    var serviceName: String?
}

extension Array where Element == PortSnapshot {
    /// The ports §S1's "Ports ready for RDMA" row names, in physical order.
    var ready: [PortSnapshot] { filter { $0.readiness.isReady } }

    /// The ports §S1 offers `Adopt…` on.
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
                         hasLinkedMac: true, bridges: $0.port.bridges.map(\.name))
        }
        let subjects = Set(Refusals.oneCableOnly(observed)?.subjects ?? [])
        return withAMac.filter { subjects.contains($0.port.bsdName) }
    }
}
