//
//  WizardRefusal.swift
//
//  Every refusal the set-up assistant can raise, as one shape (UX_SPEC §6.1):
//  inline in the working area, a hierarchical symbol in `.secondary` or
//  `.orange`, a headline that names the situation, one short paragraph of why,
//  and a button row whose primary is always a real action.
//
//  Pure values. Nothing here reads the world or performs an action: the
//  builders are functions of observed state and the buttons are intents the
//  view hands back. That is rule 4 of docs/ARCHITECTURE.md — every refusal is
//  a pure function — carried into the presentation layer, where it is also the
//  only way the strings stay checkable against the spec.
//
//  There is no override anywhere in this file. No "Continue Anyway", no "I
//  understand the risks", no modifier key.
//

import Foundation
import RDMALinkCore

/// A button the assistant can offer — on a refusal, on a check row, or in
/// Identify. The view supplies the behaviour; the title comes from the spec
/// and lives here, so the copy is checkable in one place.
enum WizardAction: String, Sendable, Equatable, Hashable, Identifiable, CaseIterable {
    case showThunderboltPorts
    case checkAgain
    case copyDetails
    case back
    case done
    case tryAgain
    case showInFinder
    case showNotesInFinder
    case openNetworkSettings
    case openUsersAndGroups
    case quitSystemSettings
    case showProfile
    case copyDetailsForIT
    case chooseAnotherPort
    case takeAnotherLook
    case chooseFromList
    case useThisPort
    case identifyAgain
    case identifyPort
    case cancel
    case `continue`

    var id: String { rawValue }

    /// §1.3 rule 1: Title Case for buttons.
    var title: LocalizedStringResource {
        switch self {
        case .showThunderboltPorts: "Show Thunderbolt Ports"
        case .checkAgain: "Check Again"
        case .copyDetails: "Copy Details"
        case .back: "Back"
        case .done: "Done"
        case .tryAgain: "Try Again"
        case .showInFinder: "Show in Finder"
        case .showNotesInFinder: "Show Notes in Finder"
        case .openNetworkSettings: "Open Network Settings"
        case .openUsersAndGroups: "Open Users & Groups"
        case .quitSystemSettings: "Quit System Settings"
        case .showProfile: "Show Profile"
        case .copyDetailsForIT: "Copy Details for IT"
        case .chooseAnotherPort: "Choose Another Port"
        case .takeAnotherLook: "Take Another Look"
        case .chooseFromList: "Choose from List"
        case .useThisPort: "Use This Port"
        case .identifyAgain: "Identify Again"
        case .identifyPort: "Identify Port…"
        case .cancel: "Cancel"
        case .continue: "Continue"
        }
    }

    /// `Copy Details` carries the technical names regardless of the "Show
    /// technical names" toggle (§6.1 rule 8), so the view routes it to the
    /// diagnostics payload rather than to a handler of its own.
    var isCopyDetails: Bool { self == .copyDetails || self == .copyDetailsForIT }
}

/// One refusal, ready to draw.
struct WizardRefusal: Sendable, Equatable, Identifiable {
    /// The spec number, e.g. `R5`. The view picks nothing from it — it is here
    /// so a refusal can be identified in a test and in the diagnostics.
    var code: String
    /// A hierarchical SF Symbol. Never a filled red badge (§6.1 rule 2).
    var symbol: String
    var isAttention: Bool
    var headline: LocalizedStringResource
    var body: LocalizedStringResource
    /// The actual finding, in the same words the rest of the app uses.
    var detail: LocalizedStringResource?
    /// §6.1 rule 7: a refusal that follows a partial write states the rollback
    /// first, above everything else.
    var rollbackLine: LocalizedStringResource?
    /// The first button is the default (§8.3: `.keyboardShortcut(.defaultAction)`).
    /// An empty row is a refusal that watches itself and clears (§6.1 rule 5).
    var actions: [WizardAction]
    /// BSD names the model should ring.
    var subjects: [String]
    /// §6.1 rule 5: where the condition is physical the refusal has no button
    /// and says so instead.
    var watchingLine: LocalizedStringResource?

