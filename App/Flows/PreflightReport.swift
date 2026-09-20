//
//  PreflightReport.swift
//
//  S3 — Before we change anything (UX_SPEC §S3). Every hard rule the app can
//  measure, so the user is never asked to promise something.
//
//  Nothing on this screen is a checkbox and nothing here can be waved through.
//  There is not one attestation row in it: every row states a *finding*, and a
//  finding the app has not observed yet reads as "checking" rather than as
//  "satisfied", because the app never claims something it hasn't verified
//  (§1.3 rules 4 and 10).
//
//  Pure. The report is a function of `PreflightFindings` and nothing else, so
//  the copy stays checkable against the spec and the live re-evaluation is a
//  matter of handing it a new value.
//

import Foundation
import RDMALinkCore

// The list joins below use `ThisMacPresentation.english` for the reason given
// there: the app's sentences are English, and a list joined in the user's
// locale would put a French "et" inside one.

/// One receptacle as the preflight checks name it.
struct PreflightPort: Sendable, Equatable {
    var id: String
    var positionName: String

    init(id: String, positionName: String) {
        self.id = id
        self.positionName = positionName
    }
}

/// How this Mac is reachable with Thunderbolt taken out of the picture (R5).
enum PreflightRoute: Sendable, Equatable {
    /// Not read yet. The row waits rather than guessing.
    case unknown
    case wiFi
    /// Ethernet, or anything else that is not Thunderbolt and not Wi-Fi,
    /// named the way System Settings names it.
    case otherThanWiFi(name: String?)
    case thunderboltOnly
}

/// Everything S3's four rows are derived from.
///
/// `nil` means *not observed yet*, which is a third state and not a quiet
/// "fine". It draws `circle.dotted` and it greys `Continue` without printing a
/// reason, exactly as a re-check does.
struct PreflightFindings: Sendable, Equatable {
    /// True while `Check Again` is running: `Continue` greys for the duration.
    var isRechecking = false
    /// Receptacles with a Mac on the end, in physical order.
    var portsWithAMac: [PreflightPort] = []
    /// The ones among them that share a bridge, so this Mac could forward
    /// between the two cables — R1's subjects, from Core's own rule. Empty
    /// when no bridge holds more than one of them, however many there are.
    var portsInALoop: [PreflightPort] = []
    /// The two receptacles one cable's ends are both in — R2's subjects, from
    /// Core's own rule. Empty when no cable comes back into this Mac, or when
    /// this Mac cannot say. Independent of `portsWithAMac`: the rule rests on
    /// the Thunderbolt domain identities, not on both ends reading as linked
    /// in the same tick.
    var portsLoopedBack: [PreflightPort] = []
    /// True when a cable's two ends are both in this Mac (R2).
    var isLoopedBackIntoThisMac: Bool { !portsLoopedBack.isEmpty }
    /// Volumes mounted over Thunderbolt (R4). `nil` until something looks.
    var mountedThunderboltVolumes: [String]?
    /// R5.
    var route: PreflightRoute = .unknown
    /// R14. `nil` until something looks.
    var notesWritability: BaselineWritability?
    /// R13. `nil` until something looks.
    var isManagedByProfile: Bool?

    init() {}

    /// The half of the findings the hub's inventory already answers.
    ///
    /// R1 is a property of the receptacles and nothing else, so it is derived
    /// here. The other three need reads this value does not carry, and they
    /// stay `nil` — unobserved — until the caller fills them in.
    init(ports: [PortSnapshot], isRechecking: Bool = false) {
        self.init()
        self.isRechecking = isRechecking
        self.portsWithAMac = ports.withAMac.map {
            PreflightPort(id: $0.port.bsdName, positionName: $0.port.positionName)
        }
        self.portsInALoop = ports.inALoop.map {
            PreflightPort(id: $0.port.bsdName, positionName: $0.port.positionName)
        }
        self.portsLoopedBack = Self.loopedBack(ports.map(\.observed))
    }

    /// R2's two receptacles, in the order the refusal names them.
    private static func loopedBack(_ observed: [ObservedPort]) -> [PreflightPort] {
        Refusals.loopedBackIntoThisMac(observed)?.subjects.compactMap { subject in
            observed.first { $0.bsdName == subject }.map {
                PreflightPort(id: $0.bsdName, positionName: $0.positionName)
            }
        } ?? []
    }

