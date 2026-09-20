import Foundation
import SystemConfiguration

/// Proof that the undo note for one port landed before anything was changed.
///
/// The `Store` module writes the note and vends the token; `Network` only
/// checks that it is there and that it is about the right port.
public struct BaselineToken: Sendable, Equatable {
    public var portBSDName: String
    public var recordedAt: Date

    public init(portBSDName: String, recordedAt: Date = Date()) {
        self.portBSDName = portBSDName
        self.recordedAt = recordedAt
    }
}

/// The seam to the `Store` module's undo note, as closures so neither module
/// has to know the other's types.
public struct BaselineRecorder: Sendable {
    /// Whether a note could be written right now, **without writing one**.
    /// This is how ``AuthorizedSession/Mode/dryRun`` proves R14: a dry run
    /// leaves nothing behind, so it cannot prove the gate by using it.
    public var checkWritable: @Sendable () -> Refusal?
    /// Writes how the port looks today and returns proof. Throwing means
    /// nothing may be changed at all (R14).
    public var record: @Sendable (_ bsdName: String) throws -> BaselineToken
    /// Records the service RDMALink just created, at creation time and before
    /// the commit, so a crash mid-burst still leaves something that can find
    /// it again — and so Restore can tell later whether it is still the same
    /// service.
    public var recordCreatedService: @Sendable (_ service: CreatedServiceRecord, _ token: BaselineToken) throws -> Void

    public init(
        checkWritable: @escaping @Sendable () -> Refusal?,
        record: @escaping @Sendable (_ bsdName: String) throws -> BaselineToken,
        recordCreatedService: @escaping @Sendable (_ service: CreatedServiceRecord, _ token: BaselineToken) throws -> Void
    ) {
        self.checkWritable = checkWritable
        self.record = record
        self.recordCreatedService = recordCreatedService
    }
}

/// What setting up one port would change, with no writes of any kind.
public struct StandalonePortPlan: Sendable, Equatable {
    /// Where this port goes from the review screen.
    public enum Outcome: Sendable, Equatable {
        /// Nothing there yet: set-up can run.
        case setUp
        /// The port is already configured, by the user or by RDMALink. UX_SPEC
        /// §S4 routes this to Adopt (S9) and R27 says so out loud: **there is
        /// no path anywhere in the app that rewrites a service the app did not
        /// create**. Routing, not refusing — there is no refusal copy for it.
        case adopt(serviceID: String)
        /// A refusal is in the way. ``StandalonePortPlan/refusal`` carries it.
        case refused
    }

    public var bsdName: String
    public var positionName: String
    /// The name the new service gets.
    public var serviceName: String
    /// Every kernel bridge the port must leave first, including one that is down.
    public var bridgesToLeave: [String]
    /// What is on the port today.
    public var existing: PortConfiguration
    /// Where this port goes.
    public var outcome: Outcome
    /// The refusal to show instead of the plan, when there is one. On the
    /// review screen the default button is removed entirely, not disabled.
    public var refusal: Refusal?

    /// True when set-up can actually run — which is the **only** thing that
    /// may keep the review screen's default button on screen.
    public var canProceed: Bool { refusal == nil && outcome == .setUp }

    /// True when the app should show Adopt (S9) rather than set-up.
    public var routesToAdopt: Bool {
        if case .adopt = outcome { return true }
        return false
    }

    public init(
        bsdName: String,
        positionName: String,
        serviceName: String,
        bridgesToLeave: [String],
        existing: PortConfiguration,
        outcome: Outcome = .setUp,
        refusal: Refusal? = nil
    ) {
        self.bsdName = bsdName
        self.positionName = positionName
        self.serviceName = serviceName
        self.bridgesToLeave = bridgesToLeave
        self.existing = existing
        self.outcome = outcome
        self.refusal = refusal
    }
}

/// The service RDMALink created, captured at creation time.
public struct CreatedService: Sendable, Equatable {
    public var serviceID: String
    public var serviceName: String
    public var bsdName: String
    public var createdAt: Date

    public init(serviceID: String, serviceName: String, bsdName: String, createdAt: Date = Date()) {
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.bsdName = bsdName
        self.createdAt = createdAt
    }
}

