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
/// §S4's dimmed rows are not dead: two of them route somewhere (R27) and one
/// produces R3's copy. A row that refuses a click without saying anything
/// would be the dead end §1.3 rule 5 exists to forbid.
enum ChooseRefusalRoute: Sendable, Equatable {
    /// USB-only: R3, inline, with `Turn the Mac Around`.
    case usbPort
    /// Already a link: the row offers `Restore…` and one line is printed.
    case alreadyReady
    /// Set up by hand: routes silently to Adopt (S9).
    case adopt
    /// R16 — a service RDMALink didn't make, with a fixed IPv4 address on it.
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
    /// Receptacles that are selected by default, and why, in words rather than
    /// assumed (§S4 "Pre-selection").
    var preSelection: Set<String>
    var preSelectionLine: LocalizedStringResource?
    /// On an unrecognized model, `Identify a Port…` is promoted above the list
    /// and the numbering is explained.
    var promotesIdentify: Bool
    var unrecognizedModelLine: LocalizedStringResource?
    /// The informational lines the current selection earns. Never blocking.
    var informationalLines: [ChooseInformationalLine]
    /// Shown once more than one port is chosen.
    var multiSelectNote: LocalizedStringResource?
    /// `.caption` secondary on the leading side of the footer.
    var counter: LocalizedStringResource?
    /// R26 — a dead end handled kindly, with no buttons: it watches and clears.
    var everyPortOccupied: WizardRefusal?

    init(
        ports: [PortSnapshot],
        hardware: HardwareModel?,
        selection: Set<String>
    ) {
        let archetype = hardware?.archetype ?? .unknown
        self.body =
            archetype == .notebook
            ? "Click a port on the model, or pick one from the list. Use the selector below the model to see the other side."
            : "Click a port on the model, or pick one from the list. If it's on the other side, I'll turn the Mac around."

        let selectablePorts = ports.filter { Self.route(for: $0) == nil }
        self.selectable = Set(selectablePorts.map(\.id))

        let candidates = selectablePorts.filter { $0.port.link == .macLinked }
        switch candidates.count {
        case 1:
            self.preSelection = [candidates[0].id]
            self.preSelectionLine =
                "I've picked \(candidates[0].port.positionName) for you, because that's the port with another Mac on the end of it. Choose a different one if you'd rather."
        case 2:
            self.preSelection = []
            self.preSelectionLine =
                "Two ports have a Mac on the end. I haven't picked for you — choose the one with the cable you mean."
        default:
            self.preSelection = []
            self.preSelectionLine = nil
        }

        self.promotesIdentify = archetype == .unknown
        self.unrecognizedModelLine =
            archetype == .unknown
            ? "The ports here are numbered the way macOS reports them. If you're not sure which is which, Identify will tell you."
            : nil

        let chosen = ports.filter { selection.contains($0.id) }
        self.informationalLines = chosen.compactMap(ChooseInformationalLine.init)
        self.multiSelectNote =
            chosen.count > 1
            ? "RDMALink will prepare both, one after the other, from the same password."
            : nil
        self.counter = chosen.count > 1 ? "\(chosen.count) ports selected" : nil

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
    static func route(for snapshot: PortSnapshot) -> ChooseRefusalRoute? {
        guard snapshot.port.isThunderbolt else { return .usbPort }
        if case .foreign = snapshot.configuration { return .foreignService }
        switch snapshot.readiness {
        case .plain: return nil
        case .managed, .adopted: return .alreadyReady
        case .setUpElsewhere: return .adopt
        // A port whose setup has gone away is a port to set up again, and
        // §7.4 calls that news rather than failure. Core's own preview is
        // what decides whether it really can be — a stale note is never
        // reapplied to a world that moved — so the click is allowed through
        // and the plan answers. **Owed from the spec owner:** §S4 has no
        // subtitle for this row.
        case .drifted: return nil
        }
    }

    /// The dimmed rows' subtitles (§S4). Returned for the list to draw; a
    /// `nil` means the row keeps the subtitle the hub already gives it.
    static func dimmedSubtitle(for route: ChooseRefusalRoute) -> LocalizedStringResource? {
        switch route {
        case .usbPort: "USB only — this one isn't Thunderbolt"
        case .alreadyReady: "Already ready for RDMA"
        case .adopt: "Set up outside RDMALink"
        case .foreignService: nil
        }
    }
}

/// One informational line about a chosen port. Informational, never blocking.
struct ChooseInformationalLine: Sendable, Equatable, Identifiable {
    var id: String
    var text: LocalizedStringResource

    init?(_ snapshot: PortSnapshot) {
        switch snapshot.port.link {
        case .device:
            self.id = snapshot.id
            self.text = "There's a dock in this port. RDMALink can still prepare it — it will carry RDMA once a Mac is on the other end."
        case .empty:
            self.id = snapshot.id
            self.text = "Nothing is plugged in here yet. That's fine — the address appears when a Mac arrives."
        case .macLinked, .macLinkComingUp:
            return nil
        }
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
