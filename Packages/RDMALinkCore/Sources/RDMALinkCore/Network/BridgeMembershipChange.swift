import Foundation
import SystemConfiguration

/// What taking one port out of one bridge — or putting it back — would change.
public struct BridgeMembershipPlan: Sendable, Equatable {
    /// The port being moved.
    public var bsdName: String
    /// The bridge as it is right now, by kernel name.
    public var bridgeBSDName: String
    /// The name System Settings shows, when macOS offers one.
    public var bridgeDisplayName: String?
    /// The member list before, in the order found.
    public var membersBefore: [String]
    /// What the member list should be afterwards.
    public var membersAfter: [String]
    /// True when the bridge is already in the state asked for, so the burst
    /// has nothing to do here.
    public var isAlreadyDone: Bool
    /// The refusal to show instead of the plan, when there is one.
    public var refusal: Refusal?

    /// True when there is nothing in the way.
    public var canProceed: Bool { refusal == nil }

    public init(
        bsdName: String,
        bridgeBSDName: String,
        bridgeDisplayName: String? = nil,
        membersBefore: [String],
        membersAfter: [String],
        isAlreadyDone: Bool = false,
        refusal: Refusal? = nil
    ) {
        self.bsdName = bsdName
        self.bridgeBSDName = bridgeBSDName
        self.bridgeDisplayName = bridgeDisplayName
        self.membersBefore = membersBefore
        self.membersAfter = membersAfter
        self.isAlreadyDone = isAlreadyDone
        self.refusal = refusal
    }
}

/// Moves one port out of one bridge, or puts it back — the only two things
/// RDMALink ever does to a bridge (`docs/ARCHITECTURE.md`, rule 3).
///
/// This is the one door to the private `SCBridgeInterface*` mutators. It owns
/// the authorized session rather than taking a bare `SCPreferences`, because
/// the push those mutators need — `_SCBridgeInterfaceUpdateConfiguration` — is
/// the routine configd itself uses to realise a bridge change: it issues the
/// `SIOCSDRVSPEC` ioctls and the kernel has the result the moment it returns,
/// with no commit involved. A "dry run" that reached it would be a real
/// unbridging. So in ``AuthorizedSession/Mode/dryRun`` this type writes
/// nothing at all and only reports what the membership would become.
public struct BridgeMembershipChange: Sendable {
    /// Which way the one member moves.
    public enum Direction: Sendable, Equatable {
        /// Take the port out. The bridge itself is never removed, even when
        /// this empties it.
        case leave
        /// Put the port back where the undo note says it sat.
        case rejoin(position: Int?)
    }

    public let port: ObservedPort
    /// The bridge as the undo note records it, identifier included.
    public let bridge: BridgeMembership
    public let direction: Direction

    public init(port: ObservedPort, bridge: BridgeMembership, direction: Direction) {
        self.port = port
        self.bridge = bridge
        self.direction = direction
    }

    // MARK: - Preview

    /// What would change. Pure: it reads nothing and writes nothing.
    ///
    /// - Parameter bridges: every bridge as it is right now, from
    ///   ``BridgeSPI/bridges(in:)`` or ``BridgeSPI/activeBridges()``.
    public func preview(bridges: [BridgeSPI.Membership]) -> BridgeMembershipPlan {
        let live = bridges.first { $0.bsdName == bridge.bridgeName }
        let before = live?.members ?? bridge.members
        let isMember = before.contains(port.bsdName)
        let after: [String]
        let alreadyDone: Bool
        switch direction {
        case .leave:
            after = before.filter { $0 != port.bsdName }
            alreadyDone = !isMember
        case let .rejoin(position):
            if isMember {
                after = before
                alreadyDone = true
            } else {
                var members = before
                members.insert(port.bsdName,
                               at: min(max(position ?? members.count, 0), members.count))
                after = members
                alreadyDone = false
            }
        }
        return BridgeMembershipPlan(
            bsdName: port.bsdName,
            bridgeBSDName: live?.bsdName ?? bridge.bridgeName,
            bridgeDisplayName: live?.displayName ?? bridge.displayName,
            membersBefore: before,
            membersAfter: after,
            isAlreadyDone: alreadyDone,
            refusal: nil)
    }

    // MARK: - Perform