    var id: String { code }

    init(
        code: String,
        symbol: String = "exclamationmark.circle",
        isAttention: Bool = false,
        headline: LocalizedStringResource,
        body: LocalizedStringResource,
        detail: LocalizedStringResource? = nil,
        rollbackLine: LocalizedStringResource? = nil,
        actions: [WizardAction] = [],
        subjects: [String] = [],
        watchingLine: LocalizedStringResource? = nil
    ) {
        self.code = code
        self.symbol = symbol
        self.isAttention = isAttention
        self.headline = headline
        self.body = body
        self.detail = detail
        self.rollbackLine = rollbackLine
        self.actions = actions
        self.subjects = subjects
        self.watchingLine = watchingLine
    }
}

/// §6.1's shared strings, written once so every refusal reads the same.
enum WizardRefusalStrings {
    static let nothingChanged: LocalizedStringResource = "Nothing has been changed."
    static let keepWatching: LocalizedStringResource =
        "RDMALink is watching — once this is sorted it carries straight on."
    /// Rule 9: a self-clearing refusal cross-fades to this one line and the
    /// flow carries on by itself.
    static let sortedCarryingOn: LocalizedStringResource = "Sorted. Carrying on."
}

/// The builders. One per spec refusal, each a pure function of observed state.
enum WizardRefusals {

    // MARK: - R3 — a cable is in a USB-only port

    /// The hard refusal on click in Choose a port. (The hub's non-blocking tip
    /// is `USBPortTip`, which the hub already owns.)
    static func usbPort(isMacMini: Bool) -> WizardRefusal {
        WizardRefusal(
            code: "R3",
            symbol: "cable.connector.horizontal",
            headline: "That's a USB port",
            body: isMacMini
                ? "The two ports at the front of a Mac mini carry USB, not Thunderbolt. The three on the back are the Thunderbolt ones."
                : "The front ports on this Mac carry USB, not Thunderbolt. Move the cable to one of the four Thunderbolt ports on the back and RDMALink will follow along.",
            actions: [.showThunderboltPorts, .checkAgain]
        )
    }

    // MARK: - R5 — this is how you're connected right now

    static let onlyRouteIsThunderbolt = WizardRefusal(
        code: "R5",
        isAttention: true,
        headline: "This is how you're connected right now",
        body: "Right now, Thunderbolt is the only way this Mac is reachable. Removing a port from a bridge can briefly interrupt the whole bridge — not just that one port — so this would cut you off half-way through. Connect Wi-Fi or Ethernet first, then come straight back.",
        actions: [.openNetworkSettings, .checkAgain],
        watchingLine: WizardRefusalStrings.keepWatching
    )

    // MARK: - R6, R7 — permission

    static let notAnAdministrator = WizardRefusal(
        code: "R6",
        headline: "This account can't change network settings",
        body: "macOS only lets an administrator rearrange network connections. Log in as an administrator, or ask someone who is to sit down for thirty seconds — that's genuinely all it takes. The name and password don't have to be yours.",
        actions: [.openUsersAndGroups, .back]
    )

    static let noAuthorization = WizardRefusal(
        code: "R7",
        symbol: "lock",
        headline: "No changes were made",
        body: "Without an administrator's permission RDMALink can't touch the bridge — and it didn't. Everything is exactly as it was. Try again whenever you're ready; the name and password don't have to be yours.",
        actions: [.tryAgain, .back]
    )

    // MARK: - R8, R10, R11 — after a write

    static let credentialExpired = WizardRefusal(
        code: "R8",
        headline: "That took a moment too long",
        body: "The permission macOS gives RDMALink lasts about thirty seconds, and it ran out before every change went through — so RDMALink put the port back exactly as it was. Try again; it usually flies through.",
        rollbackLine: WizardRefusalStrings.nothingChanged,
        actions: [.tryAgain, .done, .copyDetails]
    )

