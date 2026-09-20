import Darwin
import Foundation
import SystemConfiguration

/// A bridge interface. `SCBridgeInterfaceRef` is an `SCNetworkInterfaceRef`
/// under another name, so the public interface calls work on it unchanged.
public typealias SCBridgeInterfaceRef = SCNetworkInterface

/// Which `SCBridgeInterface*` symbols this copy of macOS actually has.
///
/// The whole configure path rests on this private SPI, so the app probes it
/// rather than assuming, and degrades to a supervised System Settings hand-off
/// when it is not all there (`docs/ARCHITECTURE.md`).
public struct BridgeSPIAvailability: Sendable, Equatable {
    /// Symbol names that resolved, in the order they were probed.
    public var resolved: [String]
    /// Symbol names that did not.
    public var missing: [String]

    public init(resolved: [String], missing: [String]) {
        self.resolved = resolved
        self.missing = missing
    }

    /// Every probed symbol is present.
    public var isComplete: Bool { missing.isEmpty }
    /// Enough to read bridges and edit their member lists — all RDMALink does.
    public var canEditMembership: Bool {
        let needed = [
            "SCBridgeInterfaceCopyAll",
            "SCBridgeInterfaceGetMemberInterfaces",
            "SCBridgeInterfaceSetMemberInterfaces",
        ]
        return needed.allSatisfy(resolved.contains)
    }
    /// The private configuration push, `_SCBridgeInterfaceUpdateConfiguration`,
    /// resolves. Reported by `rdmalink bridge-probe` and nothing else: the
    /// call is root-only in practice (`docs/ARCHITECTURE.md`), so no operation
    /// makes it — configd runs it itself after every apply.
    public var canUpdateConfiguration: Bool {
        resolved.contains("_SCBridgeInterfaceUpdateConfiguration")
    }
    /// The kernel's live bridge list can be read.
    ///
    /// A separate `dlsym` probe from ``canUpdateConfiguration``: the two are
    /// independent symbols and a future macOS may drop either one, so every
    /// call site gates on the one it actually calls.
    public var canReadActiveBridges: Bool {
        resolved.contains("_SCBridgeInterfaceCopyActive")
    }
}

/// Something the bridge SPI would not do.
public enum BridgeSPIError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The symbol is not in this build of SystemConfiguration.
    case symbolMissing(String)
    case bridgeNotFound(String)
    /// The port is not a member of that bridge, so there is nothing to remove.
    case memberNotFound(bsdName: String, bridge: String)
    /// The port is already a member, so there is nothing to put back.
    case alreadyMember(bsdName: String, bridge: String)
    /// A member interface could not be found to put back.
    case interfaceNotFound(String)
    /// The SPI would not say what a bridge's members are. Never treated as
    /// "no members": rewriting a member list from an empty read would evict
    /// every other member of someone else's bridge.
    case memberListUnreadable(String)
    /// The SPI would not say what bridges there are. Never treated as "there
    /// are none": a port a bridge still claims is a port no service can be
    /// created on, so a failed read has to fall through to the other way of
    /// reading it rather than answer an empty list.
    case bridgeListUnreadable(code: Int32)
    /// The bridge that answered to the note's identifier or name is carrying
    /// members the note never saw, so it is not the bridge the note is about.
    case notTheRecordedBridge(bridge: String, members: [String], recorded: [String])
    case callFailed(step: String, code: Int32, message: String)

    public var description: String {
        switch self {
        case let .symbolMissing(name):
            return "\(name) is not available on this version of macOS"
        case let .bridgeNotFound(name):
            return "No bridge named \(name)"
        case let .memberNotFound(bsdName, bridge):
            return "\(bsdName) is not a member of \(bridge)"
        case let .alreadyMember(bsdName, bridge):
            return "\(bsdName) is already a member of \(bridge)"
        case let .interfaceNotFound(name):
            return "No network interface named \(name)"
        case let .memberListUnreadable(name):
            return "macOS would not say which interfaces are members of \(name)"
        case let .bridgeListUnreadable(code):
            return "macOS would not say what bridges the configuration has "
                + "(\(code) \(NetworkConfigurationError.message(code)))"
        case let .notTheRecordedBridge(bridge, members, recorded):
            return "\(bridge) has members \(members.joined(separator: ", ")), "
                + "which is not the bridge recorded with \(recorded.joined(separator: ", "))"
        case let .callFailed(step, _, message):
            return "\(step): \(message)"
        }
    }
}

