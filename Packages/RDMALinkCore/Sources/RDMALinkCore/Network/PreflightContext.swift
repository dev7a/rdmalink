import Foundation

/// Everything the refusals need that one port cannot see.
///
/// ``StandalonePortSetup`` carries a single ``ObservedPort``, but R1 is about
/// *every* receptacle and R5 is about every route — so the two refusals the
/// spec marks "blocks preflight and any apply" (UX_SPEC §6.2) are unreachable
/// from a single port. This value carries them, and is re-read inside the
/// authorized burst so a cable that arrives between the review screen and the
/// password cannot slip through.
public struct PreflightContext: Sendable, Equatable {
    /// Every receptacle on this Mac, as the refusals see it — R1.
    public var observedPorts: [ObservedPort]
    /// The BSD names of this Mac's Thunderbolt ports, so R5 can exclude them
    /// and the bridges they are in from the routes it counts.
    public var thunderboltBSDNames: [String]
    /// What macOS says the default route is on, from ``NetworkGlobals``.
    /// Empty means "macOS did not say", not "there is no route".
    public var primaryInterfaces: [String]
    /// What kind of interface each of those is, so §S3 row 3 can print its
    /// **finding** — "Wi-Fi is connected…" — rather than a bare checkmark.
    public var primaryKinds: [NetworkGlobals.RouteKind]

    public init(
        observedPorts: [ObservedPort],
        thunderboltBSDNames: [String],
        primaryInterfaces: [String] = [],
        primaryKinds: [NetworkGlobals.RouteKind] = []
    ) {
        self.observedPorts = observedPorts
        self.thunderboltBSDNames = thunderboltBSDNames
        self.primaryInterfaces = primaryInterfaces
        self.primaryKinds = primaryKinds
    }

    /// The route that is not a Thunderbolt port and not one of their bridges —
    /// the one R5 is satisfied by, and the one §S3 row 3 names.
    public var routeOtherThanThunderbolt: NetworkGlobals.RouteKind? {
        let thunderbolt = Set(thunderboltBSDNames)
        return primaryKinds.first { !thunderbolt.contains($0.bsdName) }
    }

    /// Re-reads this Mac. Read-only: IOKit, `ifconfig` and `SCDynamicStore`.
    ///
    /// Call this **inside** the burst, immediately before the write, not once
    /// at preflight — that is the whole point of the type.
    public static func read(
        archetype: Archetype,
        runner: CommandRunner = CommandRunner()
    ) throws -> PreflightContext {
        let ports = try Inventory.readPorts(archetype: archetype, runner: runner)
        let primary = NetworkGlobals.primaryInterfaces()
        return PreflightContext(
            observedPorts: ports.map(\.observed),
            thunderboltBSDNames: ports.filter(\.isThunderbolt).map(\.bsdName),
            primaryInterfaces: primary,
            primaryKinds: primary.compactMap(NetworkGlobals.routeKind(of:))
        )
    }
}

extension Inventory {
    /// This read, as the last gate before a write sees it.
    ///
    /// - Parameter primaryInterfaces: from ``NetworkGlobals/primaryInterfaces(clientName:)``.
    ///   Kept a parameter rather than read here, so ``Inventory`` stays the
    ///   pure aggregate of one hardware read.
    public func preflightContext(primaryInterfaces: [String] = []) -> PreflightContext {
        PreflightContext(
            observedPorts: observedPorts,
            thunderboltBSDNames: thunderboltBSDNames,
            primaryInterfaces: primaryInterfaces,
            primaryKinds: primaryInterfaces.compactMap(NetworkGlobals.routeKind(of:))
        )
    }
}