    /// Moves the member, inside the credential window, and reads the kernel
    /// back to see whether it agreed.
    ///
    /// Order: check the undo note is there and is about this port, resolve the
    /// bridge **by identifier**, take the lock, write, push, commit, apply,
    /// then verify through `ifconfig`. If the kernel did not do it, the change
    /// is rolled back and the refusal says so — R10 when the port is back where
    /// it was, R11 when it could not be put back. R9 is a precondition and is
    /// never raised from here: its copy promises nothing was changed.
    ///
    /// The session is left locked so the caller can keep the burst going, and
    /// must be ended by the caller.
    ///
    /// - Returns: the bridge's membership afterwards. In
    ///   ``AuthorizedSession/Mode/dryRun`` that is the projection, and nothing
    ///   has been written anywhere.
    @discardableResult
    public func perform(
        session: AuthorizedSession,
        baseline: BaselineToken,
        runner: CommandRunner = CommandRunner()
    ) throws -> BridgeSPI.Membership {
        guard baseline.portBSDName == port.bsdName else {
            throw Refusals.baselineUnwritable(
                detail: "The note that came back is about \(baseline.portBSDName), "
                    + "not \(port.bsdName).")
        }
        try BridgeSPI.requireMembershipEditing()
        let preferences = try session.preferences
        let resolved = try BridgeSPI.bridge(
            serviceIdentifier: bridge.serviceIdentifier,
            bsdName: bridge.bridgeName,
            in: preferences)
        let current = try BridgeSPI.describe(resolved)

        // The note's own member list is the proof that this is the bridge the
        // note is about: a `bridgeN` name freed by a delete and handed to a
        // different virtual interface would otherwise be edited as if it were.
        guard Set(current.members).isSubset(of: Set(bridge.members)) else {
            throw BridgeSPIError.notTheRecordedBridge(
                bridge: current.bsdName, members: current.members, recorded: bridge.members)
        }

        let projected = try projectedMembers(of: current)
        guard session.mode == .live else {
            return BridgeSPI.Membership(bsdName: current.bsdName,
                                        displayName: current.displayName,
                                        members: projected)
        }

        try session.lock()
        try write(direction, to: resolved, in: preferences, session: session)

        // A kernel that cannot be read is not a kernel that agreed: an
        // unreadable `ifconfig` falls into the rollback below rather than
        // leaving a membership change standing on an unverified claim.
        if let settled = (try? verified(bridgeBSDName: current.bsdName, runner: runner)) ?? nil {
            return settled
        }

        // The kernel did not do it. Put the membership back the way it was and
        // say which of the two things happened.
        let inverse: Direction = {
            switch direction {
            case .leave: return .rejoin(position: bridge.members.firstIndex(of: port.bsdName))
            case .rejoin: return .leave
            }
        }()
        let named = current.displayName ?? current.bsdName
        do {
            try write(inverse, to: resolved, in: preferences, session: session)
            let snapshot = try InterfaceSnapshot.read(using: runner)
            let membersNow = snapshot[current.bsdName]?.members ?? []
            guard membersNow.contains(port.bsdName) == (direction == .leave) else {
                throw Refusals.rollbackFailed(
                    port: port, bridgeBSDName: current.bsdName,
                    bridgeDisplayName: current.displayName,
                    membersBefore: bridge.members, membersNow: membersNow)
            }
            throw Refusals.rolledBack(
                port: port, bridgeName: named,
                cause: "macOS didn't actually let go of the port")
        } catch let refusal as Refusal {
            throw refusal
        } catch {
            let membersNow = (try? InterfaceSnapshot.read(using: runner))?[current.bsdName]?.members ?? []
            throw Refusals.rollbackFailed(
                port: port, bridgeBSDName: current.bsdName,
                bridgeDisplayName: current.displayName,
                membersBefore: bridge.members, membersNow: membersNow)
        }
    }

    // MARK: - Private

    /// What the member list becomes, or why it cannot.
    private func projectedMembers(of current: BridgeSPI.Membership) throws -> [String] {
        switch direction {
        case .leave:
            let remaining = current.members.filter { $0 != port.bsdName }
            guard remaining.count == current.members.count - 1 else {
                throw BridgeSPIError.memberNotFound(bsdName: port.bsdName,
                                                    bridge: current.bsdName)
            }
            return remaining
        case let .rejoin(position):
            guard !current.members.contains(port.bsdName) else {
                throw BridgeSPIError.alreadyMember(bsdName: port.bsdName,
                                                   bridge: current.bsdName)
            }
            var members = current.members
            members.insert(port.bsdName,
                           at: min(max(position ?? members.count, 0), members.count))
            return members
        }
    }

    /// One membership write, pushed to the kernel and committed. Only ever
    /// reached in ``AuthorizedSession/Mode/live``.
    private func write(
        _ direction: Direction,
        to bridge: SCBridgeInterfaceRef,
        in preferences: SCPreferences,
        session: AuthorizedSession
    ) throws {
        switch direction {
        case .leave:
            try BridgeSPI.removeMember(bsdName: port.bsdName, from: bridge)
        case let .rejoin(position):
            try BridgeSPI.addMember(bsdName: port.bsdName, to: bridge,
                                    at: position, in: preferences)
        }
        if BridgeSPI.availability.canUpdateConfiguration {
            try BridgeSPI.updateConfiguration(in: preferences)
        }
        try session.commit()
        try session.apply()
    }

    /// The kernel's own answer, read back through `ifconfig`. `nil` when it
    /// does not yet agree with what was asked for.
    private func verified(
        bridgeBSDName: String,
        runner: CommandRunner
    ) throws -> BridgeSPI.Membership? {
        let snapshot = try InterfaceSnapshot.read(using: runner)
        let isMember = snapshot.bridges(containing: port.bsdName).contains(bridgeBSDName)
        let wanted = direction != .leave
        guard isMember == wanted else { return nil }
        return BridgeSPI.Membership(
            bsdName: bridgeBSDName,
            displayName: bridge.displayName,
            members: snapshot[bridgeBSDName]?.members ?? [])
    }
}
