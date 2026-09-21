//
//  HubPresentation.swift
//
//  S1's headline and body, the situation rows that sit between the
//  `This Mac` section and the port list, and what the footer offers. Verbatim
//  from docs/UX_SPEC.md §S1, §2.8, §6.2 R23 and §6.2 R31.
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
/// No symbol and no colour: every one of these is a sentence about the world,
/// and §6.1's symbol treatment belongs to refusals. Two of them carry the
/// actions §S1 gives them, and one carries a second line of detail.
struct Situation: Sendable, Equatable, Identifiable {
    var id: String
    var text: LocalizedStringResource
    /// §S1's drift row is the only one with a detail line.
    var detail: LocalizedStringResource?
    var actions: [HubAction] = []
}

extension Situation {
    /// §7.4 and R20's aftermath: the service is gone, the bridge has not taken
    /// the port back, and the note was deliberately kept.
    static func needsAHand(_ port: PortSnapshot) -> Situation {
        Situation(
            id: "needsAHand",
            text: "\(port.port.positionName) needs putting back by hand.",
            actions: [.showMe(portID: port.id)]
        )
    }

    /// §7.4: "Drift is news, not failure."
    static func drift(_ port: PortSnapshot) -> Situation {
        Situation(
            id: "drift",
            text: "\(port.port.positionName) isn't set up any more.",
            detail: "The network service RDMALink made is gone — it may have been removed in System Settings.",
            actions: [.setItUpAgain(portID: port.id), .forgetThisPort(portID: port.id)]
        )
    }

    static let restartOwed = Situation(
        id: "restartOwed",
        text: "RDMA is switched on and waiting for a restart. Restart whenever it suits you."
    )

    static let usbCableTip = Situation(
        id: "usbCableTip",
        text: "There's a cable in a front port. Those carry USB, not Thunderbolt. Move it to one of the four ports on the back and I'll follow along."
    )

    static let twoMacsTip = Situation(
        id: "twoMacsTip",
        text: "Two Macs are connected. Leave just one cable in place while we work — two can send Ethernet traffic around in a loop."
    )
}

/// What the hub's footer offers (§S1's primary action, §2.8's persistent
/// `Restore…`).
struct HubFooterModel: Sendable, Equatable {
    /// Absent, not disabled, in R23's and R31's read-only modes (§S1: "The
    /// footer's primary button is **absent**, not disabled").
    var primary: HubAction?
    var primaryTitle: LocalizedStringResource
    var isPrimaryEnabled: Bool
    /// §S1: with two Macs connected the primary is disabled "with the reason
    /// printed above the footer separator".
    var disabledReason: LocalizedStringResource?
    /// Whether §2.8's `Restore…` may stand beside the primary at all. False
    /// only in R31's read-only mode — "The footer has no buttons at all" —
    /// where a note is not RDMALink's to act on; whether a note *exists* is
    /// the hub's live answer (`HubActionsModel.hasRestorableNote`).
    var offersRestore: Bool
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
    /// S1's headline and body; R31's on a Mac neither rule in §4.7
    /// recognizes; R23's when the catalogue says this Mac's ports are
    /// Thunderbolt 4.
    ///
    /// R31 wins over R23 when both apply: R23 says "there's nothing for
    /// RDMALink to set up" about a Mac it knows, and on one it does not know
    /// the honest sentence is that it does not know it — the generation table
    /// is keyed on the identifier, and an identifier can be listed there
    /// without the chassis being recognized.
    static func copy(
        hardware: HardwareModel?,
        ports: [PortSnapshot]
    ) -> HubCopy {
        if hardware?.isRecognized == false {
            return HubCopy(
                headline: "I don't recognize this Mac",
                body: "RDMALink only draws, and only changes, Macs it knows — and this isn't one of them. So there's no picture, and nothing here will be changed. The ports below are listed the way macOS reports them, and everything you see is real."
            )
        }
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
        switchState: RDMASwitchState,
        ports: [PortSnapshot]
    ) -> [Situation] {
        var result: [Situation] = []
        if let port = ports.first(where: needsAHand) {
            result.append(.needsAHand(port))
        }
        if let port = ports.first(where: hasDrifted) {
            result.append(.drift(port))
        }
        if switchState == .onAfterRestart { result.append(.restartOwed) }
        if hasCableInAFrontUSBPort(ports) { result.append(.usbCableTip) }
        if ports.inALoop.count >= 2 { result.append(.twoMacsTip) }
        return result
    }

