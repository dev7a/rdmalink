import Foundation
import Testing
@testable import RDMALinkCore

// The fakes the whole-flow operations are driven through. The operations own
// sequencing, verification and rollback; everything under them — the
// authorized session, the bridge SPI and the kernel — is replaced here, so a
// test can prove the order of a burst without a credential and without
// touching this Mac's network.

/// One call the burst made. `readKernel` is deliberately not recorded: the
/// verification loop makes many, and they would bury the writes.
enum WriterCall: Equatable, CustomStringConvertible {
    case lock
    case removeMember(port: String, bridge: String)
    case addMember(port: String, bridge: String, position: Int?)
    case createService(interface: String, name: String)
    case deleteService(identifier: String, expecting: String)
    case commitAndApply

    var description: String {
        switch self {
        case .lock: "lock"
        case let .removeMember(port, bridge): "remove \(port) from \(bridge)"
        case let .addMember(port, bridge, position): "add \(port) to \(bridge) at \(position.map(String.init) ?? "end")"
        case let .createService(interface, name): "create \(name) on \(interface)"
        case let .deleteService(identifier, expecting): "delete \(identifier) on \(expecting)"
        case .commitAndApply: "commit"
        }
    }
}

/// Mutable state a kernel closure can read without capturing the writer.
final class KernelState {
    var reads = 0
    /// How many member additions the writer has taken, so a kernel closure
    /// can follow the first attempt and only agree after a rewrite.
    var membersAdded = 0
}

final class FakeWriter: NetworkWriter {
    /// Every write, in order.
    private(set) var calls: [WriterCall] = []
    /// How many times `ifconfig` was read.
    let state = KernelState()

    var servicesValue: [NetworkServiceInfo] = []
    var serviceOrderValue: [String] = []
    /// The stored configuration as the **session** holds it, and every member
    /// write below edits this copy — exactly as the bridge SPI edits an open
    /// `SCPreferences`.
    ///
    /// A test that does not set one gets a mirror of the kernel as it is at
    /// **read zero**, which is the ordinary state of a Mac: the two agree. The
    /// kernel closure is asked with a fresh ``KernelState`` and the writer's
    /// own read counter is left alone, so the value does not depend on when it
    /// is first touched — a test whose kernel varies by read count gets the
    /// same stored configuration either way. Set it explicitly to make the two
    /// disagree, which is the state this whole seam exists for.
    var bridgesValue: [BridgeSPI.Membership] {
        get {
            if let sessionBridges { return sessionBridges }
            let mirrored = FakeWriter.mirror(kernel(KernelState()))
            sessionBridges = mirrored
            return mirrored
        }
        set { sessionBridges = newValue }
    }

    private var sessionBridges: [BridgeSPI.Membership]?
    /// What a fresh, unprivileged handle would see: only what has been
    /// committed. `nil` until the first `commitAndApply`.
    private var committedBridges: [BridgeSPI.Membership]?
    /// The value on disk before the session's first edit, so a read before any
    /// commit sees what is really there.
    private var bridgesBeforeEditing: [BridgeSPI.Membership]?
    /// When true, a fresh handle never sees the edits — the preferences keep
    /// listing the port however often the burst commits. The stored half of
    /// "macOS didn't actually let go of the port".
    var storedMembershipPersists = false

    /// What the kernel says, asked fresh on every read.
    var kernel: (KernelState) -> InterfaceSnapshot = { _ in InterfaceSnapshot(interfaces: []) }
    /// Returns the error a call should fail with, or `nil` to let it through.
    /// Called **before** the call takes effect.
    var intercept: (WriterCall) -> Error? = { _ in nil }
    /// Service identifiers the configuration currently holds.
    var presentServiceIDs: Set<String> = []
    var createdIdentifier = "NEW-SERVICE-ID"

    /// The stored configuration a Mac whose two reads agree would have.
    static func mirror(_ snapshot: InterfaceSnapshot) -> [BridgeSPI.Membership] {
        snapshot.interfaces.filter(\.isBridge).map {
            BridgeSPI.Membership(bsdName: $0.name,
                                 displayName: Fixtures.bridgeDisplayNames[$0.name],
                                 members: $0.members)
        }
    }

    private func record(_ call: WriterCall) throws {
        calls.append(call)
        if let error = intercept(call) { throw error }
    }

    func lock() throws { try record(.lock) }
    func services() throws -> [NetworkServiceInfo] { servicesValue }
    func serviceOrder() throws -> [String] { serviceOrderValue }
    func bridges() throws -> [BridgeSPI.Membership] { bridgesValue }

