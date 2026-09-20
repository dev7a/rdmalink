import Foundation
import Testing
@testable import RDMALinkCore

private let bridgedFixture = """
bridge0: flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST> mtu 1500
    member: en6 flags=3<LEARNING,DISCOVER>
    status: inactive
en6: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    inet6 fe80::6%en6 prefixlen 64 scopeid 0x15
    status: active
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    inet 10.77.78.1 netmask 0xfffffff8 broadcast 10.77.78.7
    status: active
"""

private let standaloneFixture = """
en6: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    inet6 fe80::6%en6 prefixlen 64 scopeid 0x15
    status: active
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    inet 10.77.78.1 netmask 0xfffffff8 broadcast 10.77.78.7
    status: active
"""

private let port = ObservedPort(bsdName: "en6", positionName: "Back, far left")

/// One Thunderbolt port, one Mac on the end at most, and Ethernet as the way in.
private func context(
    ports: [ObservedPort] = [port],
    primary: [String] = ["en0"]
) -> PreflightContext {
    PreflightContext(observedPorts: ports, thunderboltBSDNames: ports.map(\.bsdName),
                     primaryInterfaces: primary)
}

private func snapshot(_ text: String) -> InterfaceSnapshot {
    InterfaceSnapshot(interfaces: InterfaceSnapshot.parse(text))
}

private let manualIPv4 = ProtocolConfiguration(isEnabled: true, configMethod: "Manual",
                                               hasManualAddresses: true)

@Suite("What setting up a port would change")
struct StandalonePortPlanTests {
    @Test("The service is named the way the review screen says it will be")
    func namesTheService() {
        #expect(StandalonePortSetup.serviceName(for: "Back, far left") == "RDMA — Back, far left")
    }

    @Test("A standalone port with nothing on it is ready to go")
    func plansACleanPort() {
        let plan = StandalonePortSetup(port: port)
            .preview(snapshot: snapshot(standaloneFixture), services: [], context: context())
        #expect(plan.canProceed)
        #expect(plan.outcome == .setUp)
        #expect(plan.serviceName == "RDMA — Back, far left")
        #expect(plan.bridgesToLeave.isEmpty)
        #expect(plan.existing == .unconfigured(bridges: []))
    }

    @Test("A port still in a bridge is refused, and the bridge is named")
    func refusesAPortThatIsStillABridgeMember() {
        let plan = StandalonePortSetup(port: port).preview(
            snapshot: snapshot(bridgedFixture), services: [], context: context(),
            bridgeNames: ["bridge0": "Thunderbolt Bridge"])
        #expect(!plan.canProceed)
        #expect(plan.outcome == .refused)
        #expect(plan.bridgesToLeave == ["bridge0"])
        #expect(plan.refusal?.code == .portStillInBridge)
        #expect(plan.refusal?.body.contains("from Thunderbolt Bridge") == true)
    }

