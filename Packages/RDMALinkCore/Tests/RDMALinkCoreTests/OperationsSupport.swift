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
    case push
    case commitAndApply

    var description: String {
        switch self {
        case .lock: "lock"
        case let .removeMember(port, bridge): "remove \(port) from \(bridge)"
        case let .addMember(port, bridge, position): "add \(port) to \(bridge) at \(position.map(String.init) ?? "end")"
        case let .createService(interface, name): "create \(name) on \(interface)"
        case let .deleteService(identifier, expecting): "delete \(identifier) on \(expecting)"
        case .push: "push"
        case .commitAndApply: "commit"
        }
    }
}

/// Mutable state a kernel closure can read without capturing the writer.
final class KernelState {
    var pushed = false
    var reads = 0
}

final class FakeWriter: NetworkWriter {
    var isDryRun = false
    var canPushBridgeConfiguration = true

    /// Every write, in order.
    private(set) var calls: [WriterCall] = []
    /// How many times `ifconfig` was read.
    let state = KernelState()

    var servicesValue: [NetworkServiceInfo] = []
    var serviceOrderValue: [String] = []
    var bridgesValue: [BridgeSPI.Membership] = []

    /// What the kernel says, asked fresh on every read.
    var kernel: (KernelState) -> InterfaceSnapshot = { _ in InterfaceSnapshot(interfaces: []) }
    /// Returns the error a call should fail with, or `nil` to let it through.
    /// Called **before** the call takes effect.
    var intercept: (WriterCall) -> Error? = { _ in nil }
    /// Service identifiers the configuration currently holds.
    var presentServiceIDs: Set<String> = []
    var createdIdentifier = "NEW-SERVICE-ID"

    private func record(_ call: WriterCall) throws {
        calls.append(call)
        if let error = intercept(call) { throw error }
    }

    func lock() throws { try record(.lock) }
    func services() throws -> [NetworkServiceInfo] { servicesValue }
    func serviceOrder() throws -> [String] { serviceOrderValue }
    func bridges() throws -> [BridgeSPI.Membership] { bridgesValue }

    func readKernel() throws -> InterfaceSnapshot {
        state.reads += 1
        return kernel(state)
    }

    func removeMember(_ bsdName: String, from bridge: BridgeMembership) throws {
        try record(.removeMember(port: bsdName, bridge: bridge.bridgeName))
    }

    func addMember(_ bsdName: String, to bridge: BridgeMembership, at position: Int?) throws {
        try record(.addMember(port: bsdName, bridge: bridge.bridgeName, position: position))
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

    func pushBridgeConfiguration() throws {
        state.pushed = true
        try record(.push)
    }

    func commitAndApply() throws { try record(.commitAndApply) }
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

    static let bridge0 = BridgeSPI.Membership(bsdName: "bridge0",
                                              displayName: "Thunderbolt Bridge",
                                              members: ["en5", "en6"])
    static let bridge1 = BridgeSPI.Membership(bsdName: "bridge1",
                                              displayName: "Thunderbolt Bridge 2",
                                              members: ["en6", "en9"])

    /// A whole world, with Ethernet as the management path unless told otherwise.
    static func world(
        ifconfig: String,
        services: [NetworkServiceInfo] = [],
        bridges: [BridgeSPI.Membership] = [bridge0],
        ports: [OperationPort] = [port],
        primary: [String] = ["en0"],
        mounted: [MountedVolume] = [],
        notesAreWritable: Refusal? = nil,
        rdma: RDMAStatus = .off
    ) -> ObservedWorld {
        ObservedWorld(
            snapshot: snapshot(ifconfig),
            services: services,
            serviceOrder: services.map(\.serviceID),
            bridges: bridges,
            context: PreflightContext(observedPorts: ports.map(\.observed),
                                      thunderboltBSDNames: ports.map(\.bsdName),
                                      primaryInterfaces: primary),
            rdma: rdma,
            mountedVolumes: mounted,
            notesAreWritable: notesAreWritable)
    }

    /// A private notes folder per test, removed afterwards.
    static func store() -> BaselineStore {
        BaselineStore(directory: FileManager.default.temporaryDirectory
            .appending(path: "rdmalink-operations-\(UUID().uuidString)"))
    }

    static func environment(
        store: BaselineStore,
        policy: KernelWaitPolicy = quickPolicy
    ) -> OperationEnvironment {
        OperationEnvironment(
            archetype: .studioFour,
            store: store,
            log: ChangeLog(url: store.directory.appending(path: "changes.jsonl")),
            policy: policy)
    }

    /// Four reads and no real waiting, so a kernel that catches up late can be
    /// exercised without spending three seconds on it.
    static let quickPolicy = KernelWaitPolicy(
        window: .milliseconds(30), interval: .milliseconds(10), pause: { _ in })
}

/// Collects the checklist as the burst reports it.
final class ProgressLog {
    private(set) var rows: [(step: OperationStep, state: StepState)] = []
    var text: [String] { rows.map { "\($0.state) \($0.step.text($0.state))" } }
    func record(_ step: OperationStep, _ state: StepState) { rows.append((step, state)) }
}