    /// §7.4's "a port needing putting back by hand", which is R20's state seen
    /// on a later launch: RDMALink's service is gone, the bridge has not taken
    /// the port back, and the note was kept on purpose.
    ///
    /// Observed, never remembered: a note that records the bridges the port
    /// came from, a port that is now in none of them, and no service of its
    /// own. An adopted note has no bridge history and can never be this.
    static func needsAHand(_ port: PortSnapshot) -> Bool {
        guard let baseline = port.baseline, !baseline.isAdopted, !baseline.bridges.isEmpty else {
            return false
        }
        guard case .unconfigured(let bridges)? = port.configuration else { return false }
        return bridges.isEmpty
    }

    /// Drift proper: there is a note, and what it describes is not there any
    /// more. The half-restored port above is a drift the app can name more
    /// precisely, so it is taken out of this one.
    static func hasDrifted(_ port: PortSnapshot) -> Bool {
        port.readiness == .drifted && !needsAHand(port)
    }

    /// §S1's footer: the primary action, and `Restore…` beside it whenever a
    /// note exists (§2.8).
    /// §2.8's `Restore…` is not here: whether a note `Restore…` can put
    /// something back from exists is a live answer the hub keeps
    /// (`HubActionsModel.hasRestorableNote`), and asking it in two places is
    /// how the two come to disagree.
    static func footer(
        hardware: HardwareModel?,
        ports: [PortSnapshot]
    ) -> HubFooterModel {
        let twoMacs = ports.inALoop.count >= 2
        // R31: "The footer has no buttons at all." R23: no primary button at
        // all, and `Identify a Port…` stays in the Port menu.
        let unrecognized = hardware?.isRecognized == false
        let readOnly = unrecognized || hardware?.isThunderbolt4 == true
        return HubFooterModel(
            primary: readOnly ? nil : .setUpAPort(portID: nil),
            primaryTitle: ports.ready.isEmpty ? "Set Up a Port…" : "Set Up Another Port…",
            isPrimaryEnabled: !twoMacs,
            // §S1 asks for "the reason printed above the footer separator" and
            // does not write one there. This is S3's own reason for the same
            // condition, which is the nearest sentence the spec has.
            disabledReason: twoMacs ? "Unplug one of the two cables to continue." : nil,
            offersRestore: !unrecognized
        )
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

/// The moments the copy quotes, in the two shapes the spec writes them in:
/// `3 September at 14:21` inside a sentence (§7.1, §S10, §S11) and
/// `3 September, 14:21` at the head of a change-log entry (§S11).
///
/// The day and the time are Core's `Moment` halves — the locale's own long
/// day-and-month and its short time, `14:21` or `2:21 PM` (§7.1) — so the app
/// and the operations never format one moment two ways; only the join between
/// them is the app's, and it is one localizable string so a translator can
/// move both halves.
enum Moments {
    static func dayAtTime(_ date: Date) -> String {
        let value: String.LocalizationValue = "\(day(date)) at \(time(date))"
        return String(localized: value)
    }

    static func dayAndTime(_ date: Date) -> String {
        let value: String.LocalizationValue = "\(day(date)), \(time(date))"
        return String(localized: value)
    }

    private static func day(_ date: Date) -> String {
        Moment.day(date, locale: .autoupdatingCurrent)
    }

    private static func time(_ date: Date) -> String {
        Moment.time(date, locale: .autoupdatingCurrent)
    }
}