    static let rolledBack = WizardRefusal(
        code: "R10",
        symbol: "arrow.uturn.backward.circle",
        headline: "Put back, safely",
        body: "The new service wouldn't create, so RDMALink returned the port to Thunderbolt Bridge. Nothing has been left half-done, and it checked before telling you.",
        rollbackLine: WizardRefusalStrings.nothingChanged,
        actions: [.tryAgain, .done, .copyDetails]
    )

    /// The most serious state in the app, and the only one that asks the user
    /// to do something by hand. Its findings block is always shown, with the
    /// technical names in it regardless of the toggle.
    static func rollbackFailed(
        positionName: String,
        bridgeDisplayName: String,
        bridgeBSDName: String,
        membersBefore: [String],
        membersNow: [String],
        portBSDName: String
    ) -> WizardRefusal {
        WizardRefusal(
            code: "R11",
            isAttention: true,
            headline: "One thing needs your hand",
            body: "RDMALink took \(positionName) out of Thunderbolt Bridge, then couldn't finish — and couldn't put it back either. Nothing is broken, but the port is currently in neither place. Open System Settings, under Network, choose Manage Virtual Interfaces, open Thunderbolt Bridge, and add the port back. Here is exactly how it was.",
            detail: "Bridge: \(bridgeDisplayName) (\(bridgeBSDName)) · Members before: \(membersBefore.formatted(.list(type: .and))) · Members now: \(membersNow.formatted(.list(type: .and))) · The port to add back: \(portBSDName) — \(positionName)",
            actions: [.openNetworkSettings, .copyDetails, .checkAgain],
            subjects: [portBSDName]
        )
    }

    // MARK: - R9, R12, R13, R14, R15, R16, R17

    static func portStillBridged(
        positionName: String, bridgeName: String, portBSDName: String
    ) -> WizardRefusal {
        WizardRefusal(
            code: "R9",
            headline: "macOS wouldn't let go of that port",
            body: "RDMALink couldn't remove \(positionName) from \(bridgeName), so it stopped and changed nothing at all. You can take it out by hand in System Settings, under Network — open the three-dot menu, choose Manage Virtual Interfaces, open Thunderbolt Bridge and remove just this port. Come back after that and RDMALink will offer to adopt it.",
            actions: [.openNetworkSettings, .checkAgain, .copyDetails],
            subjects: [portBSDName]
        )
    }

    static func networkLockHeld(bySystemSettings: Bool) -> WizardRefusal {
        WizardRefusal(
            code: "R12",
            headline: "Something else has the network open",
            body: "System Settings, or another app, is editing the network configuration right now. RDMALink won't write over it — two things writing network settings at once is how configurations get mangled. Close that and RDMALink will try again.",
            actions: bySystemSettings
                ? [.checkAgain, .quitSystemSettings, .back]
                : [.checkAgain, .back]
        )
    }

    /// Replaces the whole of S5's working area. Identify, the model and the
    /// port list all keep working, so the app is still a useful map.
    static let managedByProfile = WizardRefusal(
        code: "R13",
        symbol: "building.2",
        headline: "This Mac's network settings are managed for you",
        body: "A configuration profile on this Mac owns the network setup, and it will quietly put back anything RDMALink changes. It'd rather tell you now than have you wonder later why the link keeps vanishing. Whoever manages this Mac can make an exception for Thunderbolt.",
        actions: [.showProfile, .copyDetailsForIT, .back]
    )

    /// The refusal that protects every other promise in the app, and it comes
    /// before the password, not after.
    static func cannotSaveUndoNote(_ writability: BaselineWritability?) -> WizardRefusal {
        WizardRefusal(
            code: "R14",
            isAttention: true,
            headline: "RDMALink can't write down how things are right now",
            body: "RDMALink's notes live in your Library folder, and it can't save there at the moment — which means it couldn't put things back afterwards. It won't change anything it can't undo.",
            detail: detail(for: writability),
            actions: [.checkAgain, .showNotesInFinder, .copyDetails]
        )
    }

