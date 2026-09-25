import Foundation

/// The spec number of a refusal, so the UI can pick its symbol, its buttons and
/// its recovery behaviour without re-deriving them from the text.
///
/// See `docs/UX_SPEC.md` § 6.2. Only the numbers the network module can raise
/// are listed; the rest belong to modules that observe other things.
public enum RefusalCode: String, Sendable, Equatable, CaseIterable {
    /// Two Macs are connected (loop risk).
    case twoMacsConnected = "R1"
    /// Both ends of one cable are in this Mac. Blocks preflight; self-clearing.
    case loopedBackIntoThisMac = "R2"
    /// Something is still mounted over a Thunderbolt link. Blocks preflight
    /// and blocks Restore.
    case volumeMounted = "R4"
    /// This is how you're connected right now — Thunderbolt is the only route.
    case onlyRouteIsThunderbolt = "R5"
    /// The permission expired mid-burst, so the port was put back.
    case credentialExpired = "R8"
    /// macOS wouldn't release the port from the bridge. A **precondition**:
    /// it is only ever raised before anything has been written.
    case portStillInBridge = "R9"
    /// The service couldn't be created; the port was put back.
    case rolledBack = "R10"
    /// The rollback itself failed — the port is in neither place.
    case rollbackFailed = "R11"
    /// System Settings, or another app, holds the network configuration.
    case networkBusy = "R12"
    /// RDMALink can't save its undo note.
    case baselineUnwritable = "R14"
    /// There's a bridge here RDMALink can't read. Blocks review for that port.
    case bridgeUnreadable = "R15"
    /// This port already has a setup RDMALink didn't make.
    case foreignService = "R16"
    /// The arrangement changed while the review was on screen.
    case topologyChanged = "R17"
    /// The undo note is missing or unreadable, at Restore.
    case undoNoteMissing = "R19"
    /// The service is gone but the bridge is not listing the port yet. The
    /// undo note is **kept**.
    case notBackInBridge = "R20"
    /// The bridge the port came from doesn't exist any more, at Restore.
    case originalBridgeGone = "R21"
    /// The service RDMALink created has been edited since, so Restore will not
    /// delete it. The same number covers its other body: that service has
    /// gone and one set up by hand stands in its place, which Restore will
    /// not delete either.
    case createdServiceEdited = "R28"
    /// There is no Thunderbolt Bridge to return a standalone port to, and
    /// RDMALink never creates one. The copy is §S10's no-bridge form.
    case noBridgeToReturnTo = "R29"
    /// The note is a **return record** (§7.5): it says only that RDMALink put
    /// the port back in a bridge, so there is nothing for Restore to undo.
    /// Reached only from the command line or a stale sheet — the hub never
    /// offers `Restore…` for one. The note is kept and nothing is written.
    /// The same number covers an **adopted note** (§7.3, §6.2 R30's second
    /// form): no bridge history, nothing to put back, the port keeps its
    /// setup. The two forms have different bodies and button rows. Only the
    /// command line ever shows the adopted form: the app's Restore sheet
    /// sends an adopted note to Return to Bridge before it asks for a preview.
    case noteIsAReturnRecord = "R30"
    /// Neither rule in UX_SPEC §4.7 recognizes this Mac. Read-only mode, not
    /// an error: every operation refuses with it **first**, so nothing that
    /// writes — notes included — runs on a Mac RDMALink does not know.
    case macNotRecognized = "R31"
}

/// A refusal: a situation the app names, explains and will not step around.
///
/// Every refusal in the spec is a pure function over observed state, with a
/// test, and there is no override anywhere in the app
/// (`docs/ARCHITECTURE.md`, rule 4). The headline, body and detail are the
/// spec's own strings; buttons and recovery are the UI's to supply from
/// ``code``.
public struct Refusal: Error, Sendable, Equatable {
    public var code: RefusalCode
    /// Names the situation. Never scolds, never says "Error".
    public var headline: String
    /// One short paragraph of plain-language why, including the consequence.
    public var body: String
    /// The actual finding, in the same words the rest of the app uses.
    public var detail: String?
    /// BSD names of the ports this refusal is about, so the model can ring them.
    public var subjects: [String]

    public init(
        code: RefusalCode,
        headline: String,
        body: String,
        detail: String? = nil,
        subjects: [String] = []
    ) {
        self.code = code
        self.headline = headline
        self.body = body
        self.detail = detail
        self.subjects = subjects
    }
}

/// The part of a Thunderbolt port the refusals need.
///
/// `Inventory` maps its `ThunderboltPort` onto this so the refusals stay pure
/// functions over plain values and can be tested without hardware.
public struct ObservedPort: Sendable, Equatable {
    /// The BSD name, e.g. `en6`.
    public var bsdName: String
    /// The position name the whole app uses, e.g. "Back, far left".
    public var positionName: String
    /// True when another Mac is on the end of this cable (`IOLinkStatus` 3).
    public var hasLinkedMac: Bool
    /// The BSD names of every bridge this port is a member of, whether the
    /// kernel or the saved network settings say so. R1 counts a linked Mac
    /// only through a bridge: a standalone port forwards nothing, so two
    /// cables on two standalone ports cannot loop.
    public var bridges: [String]
    /// The BSD name of the receptacle on this Mac the same cable comes back
    /// into, from ``ThunderboltPort/loopedBackTo`` — R2's input. `nil` when
    /// the cable goes somewhere else, or when this Mac could not say.
    public var loopedBackTo: String?

    public init(
        bsdName: String,
        positionName: String,
        hasLinkedMac: Bool = false,
        bridges: [String] = [],
        loopedBackTo: String? = nil
    ) {
        self.bsdName = bsdName
        self.positionName = positionName
        self.hasLinkedMac = hasLinkedMac
        self.bridges = bridges
        self.loopedBackTo = loopedBackTo
    }
}

/// Joins names the way the spec's copy does: "A", "A and B", "A, B and C".
func englishList(_ items: [String]) -> String {
    switch items.count {
    case 0: return ""
    case 1: return items[0]
    case 2: return items[0] + " and " + items[1]
    default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }
}

/// Counts as the copy writes them: in words, in a button or a counter as in a
/// sentence — `Set Up Two Ports`, "Two ports selected", "Setting up three
/// ports" (UX_SPEC §1.3 rule 1).
///
/// The one `.spellOut` formatter. Core's copy uses it, and so does the app's
/// (`ThisMacPresentation.spelledOut`), so one count is never written two ways.
/// It is pinned to English, the language every sentence around it is written
/// in: until the app is genuinely localized, a count spelled in the user's
/// locale would land a French "deux" inside an English button.
public enum Counts {
    public static let english = Locale(identifier: "en_US")

    /// `two`, or `Two` at the head of a sentence or in a Title Case button.
    public static func spelledOut(_ value: Int, capitalized: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = english
        guard let words = formatter.string(from: NSNumber(value: value)) else {
            return String(value)
        }
        guard capitalized else { return words }
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