    /// Everything S3 asks, from the one read Core already does for the
    /// operations. Call it off the main actor and hand the result back.
    ///
    /// R13 is not in `ObservedWorld` — nothing in this repository reads the
    /// configuration profiles yet — so it stays unobserved and its row keeps
    /// waiting rather than declaring this Mac unmanaged.
    /// **Owed from Core:** the managed-network probe.
    init(world: ObservedWorld, isRechecking: Bool = false) {
        self.init()
        self.isRechecking = isRechecking
        self.portsWithAMac = world.context.observedPorts.filter(\.hasLinkedMac).map {
            PreflightPort(id: $0.bsdName, positionName: $0.positionName)
        }
        let inALoop = Set(Refusals.oneCableOnly(world.context.observedPorts)?.subjects ?? [])
        self.portsInALoop = portsWithAMac.filter { inALoop.contains($0.id) }
        self.portsLoopedBack = Self.loopedBack(world.context.observedPorts)
        self.mountedThunderboltVolumes = world.mountedVolumes.map(\.name)
        // §S3 row 3's satisfied finding names Wi-Fi by name, so the row needs
        // to know what kind of interface the route is on.
        // `SCNetworkInterfaceGetInterfaceType` answers exactly that and Core
        // carries the answer on `PreflightContext`.
        let noOtherRoute = Refusals.managementPathExists(
            in: world.snapshot,
            thunderboltPorts: world.context.thunderboltBSDNames,
            primaryInterfaces: world.context.primaryInterfaces)
        if noOtherRoute != nil {
            self.route = .thunderboltOnly
        } else if let kind = world.context.routeOtherThanThunderbolt {
            self.route = kind.isWiFi ? .wiFi : .otherThanWiFi(name: kind.displayName)
        } else {
            // A route the observed fallback found but macOS did not name.
            self.route = .otherThanWiFi(name: nil)
        }
        self.notesWritability =
            world.notesAreWritable == nil
            ? .writable(availableBytes: nil)
            : .notWritable(reason: world.notesAreWritable?.detail ?? "")
    }
}

/// One of S3's rows.
struct PreflightRow: Sendable, Equatable, Identifiable {
    enum Check: String, Sendable, Equatable {
        case oneCable
        case nothingMounted
        case anotherRoute
        case undoNote
    }

    /// §S3: `checkmark.circle.fill` accent when satisfied, `exclamationmark.circle`
    /// `.orange` when not, `circle.dotted` while checking.
    enum State: Sendable, Equatable {
        case checking
        case satisfied
        case unsatisfied

        var symbol: String {
            switch self {
            case .checking: "circle.dotted"
            case .satisfied: "checkmark.circle.fill"
            case .unsatisfied: "exclamationmark.circle"
            }
        }
    }

    /// The trailing borderless button, "only where one helps".
    enum Action: Sendable, Equatable {
        case showInFinder
        case openNetworkSettings
        case showTheNotesFolder

        var wizardAction: WizardAction {
            switch self {
            case .showInFinder: .showInFinder
            case .openNetworkSettings: .openNetworkSettings
            case .showTheNotesFolder: .showTheNotesFolder
            }
        }
    }

    var check: Check
    var state: State
    var title: LocalizedStringResource
    /// The `.callout` secondary line carrying the actual finding. Absent only
    /// where the app has observed the check but the spec has no sentence for
    /// what it observed.
    var finding: LocalizedStringResource?
    var action: Action?

    var id: String { check.rawValue }
}

/// S3, ready to draw.
struct PreflightReport: Sendable, Equatable {
    var rows: [PreflightRow]
    /// R13 replaces the whole list. Nothing else does.
    var replacement: WizardRefusal?
    /// Printed in `.callout` `.orange` directly above the footer separator,
    /// and only when `Continue` is disabled because a check said no.
    var continueReason: LocalizedStringResource?
    var canContinue: Bool
    /// The receptacles an unsatisfied check names, for the attention ring.
    var attentionPortIDs: Set<String>
    /// §6.2 R2's two receptacles, in the order the refusal names them, for
    /// the thread the stage draws between them. Empty for every other row 1.
    var loopedPortIDs: [String]

    static let headline: LocalizedStringResource = "Before we change anything"

