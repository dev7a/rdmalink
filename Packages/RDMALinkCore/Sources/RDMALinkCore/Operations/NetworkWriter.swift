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
    /// Takes the configuration lock. Fails rather than waits — two writers is
    /// how configurations get mangled (R12).
    func lock() throws

    func services() throws -> [NetworkServiceInfo]
    /// The identifiers of every service in the current location, in order.
    func serviceOrder() throws -> [String]
    /// Every bridge in the stored configuration as **this session** has it:
    /// the object the writes edit, uncommitted changes included.
    func bridges() throws -> [BridgeSPI.Membership]
    /// Every bridge in the stored configuration as a **fresh, unprivileged**
    /// handle sees it — which is what has actually been committed.
    ///
    /// The verification read. `bridges()` would answer out of the session's
    /// own copy and say yes to a removal that never reached the disk.
    func readStoredBridges() throws -> [BridgeSPI.Membership]
    /// The kernel's own answer, from `ifconfig -a`. One of the two places
    /// membership is real; ``readStoredBridges()`` is the other.
    func readKernel() throws -> InterfaceSnapshot

    func removeMember(_ bsdName: String, from bridge: BridgeMembership) throws
    func addMember(_ bsdName: String, to bridge: BridgeMembership, at position: Int?) throws
    func createService(on bsdName: String, named name: String) throws -> CreatedServiceRecord
    /// Deletes a service by identifier, and only while it is still on
    /// `expectedInterface`. `false` means it was already gone — which is a
    /// success, not a failure.
    @discardableResult
    func deleteService(identifier: String, expectedInterface: String) throws -> Bool

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

    /// A **fresh** handle every time, deliberately: the point of this read is
    /// to see what landed on disk, not what the session is holding.
    func readStoredBridges() throws -> [BridgeSPI.Membership] {
        let reading = StoredBridges.read()
        // An unreadable configuration is not an empty one, and the difference
        // is the whole point here: `[]` would read as "the port is out of
        // every bridge" and sign off a removal nobody observed. The two reads
        // underneath keep the distinction rather than flatten it — a failed
        // `SCBridgeInterfaceCopyAll` throws instead of answering `[]`, and the
        // preferences file is tried next — so `.unavailable` really does mean
        // neither of them answered.
        guard reading.source != .unavailable else {
            throw NetworkConfigurationError.missing("the stored bridge configuration")
        }
        return reading.bridges
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
        try session.lock()
        try BridgeSPI.removeMember(bsdName: bsdName, from: resolved)
    }

    func addMember(_ bsdName: String, to bridge: BridgeMembership, at position: Int?) throws {
        try BridgeSPI.requireMembershipEditing()
        let preferences = try session.preferences
        let (resolved, _) = try BridgeSPI.resolveRecorded(bridge, in: preferences)
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
        try session.lock()
        try session.check(SCNetworkServiceRemove(service), "Delete the service")
        return true
    }

    func commitAndApply() throws {
        try session.commit()
        try session.apply()
    }
}
