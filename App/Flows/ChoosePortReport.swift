//
//  ChoosePortReport.swift
//
//  S4 — Choose a port (UX_SPEC §S4). Turning "which hole" into a two-second
//  decision by making the model and the list one selection.
//
//  Pure. Selectability, the pre-selection and every line on the screen are
//  functions of the receptacles and the current selection, so the rules stay
//  checkable and the screen re-derives itself the moment a cable moves.
//

import Foundation
import RDMALinkCore

/// Why a receptacle cannot be chosen, when it cannot.
///
/// §S4's dimmed rows are not dead: most of them route somewhere (R27), and
/// the rest produce a card (R3, R16). A row that refuses a click without
/// saying anything would be the dead end §1.3 rule 5 exists to forbid.
enum ChooseRefusalRoute: Sendable, Equatable {
    /// USB-only: R3, inline, with `Show Thunderbolt Ports`.
    case usbPort
    /// Already a link: the row offers `Restore…` — or `Return to Bridge…`
    /// for an adopted port, which has no exact Restore (§7.3) — and one line
    /// is printed.
    case alreadyReady
    /// A note that records the bridges the port came from, over a port in no
    /// bridge with no service (§S1, §7.4): the row offers `Restore…`, never a
    /// set-up, and is never pre-selected.
    case needsAHand
    /// Set up by hand and out of every bridge, a near match included (§S9):
    /// the row offers `Adopt…`. Core routes a port with a service of its own
    /// to Adopt and never plans it (`routesToAdopt`), so choosing one would
    /// open a Review with nothing to press.
    case adopt
    /// §S1's drifted port whose service is still the one RDMALink made,
    /// edited by hand since — nearly a match now, or given a fixed IPv4
    /// address: the row offers `Restore…`, which raises R28 and says what
    /// changed. `Adopt…` would claim RDMALink didn't make it, and R16 that it
    /// isn't RDMALink's.
    case editedService
    /// R16 — a service RDMALink didn't make and can't adopt: a fixed IPv4
    /// address on it, or a service of its own on a port still in a bridge,
    /// which Adopt can't take either (§7.3). The row names no route; a click
    /// raises the card.
    case foreignService
}

/// S4, ready to draw.
struct ChoosePortReport: Sendable, Equatable {
    static let headline: LocalizedStringResource = "Which port should carry RDMA?"

    /// Desktop or notebook: the difference is whether turning the Mac around
    /// is something the app does or something the face selector does.
    var body: LocalizedStringResource
    /// Which receptacles a click can select.
    var selectable: Set<String>
    /// The port RDMALink would pick for the user: the one selectable port
    /// with a Mac linked, when there is exactly one (§S4 "Pre-selection").
    var preSelection: Set<String>
    /// Why the selection is what it is, in words rather than assumed — and
    /// only while it still is (§S4): the one-candidate line while RDMALink's
    /// pick is the selection, the two-candidates line while nothing is chosen.
    var preSelectionLine: LocalizedStringResource?
    /// The informational lines the current selection earns. Never blocking.
    var informationalLines: [ChooseInformationalLine]
    /// Shown once more than one port is chosen.
    var multiSelectNote: LocalizedStringResource?
    /// `.caption` secondary on the leading side of the footer.
    var counter: LocalizedStringResource?
    /// R26 — a dead end handled kindly, with no buttons: it watches and clears.
    var everyPortOccupied: WizardRefusal?