    func readStoredBridges() throws -> [BridgeSPI.Membership] {
        if storedMembershipPersists { return bridgesBeforeEditing ?? bridgesValue }
        return committedBridges ?? bridgesBeforeEditing ?? bridgesValue
    }

    func readKernel() throws -> InterfaceSnapshot {
        state.reads += 1
        return kernel(state)
    }

    func removeMember(_ bsdName: String, from bridge: BridgeMembership) throws {
        try record(.removeMember(port: bsdName, bridge: bridge.bridgeName))
        edit(bridge.bridgeName) { $0.removeAll { $0 == bsdName } }
    }

    func addMember(_ bsdName: String, to bridge: BridgeMembership, at position: Int?) throws {
        try record(.addMember(port: bsdName, bridge: bridge.bridgeName, position: position))
        // The SPI refuses a member it already has; so does the fake, so an
        // operation that tolerates it is exercised rather than assumed.
        if bridgesValue.first(where: { $0.bsdName == bridge.bridgeName })?
            .members.contains(bsdName) == true {
            throw BridgeSPIError.alreadyMember(bsdName: bsdName, bridge: bridge.bridgeName)
        }
        edit(bridge.bridgeName) { members in
            members.insert(bsdName, at: min(max(position ?? members.count, 0), members.count))
        }
        state.membersAdded += 1
    }

    /// One member-list edit on the session's copy, remembering what was on
    /// disk before the first one.
    private func edit(_ bridgeName: String, _ change: (inout [String]) -> Void) {
        if bridgesBeforeEditing == nil { bridgesBeforeEditing = bridgesValue }
        guard let index = bridgesValue.firstIndex(where: { $0.bsdName == bridgeName }) else {
            return
        }
        change(&bridgesValue[index].members)
    }

    func createService(on bsdName: String, named name: String) throws -> CreatedServiceRecord {
        try record(.createService(interface: bsdName, name: name))
        presentServiceIDs.insert(createdIdentifier)
        return CreatedServiceRecord(
            identifier: createdIdentifier, interfaceBSDName: bsdName, name: name,
            isEnabled: true, ipv4: Fixtures.ipv4Off, ipv6: Fixtures.ipv6LinkLocal)
    }

    @discardableResult
    func deleteService(identifier: String, expectedInterface: String) throws -> Bool {
        try record(.deleteService(identifier: identifier, expecting: expectedInterface))
        return presentServiceIDs.remove(identifier) != nil
    }

    func commitAndApply() throws {
        try record(.commitAndApply)
        committedBridges = bridgesValue
    }
}

enum Fixtures {
    static let ipv4Off = ProtocolConfiguration(isEnabled: false, configMethod: "Off",
                                               hasManualAddresses: false)
    static let ipv6LinkLocal = ProtocolConfiguration(
        isEnabled: true, configMethod: NetworkServices.linkLocalMethod,
        hasManualAddresses: false)
    static let ipv6Automatic = ProtocolConfiguration(isEnabled: true, configMethod: "Automatic",
                                                     hasManualAddresses: false)
    static let ipv4Manual = ProtocolConfiguration(isEnabled: true, configMethod: "Manual",
                                                  hasManualAddresses: true)

    /// en6 in bridge0, with Ethernet as the way in so R5 is satisfied.
    static let inOneBridge = """
        bridge0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            member: en5 flags=3<LEARNING,DISCOVER>
            member: en6 flags=3<LEARNING,DISCOVER>
            status: active
        en6: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            status: active
        en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet 10.77.78.1 netmask 0xfffffff8 broadcast 10.77.78.7
            status: active
        """

    /// en6 in bridge0 and in a bridge1 that is down.
    static let inTwoBridges = """
        bridge0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            member: en5 flags=3<LEARNING,DISCOVER>
            member: en6 flags=3<LEARNING,DISCOVER>
            status: active
        bridge1: flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST> mtu 1500
            member: en6 flags=3<LEARNING,DISCOVER>
            member: en9 flags=3<LEARNING,DISCOVER>
            status: inactive
        en6: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            status: active
        en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet 10.77.78.1 netmask 0xfffffff8 broadcast 10.77.78.7
            status: active
        """

    /// en6 down with nothing on it: what a port looks like once its service
    /// is gone, and the state the kernel will take it into a bridge from.
    static let quiet = """
        bridge0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            member: en5 flags=3<LEARNING,DISCOVER>
            status: active
        en6: flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST> mtu 1500
            status: inactive
        en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet 10.77.78.1 netmask 0xfffffff8 broadcast 10.77.78.7
            status: active
        """

    /// en6 out of every bridge.
    static let standalone = """
        bridge0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            member: en5 flags=3<LEARNING,DISCOVER>
            status: active
        en6: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet6 fe80::6%en6 prefixlen 64 scopeid 0x15
            status: active
        en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet 10.77.78.1 netmask 0xfffffff8 broadcast 10.77.78.7
            status: active
        """