    /// UX_SPEC §S3 writes "Five things worth knowing", over a list whose fifth
    /// row is the always-satisfied, informational **This Mac only**. The user
    /// struck that row: that RDMALink changes the Mac it runs on and nothing
    /// else is implied by everything on screen, and the window subtitle already
    /// names the machine — the same reason the `This Mac` toolbar badge went.
    /// Four rows are left, so the count in the sentence follows them; printing
    /// "Five" over four rows would be the one thing §1.3 rule 10 forbids.
    /// **Owed from the spec owner:** this sentence and §S3's table.
    static let body: LocalizedStringResource =
        "Four things worth knowing. RDMALink checks them itself — nothing here is a promise you have to make."

    init(_ findings: PreflightFindings) {
        if findings.isManagedByProfile == true {
            self.rows = []
            self.replacement = WizardRefusals.managedByProfile
            self.continueReason = nil
            self.canContinue = false
            self.attentionPortIDs = []
            self.loopedPortIDs = []
            return
        }
        let rows = [
            Self.oneCable(findings),
            Self.nothingMounted(findings),
            Self.anotherRoute(findings),
            Self.undoNote(findings),
        ]
        self.rows = rows
        self.replacement = nil
        self.continueReason = findings.isRechecking ? nil : Self.reason(rows: rows, findings)
        self.canContinue =
            !findings.isRechecking && rows.allSatisfy { $0.state == .satisfied }
        // R2 rings the two ends of the cable; R1 rings the ports in the loop.
        // Each follows its refusal's subjects, so an end that is unplugged
        // stops ringing on the next read rather than staying with a pair.
        self.attentionPortIDs =
            rows[0].state == .unsatisfied
            ? Set((findings.isLoopedBackIntoThisMac ? findings.portsLoopedBack
                   : findings.portsInALoop.isEmpty ? findings.portsWithAMac
                   : findings.portsInALoop).map(\.id))
            : []
        self.loopedPortIDs =
            rows[0].state == .unsatisfied && findings.isLoopedBackIntoThisMac
            ? findings.portsLoopedBack.map(\.id) : []
    }

    // MARK: - Row 1

    private static func oneCable(_ findings: PreflightFindings) -> PreflightRow {
        let title: LocalizedStringResource = "One Thunderbolt cable to another Mac"
        // R2 first, and independent of how many ports read as linked: the
        // cable's two ends are known from the domain identities, and a looped
        // cable on two bridged ports would otherwise be reported as R1.
        if findings.isLoopedBackIntoThisMac {
            let named = findings.portsLoopedBack.map(\.positionName).formatted(.list(type: .and).locale(ThisMacPresentation.english))
            return PreflightRow(
                check: .oneCable, state: .unsatisfied, title: title,
                finding: "Both ends of one cable are in this Mac, on \(named). Unplug one end and put it in the other Mac."
            )
        }
        let macs = findings.portsWithAMac
        switch macs.count {
        case 0:
            return PreflightRow(
                check: .oneCable, state: .satisfied, title: title,
                finding: "No other Mac is connected yet. That's fine — you can prepare a port now and plug in later."
            )
        case 1:
            return PreflightRow(
                check: .oneCable, state: .satisfied, title: title,
                finding: "Just one, in \(macs[0].positionName). Perfect."
            )
        default:
            let loop = findings.portsInALoop
            guard loop.count >= 2 else {
                // Two or more cables, and no bridge holds more than one of
                // their ports: nothing on this Mac can forward between them.
                // A finished set-up looks exactly like this.
                let named = macs.map(\.positionName).formatted(.list(type: .and).locale(ThisMacPresentation.english))
                return PreflightRow(
                    check: .oneCable, state: .satisfied, title: title,
                    finding: "Cables in \(named), and no bridge holds more than one of them — nothing can loop."
                )
            }
            // §6.2 R1 keeps its headline for any count above one, and names
            // every receptacle in the loop; the row's finding does the same.
            let named = loop.map(\.positionName).formatted(.list(type: .and).locale(ThisMacPresentation.english))
            return PreflightRow(
                check: .oneCable, state: .unsatisfied, title: title,
                finding: "Two Macs are connected, on \(named). Unplug one and I'll pick this back up."
            )
        }
    }

    // MARK: - Row 2