    /// - Parameters:
    ///   - hardware: a Mac the catalogue recognizes. An unrecognized one never
    ///     reaches this screen: R31 offers no set-up (§S4).
    ///   - picked: the pick this run made for the user when it opened, if it
    ///     made one — not a port that came from the hub, which the user chose.
    init(
        ports: [PortSnapshot],
        hardware: HardwareModel?,
        selection: Set<String>,
        picked: Set<String>? = nil
    ) {
        self.body =
            hardware?.archetype == .notebook
            ? "Click a port on the model, or pick one from the list. Use the selector below the model to see the other side."
            : "Click a port on the model, or pick one from the list. If it's on the other side, RDMALink will turn the Mac around."

        let selectablePorts = ports.filter { Self.route(for: $0) == nil }
        self.selectable = Set(selectablePorts.map(\.id))

        let candidates = selectablePorts.filter { $0.port.link == .macLinked }
        switch candidates.count {
        case 1:
            let pick: Set<String> = [candidates[0].id]
            self.preSelection = pick
            // "Choose a different one if you'd rather" is only true while the
            // pick on screen is RDMALink's: a port the user chose — on the
            // hub or here — is theirs, and the sentence would contradict it.
            self.preSelectionLine =
                picked == pick && selection == pick
                ? "RDMALink has picked \(candidates[0].port.positionName) for you, because that's the port with another Mac on the end of it. Choose a different one if you'd rather."
                : nil
        case 2:
            self.preSelection = []
            self.preSelectionLine =
                selection.isEmpty
                ? "Two ports have a Mac on the end. RDMALink hasn't picked for you — choose the one with the cable you mean."
                : nil
        default:
            self.preSelection = []
            self.preSelectionLine = nil
        }

        let chosen = ports.filter { selection.contains($0.id) }
        // With more than one port chosen, "here" could be any of them, so
        // each line names its port (§S4).
        self.informationalLines = chosen.compactMap {
            ChooseInformationalLine($0, namesThePort: chosen.count > 1)
        }
        // Counts are words, in the counter as in the note (§1.3 rule 1).
        switch chosen.count {
        case 0, 1:
            self.multiSelectNote = nil
            self.counter = nil
        case 2:
            self.multiSelectNote = "RDMALink will prepare both, one after the other, from the same password."
            self.counter = "Two ports selected"
        default:
            let count = ThisMacPresentation.spelledOut(chosen.count, capitalized: false)
            self.multiSelectNote = "RDMALink will prepare all \(count), one after the other, from the same password."
            self.counter = "\(ThisMacPresentation.spelledOut(chosen.count)) ports selected"
        }

        // "Every Thunderbolt port has something in it" — every one of them,
        // not most of them, and only once there is at least one to speak of.
        let thunderbolt = ports.filter(\.port.isThunderbolt)
        let allOccupied = !thunderbolt.isEmpty && thunderbolt.allSatisfy { $0.port.link != .empty }
        self.everyPortOccupied =
            allOccupied
            ? WizardRefusals.everyPortOccupied(detail: Self.occupancy(thunderbolt))
            : nil
    }

    /// R26's finding: what is actually in each receptacle, in physical order
    /// and in §4.2's own words. The card states what was observed rather than
    /// an example of what might have been.
    static func occupancy(_ ports: [PortSnapshot]) -> LocalizedStringResource? {
        guard !ports.isEmpty else { return nil }
        let described = ports.map { port -> String in
            let state: LocalizedStringResource
            switch port.port.link {
            case .device: state = "A device is connected — not a Mac"
            case .macLinked: state = "Linked to another Mac"
            case .macLinkComingUp: state = "Another Mac is here. The link is still coming up."
            case .empty: state = "Nothing plugged in"
            }
            return "\(port.port.positionName): \(String(localized: state))"
        }
        let joined = described.formatted(.list(type: .and))
        return LocalizedStringResource(String.LocalizationValue(joined))
    }

    /// Where a click on this receptacle goes, or `nil` when it simply selects.
    ///
    /// This is also every set-up control's test (`PortRowPresentation
    /// .offersSetUp`): a port that routes is never offered one, so no control
    /// opens a Review that would have nothing to press (§S4).
    static func route(for snapshot: PortSnapshot) -> ChooseRefusalRoute? {
        guard snapshot.port.isThunderbolt else { return .usbPort }
        // A drifted port with a service of its own is split by identity
        // first (§S1): the service RDMALink made, edited by hand since, is
        // RDMALink's whatever it was edited into — a near match or a fixed
        // IPv4 address alike — and Restore is what says so, with R28 (§6.2
        // R27). Only a service RDMALink didn't make reaches R16 or Adopt.
        if snapshot.hasRDMALinksOwnServiceEdited { return .editedService }
        switch snapshot.configuration {
        case .foreign?:
            return .foreignService
        // A service of the port's own that is nearly what a link needs. Core
        // routes it to Adopt and never plans it, so it is not selectable. A
        // service of its own on a port still in a bridge is no near match
        // Adopt can take (§7.3, `AdoptForm`), so R16 answers for it rather
        // than an `Adopt…` that could only close again (§S9 "Not a match at
        // all").
        case .nearMatch?:
            return snapshot.hasAServiceInABridge ? .foreignService : .adopt
        case .readyForRDMA?, .unconfigured?, nil:
            break
        }
        switch snapshot.readiness {
        case .plain: return nil
        case .managed, .adopted: return .alreadyReady
        case .setUpElsewhere: return .adopt
        case .needsAHand: return .needsAHand
        // A port whose setup has gone away is a port to set up again, and
        // §7.4 calls that news rather than failure. Core's own preview is
        // what decides whether it really can be — a stale note is never
        // reapplied to a world that moved — so the click is allowed through
        // and the plan answers. **Owed from the spec owner:** §S4 has no
        // subtitle for this row.
        case .drifted: return nil
        // In the bridge with nothing on it: the ordinary thing to set up.
        case .returned: return nil
        }
    }

