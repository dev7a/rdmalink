//
//  HubPresentation.swift
//
//  S1's headline and body, and the situation rows that sit between the
//  `This Mac` section and the port list. Verbatim from docs/UX_SPEC.md §S1 and
//  §6.2 R23.
//

import Foundation
import RDMALinkCore

/// The two lines at the top of the hub's working area.
struct HubCopy: Sendable, Equatable {
    var headline: LocalizedStringResource
    var body: LocalizedStringResource
}

/// A situation the hub states as a situation and not as an alarm (§S1, §7.4).
///
/// ML1 carries the four that are observable without a write history. The two
/// that are not — a port needing putting back by hand, and a port that has
/// drifted — arrive with the baseline writes in ML2 and keep their place at the
/// head of this order.
enum Situation: String, Sendable, Equatable, Identifiable, CaseIterable {
    case restartOwed
    case usbCableTip
    case twoMacsTip
    case unrecognizedModel

    var id: String { rawValue }

    var text: LocalizedStringResource {
        switch self {
        case .restartOwed:
            "RDMA is switched on and waiting for a restart. Restart whenever it suits you."
        case .usbCableTip:
            "There's a cable in a front port. Those carry USB, not Thunderbolt. Move it to one of the four ports on the back and I'll follow along."
        case .twoMacsTip:
            "Two Macs are connected. Leave just one cable in place while we work — two can send Ethernet traffic around in a loop."
        case .unrecognizedModel:
            "I don't recognize this Mac, so the picture is a stand-in and the ports are numbered the way macOS reports them. Everything else works normally."
        }
    }
}

/// R3 — "A cable is in a USB-only port", as the card §4.5 raises when a
/// USB-only receptacle is clicked.
///
/// §6.2 gives two bodies and no third, and both name a count: four Thunderbolt
/// receptacles on the back, or a Mac mini's three. Neither is stated unless
/// this Mac really is that shape, because the app never states something it
/// has not observed (§1.3 rule 10). The two chassis in the catalogue that
/// carry USB-only receptacles at all are exactly these two, so in practice
/// there is always a body; a third shape would need a string from the spec
/// owner before the card could say anything.
///
/// Where there is no body there is no card, so §4.5's "never a
/// disabled-button dead end" is kept by refusing the click at source rather
/// than by drawing nothing: see `RootView.usbClickable(_:)`.
enum USBPortTip {
    static let headline: LocalizedStringResource = "That's a USB port"

    static func body(hardware: HardwareModel?, ports: [PortSnapshot]) -> LocalizedStringResource? {
        let back = ports.count { $0.port.isThunderbolt && $0.port.face == .back }
        let frontUSB = ports.count { !$0.port.isThunderbolt && $0.port.face == .front }
        if hardware?.archetype == .mini, back == 3, frontUSB == 2 {
            return "The two ports at the front of a Mac mini carry USB, not Thunderbolt. The three on the back are the Thunderbolt ones."
        }
        guard back == 4 else { return nil }
        return "The front ports on this Mac carry USB, not Thunderbolt. Move the cable to one of the four Thunderbolt ports on the back and I'll follow along."
    }
}

enum HubPresentation {
    /// S1's headline and body, or R23's when the catalogue says this Mac's
    /// ports are Thunderbolt 4.
    static func copy(
        hardware: HardwareModel?,
        ports: [PortSnapshot]
    ) -> HubCopy {
        if hardware?.isThunderbolt4 == true {
            return HubCopy(
                headline: "Nothing to configure here",
                body: "This Mac has Thunderbolt 4 ports. RDMA over Thunderbolt needs Thunderbolt 5, so there's nothing for RDMALink to set up. You're welcome to look around — everything you see is real."
            )
        }
        let ready = ports.ready
        guard let first = ready.first else {
            return HubCopy(
                headline: "Let's set up a Thunderbolt link",
                body: "RDMALink prepares one Thunderbolt port on this Mac so it can carry RDMA straight to another Mac. You'll do the same on the other Mac afterwards."
            )
        }
        return HubCopy(headline: headline(readyCount: ready.count), body: steadyStateBody(first))
    }

    /// §S1 writes the count in words and gives one and two. Three or more has
    /// no copy in the spec, so the same sentence is spelled out rather than
    /// invented in another shape.
    private static func headline(readyCount: Int) -> LocalizedStringResource {
        switch readyCount {
        case 1: "One port is ready for RDMA"
        case 2: "Two ports are ready for RDMA"
        default: "\(ThisMacPresentation.spelledOut(readyCount)) ports are ready for RDMA"
        }
    }

    /// Names the first ready port and says whether a Mac is on the end of it.
    private static func steadyStateBody(_ port: PortSnapshot) -> LocalizedStringResource {
        port.port.link == .macLinked
            ? "\(port.port.positionName) is set up and linked. Nothing else on this Mac was changed."
            : "\(port.port.positionName) is set up and waiting for a Mac. Nothing else on this Mac was changed."
    }

    /// The situation rows, in the order §S1 lists them, at most one of each.
    static func situations(
        hardware: HardwareModel?,
        switchState: RDMASwitchState,
        ports: [PortSnapshot]
    ) -> [Situation] {
        var result: [Situation] = []
        if switchState == .onAfterRestart { result.append(.restartOwed) }
        if hasCableInAFrontUSBPort(ports) { result.append(.usbCableTip) }
        if ports.withAMac.count >= 2 { result.append(.twoMacsTip) }
        if let hardware, !hardware.isRecognized { result.append(.unrecognizedModel) }
        return result
    }

    /// The cable is now observable: ``ChassisProbe`` keeps the position nodes
    /// with no Thunderbolt port behind them, and `CataloguePortRows` puts their
    /// `ConnectionActive` on the USB-only row's `link`.
    ///
    /// The row's copy names its destination — "one of the four ports on the
    /// back" — so it is only true on a Mac whose back really does carry four
    /// Thunderbolt receptacles, which is the Mac Studio that has USB-only
    /// receptacles at all. On a Mac mini the sentence would state a count the
    /// app has not observed (§1.3 rule 10). §6.2 R3 *does* give a Mac mini
    /// body, so clicking the receptacle answers properly there; it is only
    /// §S1's unprompted row that has no mini wording. **Owed from the spec
    /// owner:** a Mac mini version of this situation row.
    private static func hasCableInAFrontUSBPort(_ ports: [PortSnapshot]) -> Bool {
        let backThunderbolt = ports.count { $0.port.isThunderbolt && $0.port.face == .back }
        guard backThunderbolt == 4 else { return false }
        return ports.contains {
            !$0.port.isThunderbolt && $0.port.face == .front && $0.port.link != .empty
        }
    }
}