/// Gives one Thunderbolt port its own network service, with IPv4 off and IPv6
/// link-local only — everything RDMA needs and nothing else.
///
/// Bridge membership is not this type's business: the port must already be out
/// of every bridge (``NetworkWriter`` moves the members), and
/// ``preview(snapshot:services:context:bridgeNames:)`` refuses while it is not.
public struct StandalonePortSetup: Sendable {
    public let port: ObservedPort

    public init(port: ObservedPort) { self.port = port }

    /// The name the created service carries, e.g. `RDMA — Back, far left`.
    public static func serviceName(for positionName: String) -> String {
        "RDMA — \(positionName)"
    }

    // MARK: - Preview

    /// What would change. Pure: it reads nothing and writes nothing.
    ///
    /// - Parameter context: the whole Mac, because two of the four refusals
    ///   that block an apply are about receptacles and routes this port cannot
    ///   see. The same value is re-read inside the burst and evaluated again,
    ///   so the review screen and the last gate agree.
    public func preview(
        snapshot: InterfaceSnapshot,
        services: [NetworkServiceInfo],
        context: PreflightContext,
        storedBridges: [BridgeSPI.Membership],
        bridgeNames: [String: String] = [:]
    ) -> StandalonePortPlan {
        let bridges = Self.bridges(of: port.bsdName, snapshot: snapshot, stored: storedBridges)
        let existing = NetworkServices.classify(
            services: NetworkServices.services(for: port.bsdName, in: services),
            bridges: bridges)
        var plan = StandalonePortPlan(
            bsdName: port.bsdName,
            positionName: port.positionName,
            serviceName: Self.serviceName(for: port.positionName),
            bridgesToLeave: bridges,
            existing: existing,
            outcome: .setUp,
            refusal: nil)
        plan.refusal = blockingRefusal(
            snapshot: snapshot, services: services, context: context,
            storedBridges: storedBridges, bridgeNames: bridgeNames)
        if plan.refusal != nil {
            plan.outcome = .refused
            return plan
        }
        // Not a refusal: a port that already carries a service is somebody's
        // work, and the only thing the app ever offers for it is Adopt.
        switch existing {
        case let .readyForRDMA(serviceID), let .nearMatch(serviceID, _):
            plan.outcome = .adopt(serviceID: serviceID)
        case .unconfigured:
            plan.outcome = .setUp
        case .foreign:
            plan.outcome = .refused  // unreachable: R16 is raised above.
        }
        return plan
    }

    /// Every refusal that blocks an apply, in the order the spec raises them.
    ///
    /// R1, R2 and R5 are marked "blocks preflight and any apply" / "hard
    /// refusal at preflight and at review" (UX_SPEC §6.2), so they belong here
    /// and not only in the preflight screen — a cable that arrives while the
    /// review is on screen has to be caught by the last gate.
    public func blockingRefusal(
        snapshot: InterfaceSnapshot,
        services: [NetworkServiceInfo],
        context: PreflightContext,
        storedBridges: [BridgeSPI.Membership],
        bridgeNames: [String: String] = [:]
    ) -> Refusal? {
        // §6.2 R2 first: a cable looped back into two bridged ports would read
        // as two Macs otherwise, and the sentence for it is R2's.
        if let refusal = Refusals.loopedBackIntoThisMac(context.observedPorts) { return refusal }
        if let refusal = Refusals.oneCableOnly(context.observedPorts) { return refusal }
        if let refusal = Refusals.managementPathExists(
            in: snapshot,
            thunderboltPorts: context.thunderboltBSDNames,
            primaryInterfaces: context.primaryInterfaces) { return refusal }
        if let refusal = Refusals.portStillBridged(
            port, in: snapshot, storedBridges: storedBridges, bridgeNames: bridgeNames) {
            return refusal
        }
        let existing = NetworkServices.classify(
            services: NetworkServices.services(for: port.bsdName, in: services),
            bridges: Self.bridges(of: port.bsdName, snapshot: snapshot, stored: storedBridges))
        if case let .foreign(_, reason) = existing {
            return Refusals.foreignService(port, reason: reason)
        }
        return nil
    }

    /// Every bridge a port is in, from both reads — kernel first.
    static func bridges(
        of bsdName: String,
        snapshot: InterfaceSnapshot,
        stored: [BridgeSPI.Membership]
    ) -> [String] {
        let kernel = snapshot.bridges(containing: bsdName)
        let saved = StoredBridges.names(in: stored, containing: bsdName)
        return kernel + saved.filter { !kernel.contains($0) }
    }