    @Test("A port with someone else's static IPv4 setup is refused, not rewritten")
    func refusesAForeignService() {
        let services = [NetworkServiceInfo(serviceID: "ABC", name: "Static link",
                                           interfaceBSDName: "en6", isEnabled: true,
                                           ipv4: manualIPv4, ipv6: nil)]
        let plan = StandalonePortSetup(port: port)
            .preview(snapshot: snapshot(standaloneFixture), services: services, context: context())
        #expect(!plan.canProceed)
        #expect(plan.refusal?.code == .foreignService)
        #expect(plan.refusal?.headline == "This port already has a setup RDMALink didn't make")
        #expect(plan.refusal?.body.contains(
            "a service on Back, far left with a fixed IPv4 address on it") == true)
    }

    @Test("Bridge membership is refused before anything else is looked at")
    func refusesTheBridgeFirst() {
        let services = [NetworkServiceInfo(serviceID: "ABC", name: "Static link",
                                           interfaceBSDName: "en6", isEnabled: true,
                                           ipv4: manualIPv4, ipv6: nil)]
        let plan = StandalonePortSetup(port: port)
            .preview(snapshot: snapshot(bridgedFixture), services: services, context: context())
        #expect(plan.refusal?.code == .portStillInBridge)
    }

    // MARK: - The two refusals one port cannot see

    @Test("A second Mac arriving while the review is on screen blocks the apply")
    func refusesTwoMacsAtReview() {
        // Both ports are still in the bridge, so the second cable is a loop.
        var left = port
        left.hasLinkedMac = true
        left.bridges = ["bridge0"]
        let right = ObservedPort(bsdName: "en7", positionName: "Back, far right",
                                 hasLinkedMac: true, bridges: ["bridge0"])
        let plan = StandalonePortSetup(port: left).preview(
            snapshot: snapshot(bridgedFixture), services: [],
            context: context(ports: [left, right]))
        #expect(!plan.canProceed)
        #expect(plan.refusal?.code == .twoMacsConnected)
    }

    @Test("Losing Wi-Fi while the review is on screen blocks the apply")
    func refusesWhenThunderboltBecomesTheOnlyRoute() {
        // The chosen port is standalone, but the Mac is reachable only over a
        // bridge that holds another Thunderbolt port — and removing a member
        // can blink the whole bridge, not just the port.
        let text = """
        bridge0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            member: en5 flags=3<LEARNING,DISCOVER>
            inet 10.1.1.4 netmask 0xffffff00 broadcast 10.1.1.255
            status: active
        en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            status: active
        en6: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet6 fe80::6%en6 prefixlen 64 scopeid 0x15
            status: active
        """
        let both = [ObservedPort(bsdName: "en5", positionName: "Back, far right"), port]
        let plan = StandalonePortSetup(port: port).preview(
            snapshot: snapshot(text), services: [],
            context: context(ports: both, primary: ["bridge0"]))
        #expect(!plan.canProceed)
        #expect(plan.refusal?.code == .onlyRouteIsThunderbolt)
    }

    // MARK: - Routing, not refusing (R27)

    @Test("A port already ready for RDMA routes to Adopt and offers no set-up button")
    func routesAReadyPortToAdopt() {
        let ready = NetworkServiceInfo(
            serviceID: "READY", name: "RDMA — Back, far left", interfaceBSDName: "en6",
            isEnabled: true,
            ipv4: ProtocolConfiguration(isEnabled: false, configMethod: nil,
                                        hasManualAddresses: false),
            ipv6: ProtocolConfiguration(isEnabled: true, configMethod: "LinkLocal",
                                        hasManualAddresses: false))
        let plan = StandalonePortSetup(port: port)
            .preview(snapshot: snapshot(standaloneFixture), services: [ready], context: context())
        #expect(plan.existing == .readyForRDMA(serviceID: "READY"))
        // The review screen keeps its default button on `canProceed` alone, and
        // `perform` throws for any port that already has a service.
        #expect(!plan.canProceed)
        #expect(plan.routesToAdopt)
        #expect(plan.outcome == .adopt(serviceID: "READY"))
        #expect(plan.refusal == nil)  // routing, not refusing
    }

    @Test("A hand-configured near match routes to Adopt too, never to set-up")
    func routesANearMatchToAdopt() {
        let near = NetworkServiceInfo(
            serviceID: "NEAR", name: "Thunderbolt en6", interfaceBSDName: "en6",
            isEnabled: true,
            ipv4: ProtocolConfiguration(isEnabled: true, configMethod: "DHCP",
                                        hasManualAddresses: false),
            ipv6: nil)
        let plan = StandalonePortSetup(port: port)
            .preview(snapshot: snapshot(standaloneFixture), services: [near], context: context())
        #expect(!plan.canProceed)
        #expect(plan.routesToAdopt)
    }
}

@Suite("What removing RDMALink's own service would do")
struct StandalonePortRemovalPlanTests {
    private static let record = CreatedServiceRecord(
        identifier: "ABC",
        interfaceBSDName: "en6",
        name: "RDMA — Back, far left",
        isEnabled: true,
        ipv4: ProtocolConfiguration(isEnabled: false, configMethod: nil, hasManualAddresses: false),
        ipv6: ProtocolConfiguration(isEnabled: true, configMethod: "LinkLocal",
                                    hasManualAddresses: false))

    private static func removal() -> StandalonePortRemoval {
        StandalonePortRemoval(port: port, record: record)
    }

    private static func asMade(name: String) -> NetworkServiceInfo {
        NetworkServiceInfo(
            serviceID: "ABC", name: name, interfaceBSDName: "en6", isEnabled: true,
            ipv4: record.ipv4, ipv6: record.ipv6)
    }

    @Test("The service is found by identifier, whatever it has been renamed to")
    func matchesByIdentifierOnly() {
        let plan = Self.removal().preview(services: [Self.asMade(name: "Renamed by hand")])
        #expect(plan.isAlreadyGone == false)
        #expect(plan.canProceed)
        #expect(plan.serviceName == "Renamed by hand")
        #expect(plan.interfaceBSDName == "en6")
        #expect(plan.differences.isEmpty)
    }

