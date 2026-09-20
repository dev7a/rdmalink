import Foundation
import SystemConfiguration

/// The writes one authorized burst is made of.
///
/// The operations in this folder own sequencing, verification and rollback;
/// this is the one seam beneath them, so a test can drive a whole flow — R10's
/// reverse order included — with no credential, no bridge SPI and no kernel.
/// ``LiveNetworkWriter`` is the only production implementation and does
/// nothing but forward to the `Network` types beside it.
///
/// Internal on purpose: nothing outside this module writes network
/// configuration, and the app reaches these flows through the operations.
protocol NetworkWriter: AnyObject {
    /// True when the session will throw its changes away instead of
    /// committing them.
    ///
    /// A dry run writes no bridge membership at all: the SPI's configuration
    /// push is what configd itself uses to realise a change and the kernel has
    /// it the moment the call returns, so there is no such thing as a dry run
    /// of it (see ``BridgeMembershipChange``).
    var isDryRun: Bool { get }

    /// Whether `_SCBridgeInterfaceUpdateConfiguration` resolves here.
    var canPushBridgeConfiguration: Bool { get }

    /// Takes the configuration lock. Fails rather than waits — two writers is
    /// how configurations get mangled (R12).
    func lock() throws

    func services() throws -> [NetworkServiceInfo]
    /// The identifiers of every service in the current location, in order.
    func serviceOrder() throws -> [String]
    /// Every bridge in the stored configuration, members included.
    func bridges() throws -> [BridgeSPI.Membership]
    /// The kernel's own answer, from `ifconfig -a`. The only place membership
    /// can really be read.
    func readKernel() throws -> InterfaceSnapshot

    func removeMember(_ bsdName: String, from bridge: BridgeMembership) throws
    func addMember(_ bsdName: String, to bridge: BridgeMembership, at position: Int?) throws
    func createService(on bsdName: String, named name: String) throws -> CreatedServiceRecord
    /// Deletes a service by identifier, and only while it is still on
    /// `expectedInterface`. `false` means it was already gone — which is a
    /// success, not a failure.
    @discardableResult
    func deleteService(identifier: String, expectedInterface: String) throws -> Bool

    /// `_SCBridgeInterfaceUpdateConfiguration`, the routine configd itself
    /// uses to realise a bridge change.
    func pushBridgeConfiguration() throws
    func commitAndApply() throws
}

/// The real thing: one authorized session, the bridge SPI, and `ifconfig`.
final class LiveNetworkWriter: NetworkWriter {
    private let session: AuthorizedSession
    private let runner: CommandRunner

    init(session: AuthorizedSession, runner: CommandRunner = CommandRunner()) {
        self.session = session
        self.runner = runner
    }

    var isDryRun: Bool { session.mode == .dryRun }

    var canPushBridgeConfiguration: Bool { BridgeSPI.availability.canUpdateConfiguration }

    func lock() throws { try session.lock() }

    func services() throws -> [NetworkServiceInfo] {
        NetworkServices.read(from: try session.preferences)
    }

    func serviceOrder() throws -> [String] {
        NetworkServices.serviceOrder(in: try session.preferences)
    }

    func bridges() throws -> [BridgeSPI.Membership] {
        try BridgeSPI.bridges(in: try session.preferences)
    }

    func readKernel() throws -> InterfaceSnapshot {
        try InterfaceSnapshot.read(using: runner)
    }

    func removeMember(_ bsdName: String, from bridge: BridgeMembership) throws {
        try BridgeSPI.requireMembershipEditing()
        let preferences = try session.preferences
        // Resolved by identifier, and checked against the member list the note
        // recorded: a `bridgeN` name freed by a delete and handed to another
        // virtual interface is not the bridge this change is about.
        let (resolved, _) = try BridgeSPI.resolveRecorded(bridge, in: preferences)
        guard !isDryRun else { return }
        try session.lock()
        try BridgeSPI.removeMember(bsdName: bsdName, from: resolved)
    }

    func addMember(_ bsdName: String, to bridge: BridgeMembership, at position: Int?) throws {
        try BridgeSPI.requireMembershipEditing()
        let preferences = try session.preferences
        let (resolved, _) = try BridgeSPI.resolveRecorded(bridge, in: preferences)
        guard !isDryRun else { return }
        try session.lock()
        try BridgeSPI.addMember(bsdName: bsdName, to: resolved, at: position, in: preferences)
    }

    func createService(on bsdName: String, named name: String) throws -> CreatedServiceRecord {
        try session.lock()
        return try StandalonePortSetup.createService(
            bsdName: bsdName, named: name, session: session)
    }

    @discardableResult
    func deleteService(identifier: String, expectedInterface: String) throws -> Bool {
        let preferences = try session.preferences
        guard let service = StandalonePortRemoval.liveService(
            identifier: identifier, expectedInterface: expectedInterface, in: preferences)
        else { return false }
        guard !isDryRun else { return false }
        try session.lock()
        try session.check(SCNetworkServiceRemove(service), "Delete the service")
        return true
    }

    func pushBridgeConfiguration() throws {
        guard !isDryRun else { return }
        try BridgeSPI.updateConfiguration(in: try session.preferences)
    }

    func commitAndApply() throws {
        try session.commit()
        try session.apply()
    }
}