/// The private `SCBridgeInterface*` SPI, probed with `dlsym` at first use.
///
/// There is no public header for any of this, no `kSCNetworkInterfaceTypeBridge`
/// constant, and neither `networksetup` nor `scutil` has a bridge verb — yet a
/// port has to be out of every bridge before it can carry RDMA. So the
/// prototypes here are hand-declared, the symbols are probed rather than
/// linked, and every result is verified by reading the kernel back through
/// ``InterfaceSnapshot``.
///
/// **RDMALink never creates or deletes a bridge.** `SCBridgeInterfaceCreate`
/// and `SCBridgeInterfaceRemove` are probed, so the app can say whether this
/// macOS has the full SPI, but they are deliberately not wrapped: the bridge is
/// always someone else's object and only membership is ever touched.
public enum BridgeSPI {
    /// One kernel bridge and its member list, as the SPI reports them right
    /// now. The undo note's own record is `Store`'s `BridgeMembership`.
    public struct Membership: Sendable, Equatable {
        /// The BSD name, e.g. `bridge0`.
        public var bsdName: String
        /// The localized display name, e.g. "Thunderbolt Bridge", when there is one.
        public var displayName: String?
        /// The BSD names of its members, in order.
        public var members: [String]

        public init(bsdName: String, displayName: String? = nil, members: [String]) {
            self.bsdName = bsdName
            self.displayName = displayName
            self.members = members
        }
    }

    // MARK: - Symbols

    /// The symbols that resolve under their plain names.
    public static let plainSymbolNames = [
        "SCBridgeInterfaceCopyAll",
        "SCBridgeInterfaceCopyAvailableMemberInterfaces",
        "SCBridgeInterfaceCreate",
        "SCBridgeInterfaceGetAllowConfiguredMembers",
        "SCBridgeInterfaceGetMemberInterfaces",
        "SCBridgeInterfaceGetOptions",
        "SCBridgeInterfaceRemove",
        "SCBridgeInterfaceSetAllowConfiguredMembers",
        "SCBridgeInterfaceSetLocalizedDisplayName",
        "SCBridgeInterfaceSetMemberInterfaces",
        "SCBridgeInterfaceSetOptions",
    ]

    /// The two that resolve only with a leading underscore.
    public static let underscoreSymbolNames = [
        "_SCBridgeInterfaceCopyActive",
        "_SCBridgeInterfaceUpdateConfiguration",
    ]

    /// Every symbol the app probes.
    public static var symbolNames: [String] { plainSymbolNames + underscoreSymbolNames }