    private static func detail(for writability: BaselineWritability?) -> LocalizedStringResource? {
        switch writability {
        case .notWritable:
            return "The folder isn't writable."
        case .writable, nil:
            return nil
        }
    }

    static func unreadableBridge(positionName: String, portBSDName: String) -> WizardRefusal {
        WizardRefusal(
            code: "R15",
            headline: "There's a bridge here RDMALink can't make sense of",
            body: "\(positionName) belongs to a bridge whose settings RDMALink can't read properly, and a port has to be out of every bridge — even one that isn't switched on — before it can carry RDMA. It won't guess at this. Have a look in Network settings, under Manage Virtual Interfaces, and it'll check again when you're back.",
            actions: [.openNetworkSettings, .checkAgain, .copyDetails],
            subjects: [portBSDName]
        )
    }

    static func foreignService(positionName: String, portBSDName: String) -> WizardRefusal {
        WizardRefusal(
            code: "R16",
            headline: "This port already has a setup RDMALink didn't make",
            body: "There's a service on \(positionName) with a fixed IPv4 address on it. It isn't RDMALink's and it isn't what a link needs, and RDMALink won't quietly rewrite something you or someone else set up on purpose. Remove it in Network settings if it's stale, or choose another port.",
            actions: [.openNetworkSettings, .chooseAnotherPort, .copyDetails],
            subjects: [portBSDName]
        )
    }

    static let arrangementChanged = WizardRefusal(
        code: "R17",
        symbol: "arrow.triangle.2.circlepath",
        headline: "Something moved",
        body: "A cable changed while this was on screen, so what you just read isn't true any more. RDMALink stopped before doing anything rather than act on old information.",
        rollbackLine: WizardRefusalStrings.nothingChanged,
        actions: [.takeAnotherLook]
    )

    // MARK: - R26 — every Thunderbolt port is occupied

    /// "A dead end handled kindly at Choose a port, not a refusal." It has no
    /// buttons: the card watches and clears itself.
    ///
    /// §6.2 R26's body opens with an illustration — "There's a display in
    /// Back, far left and docks in the other three" — which names four ports
    /// on a six-port Mac and asserts device kinds nothing measured. §1.3 rule
    /// 10 forbids exactly that, and R26's own shape gives the real finding a
    /// place, so the finding goes in `detail` and the body is the spec's
    /// second sentence, which stands on its own.
    /// **Owed from the spec owner:** a finding-free first sentence.
    static func everyPortOccupied(detail: LocalizedStringResource?) -> WizardRefusal {
        WizardRefusal(
            code: "R26",
            symbol: "cable.connector",
            headline: "Every Thunderbolt port has something in it",
            body: "You can still prepare any of them — or free up the one you want for the link and RDMALink will be ready.",
            detail: detail,
            watchingLine: WizardRefusalStrings.keepWatching
        )
    }

    // MARK: - R27 — routing, not refusing

    /// A port that is already ready: the row offers `Restore…` and the working
    /// area prints one line. Not a refusal — there is no closed door here.
    static let alreadyALink: LocalizedStringResource =
        "This one's already a link. Want to see how it's doing?"

    /// A port somebody set up by hand: the app routes silently to Adopt.
    static let alreadyDoneProperly: LocalizedStringResource =
        "This one's already done — and done properly. Here's what RDMALink found."
}

// MARK: - Core's refusals

extension LocalizedStringResource {
    /// A finished sentence Core produced.
    ///
    /// Core's refusals carry `String`, already interpolated with the port and
    /// volume names. Wrapping it as a resource keeps one type flowing through
    /// the views, and it degrades to exactly the English Core produced when no
    /// catalogue entry matches.
    init(core text: String) {
        self.init(String.LocalizationValue(text))
    }
}