    static func snapshot(_ text: String) -> InterfaceSnapshot {
        InterfaceSnapshot(interfaces: InterfaceSnapshot.parse(text))
    }

    static let port = OperationPort(bsdName: "en6", receptacle: 1,
                                    positionName: "Back, far left", link: .macLinked,
                                    linkLocalAddresses: ["fe80::6"])

    /// The Mac these fixtures describe: one the identifier catalogue lists,
    /// so R31 stays out of every test that is not about it.
    static let studio = HardwareModel(
        identifier: "Mac16,9", marketingName: "Mac Studio", chip: "M4 Max",
        archetype: .studioFour)

    /// A Mac neither rule in UX_SPEC §4.7 recognizes — R31's input.
    static let unrecognized = HardwareModel(
        identifier: "Mac99,99", marketingName: "Mac", chip: "M9 Max", archetype: .unknown)

    static let bridge0 = BridgeSPI.Membership(bsdName: "bridge0",
                                              displayName: "Thunderbolt Bridge",
                                              members: ["en5", "en6"])
    static let bridge1 = BridgeSPI.Membership(bsdName: "bridge1",
                                              displayName: "Thunderbolt Bridge 2",
                                              members: ["en6", "en9"])

    /// What System Settings calls the bridges in these fixtures.
    static let bridgeDisplayNames = [
        "bridge0": "Thunderbolt Bridge",
        "bridge1": "Thunderbolt Bridge 2",
    ]

    /// A whole world, with Ethernet as the management path unless told otherwise.
    ///
    /// - Parameter bridges: the stored configuration. `nil` mirrors the
    ///   `ifconfig` text, which is the ordinary state of a Mac — the two reads
    ///   agree. Pass one explicitly to make them disagree.
    static func world(
        ifconfig: String,
        services: [NetworkServiceInfo] = [],
        bridges: [BridgeSPI.Membership]? = nil,
        ports: [OperationPort] = [port],
        primary: [String] = ["en0"],
        mounted: [MountedVolume] = [],
        notesAreWritable: Refusal? = nil,
        rdma: RDMAStatus = .off,
        hardware: HardwareModel = studio
    ) -> ObservedWorld {
        var world = ObservedWorld(
            snapshot: snapshot(ifconfig),
            services: services,
            serviceOrder: services.map(\.serviceID),
            bridges: bridges ?? FakeWriter.mirror(snapshot(ifconfig)),
            context: PreflightContext(hardware: hardware,
                                      observedPorts: [],
                                      thunderboltBSDNames: ports.map(\.bsdName),
                                      primaryInterfaces: primary),
            rdma: rdma,
            mountedVolumes: mounted,
            notesAreWritable: notesAreWritable)
        // The `ifconfig` text and the stored bridges are the one description
        // of membership here, as `Inventory.readPorts` is on a real Mac: the
        // observed ports R1 reads take their bridges from the world.
        world.context.observedPorts = ports.map { port in
            var observed = port.observed
            observed.bridges = world.bridges(containing: port.bsdName)
            return observed
        }
        return world
    }

    /// A private notes folder per test, removed afterwards.
    static func store() -> BaselineStore {
        BaselineStore(directory: FileManager.default.temporaryDirectory
            .appending(path: "rdmalink-operations-\(UUID().uuidString)"))
    }

    static func environment(
        store: BaselineStore,
        policy: KernelWaitPolicy = quickPolicy,
        hardware: HardwareModel = studio
    ) -> OperationEnvironment {
        OperationEnvironment(
            hardware: hardware,
            store: store,
            log: ChangeLog(url: store.directory.appending(path: "changes.jsonl")),
            policy: policy)
    }

    /// Four reads and no real waiting, so a kernel that catches up late can be
    /// exercised without spending three seconds on it.
    ///
    /// The budget is wall clock and is left generous on purpose: with a no-op
    /// pause the loop spends only compute, and the default of twice the
    /// window — 60 ms — trips on a loaded machine and turns an R10 into an R8.
    /// Tests about the budget itself pass their own policy.
    static let quickPolicy = KernelWaitPolicy(
        window: .milliseconds(30), interval: .milliseconds(10), budget: .seconds(10),
        pause: { _ in })
}

/// Collects the checklist as the burst reports it.
final class ProgressLog {
    private(set) var rows: [(step: OperationStep, state: StepState)] = []
    var text: [String] { rows.map { "\($0.state) \($0.step.text($0.state))" } }
    func record(_ step: OperationStep, _ state: StepState) { rows.append((step, state)) }
}