    /// `RTLD_DEFAULT`, which the C macro defines as `((void *) -2)`.
    private static var anyLoadedImage: UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: -2)
    }

    /// Resolved once, on first use. Probing is read-only. Addresses are held as
    /// bit patterns because pointers are not `Sendable`.
    private static let table: [String: UInt] = {
        var found: [String: UInt] = [:]
        for name in symbolNames {
            if let symbol = dlsym(anyLoadedImage, name) {
                found[name] = UInt(bitPattern: symbol)
            }
        }
        return found
    }()

    /// Which symbols this Mac has. Probes on first use, then answers from cache.
    public static var availability: BridgeSPIAvailability {
        BridgeSPIAvailability(
            resolved: symbolNames.filter { table[$0] != nil },
            missing: symbolNames.filter { table[$0] == nil })
    }

    private static func symbol(_ name: String) throws -> UnsafeRawPointer {
        guard let address = table[name], let symbol = UnsafeRawPointer(bitPattern: address)
        else { throw BridgeSPIError.symbolMissing(name) }
        return symbol
    }

    // MARK: - Hand-declared prototypes

    private typealias CopyFromPreferences =
        @convention(c) (SCPreferences) -> Unmanaged<CFArray>?
    private typealias CopyActive = @convention(c) () -> Unmanaged<CFArray>?
    private typealias GetArray =
        @convention(c) (SCBridgeInterfaceRef) -> Unmanaged<CFArray>?
    private typealias GetDictionary =
        @convention(c) (SCBridgeInterfaceRef) -> Unmanaged<CFDictionary>?
    private typealias GetFlag = @convention(c) (SCBridgeInterfaceRef) -> DarwinBoolean
    private typealias SetMembers =
        @convention(c) (SCBridgeInterfaceRef, CFArray) -> DarwinBoolean

    // MARK: - Reads

    /// Every bridge in the stored configuration, members included.
    public static func bridges(in preferences: SCPreferences) throws -> [Membership] {
        try copyAll(in: preferences).map(describe)
    }

    /// Every bridge the kernel has live right now.
    ///
    /// Only available as `_SCBridgeInterfaceCopyActive`, which is a separate
    /// probe from the configuration push — gate on ``BridgeSPIAvailability/canReadActiveBridges``.
    public static func activeBridges() throws -> [Membership] {
        let call = unsafeBitCast(try symbol("_SCBridgeInterfaceCopyActive"), to: CopyActive.self)
        // Same distinction as `copyAll`: a NULL is a call that failed, not a
        // Mac with no live bridges.
        guard let value = call()?.takeRetainedValue(),
              let bridges = value as? [SCBridgeInterfaceRef] else {
            throw BridgeSPIError.bridgeListUnreadable(code: SCError())
        }
        return try bridges.map(describe)
    }

    /// BSD name to human name, for the copy that names a System Settings
    /// object. Degrades to an empty map — the refusals fall back to the BSD
    /// name rather than guess (`docs/ARCHITECTURE.md`, rule 5).
    public static func displayNames(in preferences: SCPreferences) -> [String: String] {
        guard let bridges = try? bridges(in: preferences) else { return [:] }
        return bridges.reduce(into: [:]) { names, bridge in
            names[bridge.bsdName] = bridge.displayName
        }
    }

    /// The interfaces this macOS would let a bridge take as members.
    public static func availableMemberInterfaces(
        in preferences: SCPreferences
    ) throws -> [String] {
        try availableMembers(in: preferences).compactMap { name(of: $0) }
    }

    private static func availableMembers(in preferences: SCPreferences) throws -> [SCNetworkInterface] {
        let call = unsafeBitCast(
            try symbol("SCBridgeInterfaceCopyAvailableMemberInterfaces"),
            to: CopyFromPreferences.self)
        return call(preferences)?.takeRetainedValue() as? [SCNetworkInterface] ?? []
    }

    /// A bridge's options dictionary, when the SPI offers one.
    public static func options(of bridge: SCBridgeInterfaceRef) throws -> [String: Any] {
        let call = unsafeBitCast(try symbol("SCBridgeInterfaceGetOptions"),
                                 to: GetDictionary.self)
        return call(bridge)?.takeUnretainedValue() as? [String: Any] ?? [:]
    }

    /// Whether a bridge accepts members that already carry a configuration.
    public static func allowsConfiguredMembers(of bridge: SCBridgeInterfaceRef) throws -> Bool {
        let call = unsafeBitCast(try symbol("SCBridgeInterfaceGetAllowConfiguredMembers"),
                                 to: GetFlag.self)
        return call(bridge).boolValue
    }

    // MARK: - Membership

    /// Takes one port out of one bridge, leaving every other member alone.
    ///
    /// The new member list is the current one minus exactly that interface: if
    /// the port is not a member, nothing is written and
    /// ``BridgeSPIError/memberNotFound(bsdName:bridge:)`` is thrown.
    ///
    /// **Internal on purpose.** This only changes an open preferences session;
    /// the commit and the apply that realise it are the caller's. It is
    /// reachable only through ``NetworkWriter``, which owns the authorized
    /// session, honours ``AuthorizedSession/Mode/dryRun``, requires the undo
    /// note first, and verifies the kernel afterwards.
    ///
    /// - Returns: what the bridge's membership should now be.
    @discardableResult
    static func removeMember(
        bsdName: String,
        from bridge: SCBridgeInterfaceRef
    ) throws -> Membership {
        try requireMembershipEditing()
        let bridgeName = name(of: bridge) ?? ""
        let members = try memberInterfaces(of: bridge)
        let remaining = members.filter { name(of: $0) != bsdName }
        guard remaining.count == members.count - 1 else {
            throw BridgeSPIError.memberNotFound(bsdName: bsdName, bridge: bridgeName)
        }
        try setMemberInterfaces(remaining, of: bridge, step: "Remove \(bsdName) from \(bridgeName)")
        return try describe(bridge)
    }

    /// Puts one port back into one bridge, in its original position.
    ///
    /// The inverse of ``removeMember(bsdName:from:)``, and the only other
    /// thing RDMALink ever does to a bridge. Internal for the same reason.
    ///
    /// - Parameter position: where the port sat in the member list before, from
    ///   the undo note. Out-of-range positions go on the end.
    @discardableResult
    static func addMember(
        bsdName: String,
        to bridge: SCBridgeInterfaceRef,
        at position: Int? = nil,
        in preferences: SCPreferences
    ) throws -> Membership {
        try requireMembershipEditing()
        let bridgeName = name(of: bridge) ?? ""
        // Throws rather than degrading to []: a member list rebuilt from an
        // empty read would write back a one-member bridge and silently evict
        // every other member of a bridge RDMALink never touched.
        var members = try memberInterfaces(of: bridge)
        guard !members.contains(where: { name(of: $0) == bsdName }) else {
            throw BridgeSPIError.alreadyMember(bsdName: bsdName, bridge: bridgeName)
        }
        // Prefer the interface object the SPI itself offers as a member: an
        // interface taken from SCNetworkInterfaceCopyAll may be refused.
        let offered = (try? availableMembers(in: preferences)) ?? []
        let candidates = offered + (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [])
        guard let interface = candidates.first(where: { name(of: $0) == bsdName }) else {
            throw BridgeSPIError.interfaceNotFound(bsdName)
        }
        members.insert(interface, at: min(max(position ?? members.count, 0), members.count))
        try setMemberInterfaces(members, of: bridge, step: "Add \(bsdName) to \(bridgeName)")
        return try describe(bridge)
    }

    /// Every mutation starts here: a missing symbol is a supervised System
    /// Settings hand-off, never a write made from a half-resolved SPI.
    static func requireMembershipEditing() throws {
        let availability = availability
        guard availability.canEditMembership else {
            throw BridgeSPIError.symbolMissing(
                availability.missing.first ?? "SCBridgeInterfaceSetMemberInterfaces")
        }
    }

    // MARK: - Resolving a bridge

    /// The bridge an undo note is about, by **identifier** first.
    ///
    /// `bridgeN` names are kernel-allocated and are not stable across a delete
    /// and recreate, so a note's `bridge0` may be someone else's bridge by the
    /// time Restore runs (`docs/ARCHITECTURE.md`, rule 2). The recorded
    /// service identifier is matched first and the BSD name is only a fallback
    /// for a note that never had one.
    static func bridge(
        serviceIdentifier: String?,
        bsdName: String,
        in preferences: SCPreferences
    ) throws -> SCBridgeInterfaceRef {
        let bridges = try copyAll(in: preferences)
        if let serviceIdentifier {
            let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] ?? []
            if let service = services.first(where: {
                SCNetworkServiceGetServiceID($0) as String? == serviceIdentifier
            }),
               let interface = SCNetworkServiceGetInterface(service),
               let resolved = name(of: interface),
               let bridge = bridges.first(where: { name(of: $0) == resolved }) {
                return bridge
            }
        }
        guard let bridge = bridges.first(where: { name(of: $0) == bsdName })
        else { throw BridgeSPIError.bridgeNotFound(bsdName) }
        return bridge
    }

    /// The bridge an undo note is about, **and** the proof that it is still
    /// that bridge.
    ///
    /// A `bridgeN` name freed by a delete and handed to a different virtual
    /// interface would otherwise be edited as if it were the recorded one, so
    /// the note's own member list is the proof: every member the bridge is
    /// carrying now has to be one the note saw.
    static func resolveRecorded(
        _ recorded: BridgeMembership,
        in preferences: SCPreferences
    ) throws -> (bridge: SCBridgeInterfaceRef, membership: Membership) {
        let resolved = try bridge(serviceIdentifier: recorded.serviceIdentifier,
                                  bsdName: recorded.bridgeName, in: preferences)
        let current = try describe(resolved)
        guard Set(current.members).isSubset(of: Set(recorded.members)) else {
            throw BridgeSPIError.notTheRecordedBridge(
                bridge: current.bsdName, members: current.members,
                recorded: recorded.members)
        }
        return (resolved, current)
    }

    // MARK: - Plumbing

    /// Every bridge the configuration has, or the reason macOS would not say.
    ///
    /// Never `[]` on failure, for the same reason ``memberInterfaces(of:)`` is
    /// not: "the call failed" and "there are no bridges" are different facts,
    /// and only one of them means a port is free. An empty `CFArray` is the
    /// second and comes back as an empty list; a NULL is the first and throws,
    /// so ``StoredBridges/read(clientName:fileURL:spi:)`` falls through to the
    /// preferences file instead of reporting a Mac with no bridges.
    private static func copyAll(in preferences: SCPreferences) throws -> [SCBridgeInterfaceRef] {
        let call = unsafeBitCast(try symbol("SCBridgeInterfaceCopyAll"),
                                 to: CopyFromPreferences.self)
        guard let value = call(preferences)?.takeRetainedValue() else {
            throw BridgeSPIError.bridgeListUnreadable(code: SCError())
        }
        guard let bridges = value as? [SCBridgeInterfaceRef] else {
            throw BridgeSPIError.bridgeListUnreadable(code: SCError())
        }
        return bridges
    }

    /// A bridge's members, or the reason macOS would not say.
    ///
    /// Never `[]` on failure: a missing symbol and a bridge with no members
    /// are different facts, and only one of them is safe to write back.
    private static func memberInterfaces(of bridge: SCBridgeInterfaceRef) throws -> [SCNetworkInterface] {
        let call = unsafeBitCast(try symbol("SCBridgeInterfaceGetMemberInterfaces"), to: GetArray.self)
        guard let value = call(bridge)?.takeUnretainedValue() else {
            throw BridgeSPIError.memberListUnreadable(name(of: bridge) ?? "that bridge")
        }
        guard let members = value as? [SCNetworkInterface] else {
            throw BridgeSPIError.memberListUnreadable(name(of: bridge) ?? "that bridge")
        }
        return members
    }

    private static func setMemberInterfaces(
        _ members: [SCNetworkInterface],
        of bridge: SCBridgeInterfaceRef,
        step: String
    ) throws {
        let call = unsafeBitCast(try symbol("SCBridgeInterfaceSetMemberInterfaces"),
                                 to: SetMembers.self)
        guard call(bridge, members as CFArray).boolValue else {
            let code = SCError()
            throw BridgeSPIError.callFailed(
                step: step, code: code, message: NetworkConfigurationError.message(code))
        }
    }

    private static func name(of interface: SCNetworkInterface) -> String? {
        SCNetworkInterfaceGetBSDName(interface) as String?
    }

    static func describe(_ bridge: SCBridgeInterfaceRef) throws -> Membership {
        Membership(
            bsdName: name(of: bridge) ?? "",
            displayName: SCNetworkInterfaceGetLocalizedDisplayName(bridge) as String?,
            members: try memberInterfaces(of: bridge).compactMap(name))
    }
}