    // MARK: - Perform

    /// Writes the service, in one burst inside the credential window.
    ///
    /// Order: re-read the world, refuse if anything is in the way, take the
    /// lock, **write the undo note**, then create. The service is recorded
    /// before the commit. The session is left locked so the caller can keep the
    /// burst going, and must be ended by the caller.
    ///
    /// - Parameter context: re-read **inside the burst**, not carried over from
    ///   preflight — ``PreflightContext/read(archetype:runner:)`` is what that
    ///   looks like. Passing a stale one defeats the whole gate.
    ///
    /// - Returns: the service that was created, or `nil` in
    ///   ``AuthorizedSession/Mode/dryRun``, which proves the burst and leaves
    ///   nothing behind — no service, and no undo note claiming one.
    ///
    /// - Throws: ``Refusal`` when the world says no, ``NetworkConfigurationError``
    ///   when macOS does.
    @discardableResult
    public func perform(
        session: AuthorizedSession,
        baseline: BaselineRecorder,
        context: PreflightContext
    ) throws -> CreatedService? {
        let preferences = try session.preferences
        let snapshot = try InterfaceSnapshot.read()
        let services = NetworkServices.read(from: preferences)
        // R9 names a System Settings object, so it gets the same map the rest
        // of the app uses. `SCBridgeInterfaceCopyAll` is a plain symbol and
        // needs no extra probe; an absent SPI degrades to the BSD name.
        let storedBridges = (try? BridgeSPI.bridges(in: preferences)) ?? StoredBridges.read().bridges
        let bridgeNames = storedBridges.reduce(into: [String: String]()) { names, bridge in
            names[bridge.bsdName] = bridge.displayName
        }
        let plan = preview(snapshot: snapshot, services: services,
                           context: context, storedBridges: storedBridges,
                           bridgeNames: bridgeNames)
        if let refusal = plan.refusal { throw refusal }
        if !NetworkServices.services(for: port.bsdName, in: services).isEmpty {
            // Belt and braces: `preview` routes this port to Adopt, so no
            // screen in the app offers a button that reaches here.
            throw NetworkConfigurationError.missing(
                "a free interface: \(port.bsdName) already has a service")
        }

        try session.lock()

        let token: BaselineToken
        if session.mode == .live {
            do {
                token = try baseline.record(port.bsdName)
            } catch {
                throw Refusals.baselineUnwritable(detail: "\(error)")
            }
            guard token.portBSDName == port.bsdName else {
                throw Refusals.baselineUnwritable(
                    detail: "The note that came back is about \(token.portBSDName), not \(port.bsdName).")
            }
        } else {
            // A dry run proves R14 rather than using it: writing a note here
            // would leave the app believing a port is managed that nothing
            // ever touched.
            if let refusal = baseline.checkWritable() { throw refusal }
            token = BaselineToken(portBSDName: port.bsdName)
        }

        let record = try Self.createService(
            bsdName: port.bsdName, named: plan.serviceName, session: session)

        guard session.mode == .live else {
            // Everything above happened in memory. Nothing is committed, the
            // preferences are thrown away with the session, and no note claims
            // a service that will never exist.
            return nil
        }

        // The record goes in the note before the commit: matching is by
        // identifier, never by name — and the configuration alongside it is
        // what lets Restore tell RDMALink's own work from a service somebody
        // has since taken over.
        do {
            try baseline.recordCreatedService(record, token)
        } catch {
            throw Refusals.baselineUnwritable(detail: "\(error)")
        }

        try session.commit()
        try session.apply()
        return CreatedService(serviceID: record.identifier, serviceName: plan.serviceName,
                              bsdName: port.bsdName, createdAt: Date())
    }