    private static func nothingMounted(_ findings: PreflightFindings) -> PreflightRow {
        let title: LocalizedStringResource = "Nothing mounted over Thunderbolt"
        guard let volumes = findings.mountedThunderboltVolumes else {
            return PreflightRow(check: .nothingMounted, state: .checking, title: title)
        }
        guard let first = volumes.first else {
            return PreflightRow(
                check: .nothingMounted, state: .satisfied, title: title,
                finding: "Nothing is mounted. Good."
            )
        }
        // One volume gets the row's own sentence; several get R4's detail
        // sentence, which is the only plural the spec writes.
        let finding: LocalizedStringResource =
            volumes.count == 1
            ? "The volume \(first) is mounted over Thunderbolt. Eject it in Finder so nothing gets interrupted."
            : "\(volumes.formatted(.list(type: .and).locale(ThisMacPresentation.english))) are mounted over Thunderbolt."
        return PreflightRow(
            check: .nothingMounted, state: .unsatisfied, title: title,
            finding: finding, action: .showInFinder
        )
    }

    // MARK: - Row 3

    private static func anotherRoute(_ findings: PreflightFindings) -> PreflightRow {
        let title: LocalizedStringResource = "Another way to reach this Mac"
        switch findings.route {
        case .unknown:
            return PreflightRow(check: .anotherRoute, state: .checking, title: title)
        case .wiFi:
            return PreflightRow(
                check: .anotherRoute, state: .satisfied, title: title,
                finding: "Wi-Fi is connected, so changing a Thunderbolt port won't cut you off."
            )
        case .otherThanWiFi(let name):
            // §S3's satisfied finding names Wi-Fi by name and the spec writes
            // no Ethernet twin of it. §S3 requires every row to carry "the
            // **actual finding**", so the sentence keeps its shape and names
            // the route macOS itself reports instead — never Wi-Fi over
            // something that is not (§1.3 rule 10). A route macOS declines to
            // name leaves the row with its symbol and no claim.
            // **Owed from the spec owner:** the non-Wi-Fi sentence.
            guard let name else {
                return PreflightRow(check: .anotherRoute, state: .satisfied, title: title)
            }
            return PreflightRow(
                check: .anotherRoute, state: .satisfied, title: title,
                finding: "\(name) is connected, so changing a Thunderbolt port won't cut you off."
            )
        case .thunderboltOnly:
            return PreflightRow(
                check: .anotherRoute, state: .unsatisfied, title: title,
                finding: "Right now, Thunderbolt is the only way this Mac is reachable. Changing a port can briefly interrupt the whole bridge — not just that one port — so connect Wi-Fi or Ethernet before we touch it.",
                action: .openNetworkSettings
            )
        }
    }

    // MARK: - Row 4

    private static func undoNote(_ findings: PreflightFindings) -> PreflightRow {
        let title: LocalizedStringResource = "Room to save an undo note"
        guard let writability = findings.notesWritability else {
            return PreflightRow(check: .undoNote, state: .checking, title: title)
        }
        guard writability.isWritable else {
            return PreflightRow(
                check: .undoNote, state: .unsatisfied, title: title,
                finding: "RDMALink can't write its notes folder, so it couldn't put things back afterwards. It won't change anything it can't undo.",
                action: .showTheNotesFolder
            )
        }
        return PreflightRow(
            check: .undoNote, state: .satisfied, title: title,
            finding: "RDMALink can save its notes, so anything it changes can be put back."
        )
    }

    // MARK: - The disabled-Continue reason

    /// §S3's five reasons, in row order. Only an *unsatisfied* check prints
    /// one: a check that is still running greys `Continue` and says nothing,
    /// because there is nothing yet to tell the user to do.
    private static func reason(
        rows: [PreflightRow], _ findings: PreflightFindings
    ) -> LocalizedStringResource? {
        for row in rows where row.state == .unsatisfied {
            switch row.check {
            case .oneCable:
                return findings.isLoopedBackIntoThisMac
                    ? "Unplug one end of that cable to continue."
                    : "Unplug one of the two cables to continue."
            case .nothingMounted:
                guard let volume = findings.mountedThunderboltVolumes?.first else { return nil }
                return "Eject \(volume) to continue."
            case .anotherRoute:
                return "Connect Wi-Fi or Ethernet to continue."
            case .undoNote:
                return "RDMALink needs somewhere to save its notes before it can continue."
            }
        }
        return nil
    }
}