extension WizardRefusal {
    /// A Core refusal, given the symbol and the button row the spec gives its
    /// number. Nothing about the copy is re-decided here: Core owns the
    /// headline, the body and the finding, and this owns only what §6.2 says
    /// the primary action is.
    init(_ refusal: Refusal) {
        self.init(
            code: refusal.code.rawValue,
            symbol: Self.symbol(for: refusal.code),
            isAttention: Self.isAttention(refusal.code),
            headline: LocalizedStringResource(core: refusal.headline),
            body: LocalizedStringResource(core: refusal.body),
            detail: refusal.detail.map { LocalizedStringResource(core: $0) },
            rollbackLine: Self.rollbackLine(for: refusal.code),
            actions: Self.actions(for: refusal.code),
            subjects: refusal.subjects,
            watchingLine: Self.actions(for: refusal.code).isEmpty
                ? WizardRefusalStrings.keepWatching : nil)
    }

    private static func symbol(for code: RefusalCode) -> String {
        switch code {
        case .twoMacsConnected, .loopedBackIntoThisMac: "cable.connector"
        case .volumeMounted: "externaldrive"
        case .rolledBack: "arrow.uturn.backward.circle"
        case .rollbackFailed: "hand.raised"
        case .topologyChanged: "arrow.triangle.2.circlepath"
        default: "exclamationmark.circle"
        }
    }

    private static func isAttention(_ code: RefusalCode) -> Bool {
        switch code {
        case .onlyRouteIsThunderbolt, .baselineUnwritable, .rollbackFailed: true
        default: false
        }
    }

    /// §6.1 rule 7: a refusal that follows a partial write states the rollback
    /// first, before explaining anything else.
    private static func rollbackLine(for code: RefusalCode) -> LocalizedStringResource? {
        switch code {
        case .rolledBack, .topologyChanged, .credentialExpired:
            WizardRefusalStrings.nothingChanged
        default: nil
        }
    }

    /// §6.2's button rows. The first is the default; an empty row is a refusal
    /// that watches itself and clears, which has no button at all.
    private static func actions(for code: RefusalCode) -> [WizardAction] {
        switch code {
        // R1 and R2: "Buttons: none; self-clearing."
        case .twoMacsConnected, .loopedBackIntoThisMac: []
        case .volumeMounted: [.showInFinder]
        case .onlyRouteIsThunderbolt: [.openNetworkSettings, .checkAgain]
        case .portStillInBridge: [.openNetworkSettings, .checkAgain, .copyDetails]
        case .rolledBack: [.tryAgain, .done, .copyDetails]
        case .credentialExpired: [.tryAgain, .done, .copyDetails]
        // §6.2 R12's `Quit System Settings` appears "only when System Settings
        // is the holder", which `SCPreferencesLock` does not report, so the
        // two actions that are always honest stand.
        // **Owed from Core:** which process holds the configuration.
        case .networkBusy: [.checkAgain, .back]
        case .rollbackFailed: [.openNetworkSettings, .copyDetails, .checkAgain]
        case .baselineUnwritable: [.checkAgain, .showNotesInFinder, .copyDetails]
        case .bridgeUnreadable: [.openNetworkSettings, .checkAgain, .copyDetails]
        case .foreignService: [.openNetworkSettings, .chooseAnotherPort, .copyDetails]
        case .topologyChanged: [.takeAnotherLook]
        // R19–R21 and R28–R30 are raised inside the Restore and Adopt sheets,
        // which own their own button rows (§6.1 rule 1's one exception). If one
        // reaches the assistant it gets the two actions every refusal can
        // honour rather than a guess at the spec's row.
        case .undoNoteMissing, .notBackInBridge, .originalBridgeGone,
            .createdServiceEdited, .noBridgeToReturnTo, .noteIsAReturnRecord:
            [.checkAgain, .copyDetails]
        // §6.2 R31: "Buttons: none." It never reaches the assistant — an
        // unrecognized Mac has no way into S3 (§S4) — and if one did, the
        // only honest button is the way out §6.1 rule 10 leaves on every
        // refusal. Not an empty row: that would print "RDMALink is watching",
        // and R31 never clears.
        case .macNotRecognized: [.back]
        }
    }
}
