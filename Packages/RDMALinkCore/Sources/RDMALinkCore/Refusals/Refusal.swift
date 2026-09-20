import Foundation

/// The spec number of a refusal, so the UI can pick its symbol, its buttons and
/// its recovery behaviour without re-deriving them from the text.
///
/// See `docs/UX_SPEC.md` § 6.2. Only the numbers the network module can raise
/// are listed; the rest belong to modules that observe other things.
public enum RefusalCode: String, Sendable, Equatable, CaseIterable {
    /// Two Macs are connected (loop risk).
    case twoMacsConnected = "R1"
    /// This is how you're connected right now — Thunderbolt is the only route.
    case onlyRouteIsThunderbolt = "R5"
    /// macOS wouldn't release the port from the bridge. A **precondition**:
    /// it is only ever raised before anything has been written.
    case portStillInBridge = "R9"
    /// The service couldn't be created; the port was put back.
    case rolledBack = "R10"
    /// The rollback itself failed — the port is in neither place.
    case rollbackFailed = "R11"
    /// RDMALink can't save its undo note.
    case baselineUnwritable = "R14"
    /// This port already has a setup RDMALink didn't make.
    case foreignService = "R16"
    /// The service RDMALink created has been edited since, so Restore will not
    /// delete it.
    ///
    /// **Proposed, not yet in UX_SPEC §6.2.** The spec's numbered refusals stop
    /// at R27 and none of them covers "RDMALink's own service is no longer the
    /// one it made". The strings below are written in the spec's voice and are
    /// owed a review by the spec owner before ML2 ships.
    case createdServiceEdited = "R28"
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

    public init(bsdName: String, positionName: String, hasLinkedMac: Bool = false) {
        self.bsdName = bsdName
        self.positionName = positionName
        self.hasLinkedMac = hasLinkedMac
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