    @Test("A service someone already removed is not a failure")
    func noticesAnAlreadyRemovedService() {
        let services = [NetworkServiceInfo(serviceID: "OTHER", name: "RDMA — Back, far left",
                                           interfaceBSDName: "en6", isEnabled: true)]
        let plan = Self.removal().preview(services: services)
        #expect(plan.isAlreadyGone)
        #expect(plan.serviceName == nil)
    }

    @Test("A service that has been taken over is refused, not deleted")
    func refusesAnEditedService() throws {
        let takenOver = NetworkServiceInfo(
            serviceID: "ABC", name: "Lab Ethernet", interfaceBSDName: "en6", isEnabled: true,
            ipv4: manualIPv4, ipv6: Self.record.ipv6)
        let plan = Self.removal().preview(services: [takenOver])
        #expect(!plan.canProceed)
        let refusal = try #require(plan.refusal)
        #expect(refusal.code == .createdServiceEdited)
        #expect(refusal.headline == "This port's service isn't the one RDMALink made any more")
        #expect(refusal.subjects == ["en6"])
        #expect(plan.differences.count == 1)
    }

    @Test("A note whose identifier names a service on another port deletes nothing")
    func neverDeletesAnotherPortsService() {
        let wifi = NetworkServiceInfo(
            serviceID: "ABC", name: "Wi-Fi", interfaceBSDName: "en1", isEnabled: true,
            ipv4: ProtocolConfiguration(isEnabled: true, configMethod: "DHCP",
                                        hasManualAddresses: false),
            ipv6: nil)
        let plan = Self.removal().preview(services: [wifi])
        // Treated as gone, which is the one outcome that removes nothing.
        #expect(plan.isAlreadyGone)
        #expect(plan.refusal == nil)
        #expect(plan.interfaceBSDName == "en1")
    }
}

@Suite("Moving one member in and out of a bridge")
struct BridgeMembershipChangeTests {
    private static let note = BridgeMembership(
        bridgeName: "bridge0",
        serviceIdentifier: "B0B0B0B0-0000-0000-0000-000000000001",
        displayName: "Thunderbolt Bridge",
        members: ["en5", "en6", "en7", "en8"],
        isActive: true)

    private static let live = BridgeSPI.Membership(
        bsdName: "bridge0", displayName: "Thunderbolt Bridge",
        members: ["en5", "en6", "en7", "en8"])

    @Test("Leaving takes out exactly one member and leaves the rest alone")
    func previewsALeave() {
        let plan = BridgeMembershipChange(port: port, bridge: Self.note, direction: .leave)
            .preview(bridges: [Self.live])
        #expect(plan.membersBefore == ["en5", "en6", "en7", "en8"])
        #expect(plan.membersAfter == ["en5", "en7", "en8"])
        #expect(!plan.isAlreadyDone)
        #expect(plan.bridgeDisplayName == "Thunderbolt Bridge")
    }

    @Test("Rejoining puts the port back where the note says it sat")
    func previewsARejoin() {
        let without = BridgeSPI.Membership(bsdName: "bridge0", displayName: "Thunderbolt Bridge",
                                           members: ["en5", "en7", "en8"])
        let plan = BridgeMembershipChange(port: port, bridge: Self.note,
                                          direction: .rejoin(position: 1))
            .preview(bridges: [without])
        #expect(plan.membersAfter == ["en5", "en6", "en7", "en8"])
        #expect(!plan.isAlreadyDone)
    }

    @Test("A bridge that is already in the state asked for has nothing to do")
    func noticesThereIsNothingToDo() {
        let without = BridgeSPI.Membership(bsdName: "bridge0", members: ["en5", "en7", "en8"])
        let leave = BridgeMembershipChange(port: port, bridge: Self.note, direction: .leave)
            .preview(bridges: [without])
        #expect(leave.isAlreadyDone)
        #expect(leave.membersAfter == without.members)

        let rejoin = BridgeMembershipChange(port: port, bridge: Self.note,
                                            direction: .rejoin(position: 1))
            .preview(bridges: [Self.live])
        #expect(rejoin.isAlreadyDone)
    }

    @Test("A position past the end of the list goes on the end")
    func clampsThePosition() {
        let without = BridgeSPI.Membership(bsdName: "bridge0", members: ["en5"])
        let plan = BridgeMembershipChange(port: port, bridge: Self.note,
                                          direction: .rejoin(position: 9))
            .preview(bridges: [without])
        #expect(plan.membersAfter == ["en5", "en6"])
    }
}