    /// Creates one standalone service on `bsdName`, names it, turns IPv4 off
    /// and sets IPv6 to link-local only.
    ///
    /// Writes into the open session and **does not commit**: the caller owns
    /// the burst, and an operation that has more to do commits once at the end
    /// of it.
    ///
    /// The record that comes back is read off the object macOS actually made
    /// rather than off what was asked for — Restore compares the live service
    /// against it, so it has to be what a freshly-made RDMA service looks like
    /// on this build, not what RDMALink intended.
    /// The error a refused `SCNetworkServiceCreate` deserves.
    ///
    /// configd answers with a bare `kSCStatusFailed`, whose `SCErrorString` is
    /// the single word "Failed!", when the interface is still a member of a
    /// bridge in the stored configuration — by far the likeliest reason to be
    /// here, and one the caller can act on. Either stored list naming the port
    /// is enough to say so: the session's copy is what the call was made
    /// against, and the committed one is what a fresh handle — and the next
    /// process — would see.
    static func createFailure(
        bsdName: String,
        code: Int32,
        session: [BridgeSPI.Membership],
        committed: [BridgeSPI.Membership]
    ) -> NetworkConfigurationError {
        let inSession = StoredBridges.names(in: session, containing: bsdName)
        let inCommitted = StoredBridges.names(in: committed, containing: bsdName)
        let claiming = inSession + inCommitted.filter { !inSession.contains($0) }
        if code == kSCStatusFailed, !claiming.isEmpty {
            return .interfaceIsStoredBridgeMember(
                bsdName: bsdName, bridges: claiming, code: code)
        }
        return .stepFailed(
            step: "Create the RDMA service", code: code,
            message: NetworkConfigurationError.message(code))
    }

    static func createService(
        bsdName: String,
        named name: String,
        session: AuthorizedSession
    ) throws -> CreatedServiceRecord {
        let preferences = try session.preferences
        guard let location = SCNetworkSetCopyCurrent(preferences) else {
            throw NetworkConfigurationError.missing("the current network location")
        }
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        guard let interface = interfaces.first(where: {
            SCNetworkInterfaceGetBSDName($0) as String? == bsdName
        }) else {
            throw NetworkConfigurationError.missing("the interface \(bsdName)")
        }
        guard let service = SCNetworkServiceCreate(preferences, interface) else {
            throw createFailure(
                bsdName: bsdName, code: SCError(),
                // Both stored lists, because they answer different questions.
                // The session's is the one this call was made against; the
                // committed one is what is on disk, and a burst that has
                // already removed the member from its session copy would find
                // nothing in it.
                session: (try? BridgeSPI.bridges(in: preferences)) ?? [],
                committed: StoredBridges.read().bridges)
        }
        try session.check(SCNetworkServiceEstablishDefaultConfiguration(service),
                          "Create the RDMA service")
        try session.check(SCNetworkServiceSetName(service, name as CFString),
                          "Name the RDMA service")
        guard let ipv4 = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeIPv4),
              let ipv6 = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeIPv6) else {
            throw NetworkConfigurationError.missing("the IPv4 and IPv6 protocols")
        }
        try session.check(SCNetworkProtocolSetEnabled(ipv4, false), "Turn IPv4 off")
        try session.check(SCNetworkProtocolSetConfiguration(ipv6, [
            kSCPropNetIPv6ConfigMethod as String: kSCValNetIPv6ConfigMethodLinkLocal as String,
        ] as CFDictionary), "Set IPv6 to link-local only")
        try session.check(SCNetworkProtocolSetEnabled(ipv6, true), "Enable IPv6")
        try session.check(SCNetworkServiceSetEnabled(service, true), "Enable the RDMA service")
        try session.check(SCNetworkSetAddService(location, service),
                          "Add the RDMA service to this location")
        guard let serviceID = SCNetworkServiceGetServiceID(service) as String? else {
            throw NetworkConfigurationError.missing("the new service's identifier")
        }
        let made = NetworkServices.describe(service)
        return CreatedServiceRecord(
            identifier: serviceID,
            interfaceBSDName: bsdName,
            name: name,
            isEnabled: made?.isEnabled ?? true,
            ipv4: made?.ipv4,
            ipv6: made?.ipv6)
    }
}

/// What removing RDMALink's own service would do.
public struct StandalonePortRemovalPlan: Sendable, Equatable {
    public var serviceID: String
    /// The service's current name, which may have been changed by hand since.
    public var serviceName: String?
    public var interfaceBSDName: String?
    /// True when someone has already removed it. Restore then only has the
    /// bridge membership left to put back.
    public var isAlreadyGone: Bool
    /// How the live service differs from the one RDMALink made, in the app's
    /// own words. Non-empty means Restore refuses rather than deletes.
    public var differences: [String]
    /// The refusal to show instead of the plan, when there is one.
    public var refusal: Refusal?

    /// True when the service can be removed.
    public var canProceed: Bool { refusal == nil }