    /// The dimmed rows' subtitles (§S4). Returned for the list to draw; a
    /// `nil` means the row keeps the subtitle the hub already gives it, which
    /// for a port needing a hand, an edited service and R16 already says why.
    static func dimmedSubtitle(for route: ChooseRefusalRoute) -> LocalizedStringResource? {
        switch route {
        case .usbPort: "USB only — this one isn't Thunderbolt"
        case .alreadyReady: "Already ready for RDMA"
        case .adopt: "Set up outside RDMALink"
        case .needsAHand, .editedService, .foreignService: nil
        }
    }

    /// §S4: "A dimmed row keeps only the route this screen names for it" —
    /// and it is the one sheet the picker lets open over the assistant, so
    /// the Port menu offers exactly this and nothing else of the kind (§2.6,
    /// §2.7). An adopted port that is already ready is named `Return to
    /// Bridge…`, the sheet its `Restore…` would open under another name:
    /// it has no exact Restore (§7.3, §S9). A USB-only row and R16's name
    /// none: their answer is the card a click raises, whose own buttons say
    /// what to do.
    static func namedAction(for route: ChooseRefusalRoute, snapshot: PortSnapshot) -> HubAction? {
        let portID = snapshot.id
        switch route {
        case .alreadyReady:
            return snapshot.readiness == .adopted
                ? .returnToBridge(portID: portID) : .restore(portID: portID)
        case .needsAHand, .editedService: return .restore(portID: portID)
        case .adopt: return .adopt(portID: portID)
        case .usbPort, .foreignService: return nil
        }
    }

    /// §S5's R27 backstop: the headline over the line, which follows the
    /// route (§6.2 R27) — S9's full-match headline for a port that is set up
    /// properly, S9's near-match headline for a near match, R28's for
    /// RDMALink's own service edited since.
    static func backstopHeadline(
        for route: ChooseRefusalRoute, snapshot: PortSnapshot
    ) -> LocalizedStringResource {
        switch route {
        case .editedService:
            return "This port's service isn't the one RDMALink made any more"
        case .adopt:
            if case .nearMatch? = snapshot.configuration { return "Nearly a match" }
            return WizardRefusals.alreadySetUpHeadline
        case .alreadyReady, .needsAHand, .usbPort, .foreignService:
            return WizardRefusals.alreadySetUpHeadline
        }
    }

    /// §6.2 R27: the one line a click on a routed row prints — a fact, and
    /// the name of the row's own button, never a question (§8.8). `nil` for
    /// the routes whose answer is a card.
    static func routingLine(
        for route: ChooseRefusalRoute, snapshot: PortSnapshot
    ) -> LocalizedStringResource? {
        switch route {
        case .alreadyReady:
            if snapshot.readiness == .adopted {
                return "This one's already a link, looked after by RDMALink. Return to Bridge… puts it in Thunderbolt Bridge."
            }
            return "This one's already a link. Restore… puts it back."
        case .needsAHand:
            return "This one needs putting back by hand. Restore… puts it back."
        case .adopt:
            // "and properly" is a claim, and a near match has not earned it.
            if case .nearMatch? = snapshot.configuration {
                return "This one was set up by hand, but not quite the way a link needs. Adopt… shows what to change."
            }
            return "This one was set up by hand, and properly. Adopt… looks after it without changing it."
        case .editedService:
            return "RDMALink set this one up, and it's been changed since. Restore… shows what changed."
        case .usbPort, .foreignService:
            return nil
        }
    }
}

/// One informational line about a chosen port. Informational, never blocking,
/// and drawn with no symbol: orange means the user needs to act (§3.1).
///
/// The sentence is Core's (`SetUpPorts.informationalLine`), the one Review
/// prints under the port's section, so each fact has one sentence on both
/// screens (§S4, §S5). With one port chosen it says "this port"; with more,
/// the same sentence would appear twice about two ports it doesn't name, so
/// each line names its port instead (§S4).
struct ChooseInformationalLine: Sendable, Equatable, Identifiable {
    var id: String
    var text: LocalizedStringResource

    init?(_ snapshot: PortSnapshot, namesThePort: Bool = false) {
        guard let line = SetUpPorts.informationalLine(
            for: snapshot.port.link,
            naming: namesThePort ? snapshot.port.positionName : nil)
        else { return nil }
        self.id = snapshot.id
        self.text = LocalizedStringResource(core: line)
    }
}

/// §S4's live-change line: something moved while the user was choosing, and
/// the selection survived it. Not a refusal — R17 is what happens when the
/// world moves after the review has been read.
enum ChooseLiveChange {
    static func line(positionName: String) -> LocalizedStringResource {
        "Something changed on \(positionName) while you were choosing. It's still selected — have a look before you continue."
    }
}
