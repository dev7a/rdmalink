import Foundation

/// One receptacle, as a whole-flow operation needs it.
///
/// ``ObservedPort`` is what the refusals see and carries no receptacle index;
/// the undo note needs one, and R4 needs the port's link-local addresses. This
/// is the one value that carries all three, so an operation never has to reach
/// back into `Inventory` mid-burst.
public struct OperationPort: Sendable, Equatable {
    /// The kernel interface name, e.g. `en6`.
    public var bsdName: String
    /// `IOLocation`, 1-based. Recorded in the undo note.
    public var receptacle: Int
    /// The position name the whole app uses, e.g. "Back, far left".
    public var positionName: String
    /// What is physically plugged in. R1 reads the linked-Mac case out of it,
    /// and S5's warning rows need the other three.
    public var link: LinkState
    /// `fe80::` addresses on this interface, without the `%scope` suffix.
    /// R4 matches a mounted volume's source against these.
    public var linkLocalAddresses: [String]

    public init(
        bsdName: String,
        receptacle: Int,
        positionName: String,
        link: LinkState = .empty,
        linkLocalAddresses: [String] = []
    ) {
        self.bsdName = bsdName
        self.receptacle = receptacle
        self.positionName = positionName
        self.link = link
        self.linkLocalAddresses = linkLocalAddresses
    }

    public init(_ port: ThunderboltPort) {
        self.init(
            bsdName: port.bsdName,
            receptacle: port.receptacle,
            positionName: port.positionName,
            link: port.link,
            linkLocalAddresses: port.linkLocal)
    }

    /// True when another Mac is on the end of this cable — R1's input.
    public var hasLinkedMac: Bool { link == .macLinked }

    /// This port as the refusal functions see it.
    public var observed: ObservedPort {
        ObservedPort(bsdName: bsdName, positionName: positionName, hasLinkedMac: hasLinkedMac)
    }
}

/// Where one checklist row is, in the live list of UX_SPEC §S6 phase B.
public enum StepState: Sendable, Equatable {
    /// `circle.dotted`.
    case pending
    /// A small `ProgressView`.
    case running
    /// `checkmark.circle.fill`.
    case done
    /// UX_SPEC §S6: "a step failed → automatic rollback, checklist reverses
    /// with a returning symbol". The row is being put back right now; it
    /// returns to ``pending`` once it has been.
    case reversing
}

/// One row of the apply or restore checklist.
///
/// The three strings per row are the spec's own, from the §S6 table and the
/// §S10 step list. Nothing here is assembled out of fragments: a row that
/// names a bridge or a service takes the whole name as one placeholder.
public enum OperationStep: Sendable, Equatable {

    // MARK: UX_SPEC §S6 — setting up

    /// Step 1. The gate that protects every other promise, and it goes first.
    case saveUndoNote
    /// Step 2, once per bridge the port has to leave.
    case leaveBridge(named: String)
    /// Step 3.
    case createService(named: String)
    /// Step 4.
    case setAddresses
    /// Step 5.
    case checkOutOfEveryBridge

    // MARK: UX_SPEC §S10 — restoring

    /// The service RDMALink made, by identifier.
    case deleteCreatedService(named: String)
    /// Back into a bridge the undo note recorded.
    case rejoinBridge(named: String)
    /// Never an assumption: an explicit, visible step.
    case checkBackInBridge

    // MARK: UX_SPEC §7.5 — returning a standalone port to the bridge

    /// A standalone service RDMALink did not make.
    case deleteForeignService(named: String)
    /// Into the existing Thunderbolt Bridge. RDMALink never creates one.
    case joinBridge(named: String)
    case checkInBridge

    /// `circle.dotted`, before anything has run.
    public var pending: String {
        switch self {
        case .saveUndoNote:
            return "Save how to undo this"
        case let .leaveBridge(named):
            return "Remove from \(named)"
        case .createService:
            return "Create the RDMA service"
        case .setAddresses:
            return "Turn IPv4 off, IPv6 to link-local"
        case .checkOutOfEveryBridge:
            return "Check it's out of every bridge"
        case let .deleteCreatedService(named):
            return "Delete the service \(named)"
        case let .rejoinBridge(named):
            return "Add the port back to \(named)"
        case .checkBackInBridge:
            return "Check that it really is back, then forget the whole thing"
        case let .deleteForeignService(named):
            return "Delete the service \(named) — RDMALink didn't make this one, "
                + "and a bridge member can't keep its own service"
        case let .joinBridge(named):
            return "Add the port to \(named)"
        case .checkInBridge:
            return "Check that it really is in the bridge"
        }
    }

    /// A small `ProgressView`, while the write is in flight.
    public var running: String {
        switch self {
        case .saveUndoNote:
            return "Saving how to undo this…"
        case let .leaveBridge(named):
            return "Removing from \(named)…"
        case .createService:
            return "Creating the service…"
        case .setAddresses:
            return "Setting the addresses…"
        case .checkOutOfEveryBridge:
            return "Checking every bridge…"
        case .deleteCreatedService, .deleteForeignService:
            return "Deleting the service…"
        case let .rejoinBridge(named), let .joinBridge(named):
            return "Returning the port to \(named)…"
        case .checkBackInBridge, .checkInBridge:
            return "Checking that it's back…"
        }
    }

    /// `checkmark.circle.fill`, once the write has landed.
    ///
    /// UX_SPEC gives a done string only for the five set-up steps (§S6's
    /// table). §S10 gives restore its row labels and its three running lines
    /// and stops there, so the restore and return rows settle back to their
    /// own label rather than to a sentence this app invented. The gap is the
    /// spec's to close.
    public var done: String {
        switch self {
        case .saveUndoNote:
            return "Saved"
        case let .leaveBridge(named):
            return "Removed from \(named)"
        case let .createService(named):
            return "Created \(named)"
        case .setAddresses:
            return "IPv4 off, IPv6 link-local only"
        case .checkOutOfEveryBridge:
            return "Out of every bridge"
        case .deleteCreatedService, .rejoinBridge, .checkBackInBridge,
             .deleteForeignService, .joinBridge, .checkInBridge:
            return pending
        }
    }

    /// The row's text in one state, so a caller can drive the list from this
    /// type alone.
    public func text(_ state: StepState) -> String {
        switch state {
        case .pending: return pending
        case .running: return running
        case .done: return done
        // §S6 gives the reversing rows a returning *symbol* and one status
        // line for the whole checklist — "Something didn't take. Putting the
        // port back exactly as it was…" — and no per-row sentence. The row
        // therefore returns to its own label rather than to one invented here.
        case .reversing: return pending
        }
    }
}

/// How an operation reports each checklist row as it happens.
///
/// Called synchronously, on the thread running the burst — the burst never
/// waits for the user and never asks a question, so this is a report and never
/// a decision point.
public typealias OperationProgress = (OperationStep, StepState) -> Void

/// The line printed under the last checkmark before the screen advances,
/// UX_SPEC §S6: **Done. That took 1.8 seconds.**
public enum OperationTiming {
    public static func completionLine(seconds: TimeInterval) -> String {
        "Done. That took \(String(format: "%.1f", max(0, seconds))) seconds."
    }
}