    public init(
        serviceID: String,
        serviceName: String? = nil,
        interfaceBSDName: String? = nil,
        isAlreadyGone: Bool,
        differences: [String] = [],
        refusal: Refusal? = nil
    ) {
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.interfaceBSDName = interfaceBSDName
        self.isAlreadyGone = isAlreadyGone
        self.differences = differences
        self.refusal = refusal
    }
}

/// Deletes the one service RDMALink created, matched by identifier only.
///
/// A service the user renames afterwards is still recognised; a service that
/// happens to share RDMALink's name is never mistaken for one of its own. But
/// an identifier is not a licence: the service must still be on the port the
/// note is about, and must still be carrying the configuration RDMALink left
/// on it. A service somebody has since taken over — given a fixed address and
/// real traffic — is refused (R28), not deleted.
public struct StandalonePortRemoval: Sendable {
    /// The port this restore is about, and the service as RDMALink made it.
    public let port: ObservedPort
    public let record: CreatedServiceRecord

    public var serviceID: String { record.identifier }

    public init(port: ObservedPort, record: CreatedServiceRecord) {
        self.port = port
        self.record = record
    }

    /// What would be removed. Pure.
    public func preview(services: [NetworkServiceInfo]) -> StandalonePortRemovalPlan {
        guard let service = services.first(where: { $0.serviceID == record.identifier }) else {
            return StandalonePortRemovalPlan(serviceID: record.identifier, serviceName: nil,
                                             interfaceBSDName: nil, isAlreadyGone: true)
        }
        var plan = StandalonePortRemovalPlan(
            serviceID: record.identifier,
            serviceName: service.name,
            interfaceBSDName: service.interfaceBSDName,
            isAlreadyGone: false,
            differences: record.differences(from: service))
        // A note carrying somebody else's identifier — hand-edited, or copied
        // from another Mac — must never delete that Mac's Wi-Fi. A service on
        // the wrong interface is treated as gone, not as a thing to remove.
        if service.interfaceBSDName != record.interfaceBSDName {
            return StandalonePortRemovalPlan(serviceID: record.identifier, serviceName: service.name,
                                             interfaceBSDName: service.interfaceBSDName,
                                             isAlreadyGone: true)
        }
        if !plan.differences.isEmpty {
            plan.refusal = Refusals.createdServiceEdited(port: port, differences: plan.differences)
        }
        return plan
    }

    /// Removes the service. Does nothing, successfully, when it is already gone.
    ///
    /// The session is left locked for the rest of the burst — the port still
    /// has to go back into its bridges — and must be ended by the caller.
    @discardableResult
    public func perform(session: AuthorizedSession) throws -> StandalonePortRemovalPlan {
        let preferences = try session.preferences
        let plan = preview(services: NetworkServices.read(from: preferences))
        if let refusal = plan.refusal { throw refusal }
        guard !plan.isAlreadyGone else { return plan }

        guard let service = Self.liveService(identifier: record.identifier,
                                             expectedInterface: record.interfaceBSDName,
                                             in: preferences) else {
            return StandalonePortRemovalPlan(serviceID: record.identifier,
                                             serviceName: plan.serviceName,
                                             interfaceBSDName: plan.interfaceBSDName,
                                             isAlreadyGone: true)
        }

        guard session.mode == .live else { return plan }
        try session.lock()
        try session.check(SCNetworkServiceRemove(service), "Delete the RDMA service")
        try session.commit()
        try session.apply()
        return plan
    }

    /// The live service object for an identifier, but **only** while it is
    /// still on the interface the caller expects.
    ///
    /// Read one more time off the object that is about to be removed, so the
    /// interface check cannot be defeated by a stale list — a note carrying
    /// somebody else's identifier must never delete that Mac's Wi-Fi. `nil`
    /// means "treat it as already gone", never "remove something else".
    static func liveService(
        identifier: String,
        expectedInterface: String,
        in preferences: SCPreferences
    ) -> SCNetworkService? {
        let all = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] ?? []
        guard let service = all.first(where: {
            SCNetworkServiceGetServiceID($0) as String? == identifier
        }) else { return nil }
        let liveInterface = SCNetworkServiceGetInterface(service)
            .flatMap { SCNetworkInterfaceGetBSDName($0) as String? }
        return liveInterface == expectedInterface ? service : nil
    }
}
