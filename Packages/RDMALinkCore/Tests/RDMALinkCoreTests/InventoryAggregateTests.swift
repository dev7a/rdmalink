import Testing
@testable import RDMALinkCore

/// The one entry point the app and the CLI read this Mac through, and the one
/// thing it does that neither half does alone: put the ports in the order they
/// are in on the chassis.
@Suite("The inventory aggregate")
struct InventoryAggregateTests {

    /// Mac15,14 as read on 2026-09-19. Receptacle 1 is the *rightmost* back
    /// port, which is exactly why receptacle order is not physical order.
    private static let studioSixEnrichment: [Int: ReceptacleEnrichment] = [
        1: .init(position: PortPosition.parse("back-right"), deviceAttached: true),
        2: .init(position: PortPosition.parse("back-right-middle"), deviceAttached: true),
        3: .init(position: PortPosition.parse("back-left-middle"), deviceAttached: true),
        4: .init(position: PortPosition.parse("back-left"), deviceAttached: false),
        5: .init(position: PortPosition.parse("front-right"), deviceAttached: true),
        6: .init(position: PortPosition.parse("front-left"), deviceAttached: true),
    ]

    private static func port(_ receptacle: Int, _ bsdName: String, _ name: String,
                             face: PortFace?, link: LinkState = .empty) -> ThunderboltPort {
        ThunderboltPort(
            id: bsdName, receptacle: receptacle, bsdName: bsdName,
            face: face, positionName: name, link: link
        )
    }

    private static let studioSixPorts: [ThunderboltPort] = [
        port(1, "en2", "Back, far right", face: .back, link: .device),
        port(2, "en3", "Back, middle right", face: .back, link: .device),
        port(3, "en4", "Back, middle left", face: .back, link: .device),
        port(4, "en5", "Back, far left", face: .back),
        port(5, "en6", "Front, right", face: .front, link: .macLinked),
        port(6, "en7", "Front, left", face: .front, link: .macLinked),
    ]

    @Test("Ports come back left to right, back before front — not in receptacle order")
    func ordersPhysically() {
        let sorted = Inventory.sortedPhysically(
            Self.studioSixPorts.shuffled(), enrichment: Self.studioSixEnrichment
        )
        #expect(sorted.map(\.positionName) == [
            "Back, far left", "Back, middle left", "Back, middle right", "Back, far right",
            "Front, left", "Front, right",
        ])
        #expect(sorted.map(\.receptacle) == [4, 3, 2, 1, 6, 5])
    }

    @Test("A Mac that publishes no positions keeps the order macOS reported")
    func fallsBackToReceptacleOrder() {
        let sorted = Inventory.sortedPhysically(Self.studioSixPorts.shuffled(), enrichment: [:])
        #expect(sorted.map(\.receptacle) == [1, 2, 3, 4, 5, 6])
    }

    @Test("A port this Mac would not place sorts after the ones it would")
    func unplacedPortsComeLast() {
        var enrichment = Self.studioSixEnrichment
        enrichment[3] = nil
        let sorted = Inventory.sortedPhysically(Self.studioSixPorts, enrichment: enrichment)
        #expect(sorted.map(\.receptacle) == [4, 2, 1, 6, 5, 3])
    }

    @Test("A linked Mac is what the refusals see as a linked Mac")
    func mapsOntoObservedPorts() {
        let inventory = Inventory(
            model: HardwareModel(identifier: "Mac15,14", marketingName: "Mac Studio",
                                 chip: "M3 Ultra", archetype: .studioSix),
            ports: Self.studioSixPorts,
            rdma: .on(devices: ["rdma_en6"])
        )
        #expect(inventory.thunderboltBSDNames == ["en2", "en3", "en4", "en5", "en6", "en7"])
        let observed = inventory.observedPorts
        #expect(observed.map(\.hasLinkedMac) == [false, false, false, false, true, true])
        #expect(observed.map(\.positionName) == Self.studioSixPorts.map(\.positionName))
        // Two Macs on two standalone ports is a finished set-up, not R1.
        #expect(observed.allSatisfy { $0.bridges.isEmpty })
        #expect(Refusals.oneCableOnly(observed) == nil)
        // Put both cables' ports in the bridge and the aggregate feeds R1.
        var bridged = inventory
        let membership = ThunderboltPort.BridgeMembership(
            name: "bridge0", displayName: "Thunderbolt Bridge", isUp: true, source: .both)
        for index in bridged.ports.indices where bridged.ports[index].link == .macLinked {
            bridged.ports[index].apply(bridges: [membership], linkLocal: [])
        }
        #expect(bridged.observedPorts.map(\.bridges)
            == [[], [], [], [], ["bridge0"], ["bridge0"]])
        #expect(Refusals.oneCableOnly(bridged.observedPorts)?.code == .twoMacsConnected)
    }

    @Test("This Mac reads end to end through one call")
    func readsThisMac() throws {
        let inventory = try Inventory.read()
        print("inventory: \(inventory.model.identifier) · \(inventory.model.marketingName) "
            + "· \(inventory.model.chip) · rdma \(inventory.rdma)")
        for port in inventory.ports {
            print("  \(port.positionName) · \(port.bsdName) · receptacle \(port.receptacle) "
                + "· \(port.link) · bridges \(port.bridges) · \(port.linkLocal)")
        }
        // A Thunderbolt port always has an interface name; a USB-only row from
        // the chassis catalogue never does, which is how everything downstream
        // tells them apart.
        #expect(inventory.ports.filter { $0.isThunderbolt }.allSatisfy { !$0.bsdName.isEmpty })
        #expect(inventory.ports.filter { !$0.isThunderbolt }.allSatisfy { $0.bsdName.isEmpty })
        #expect(Set(inventory.ports.map(\.id)).count == inventory.ports.count)
        #expect(inventory.observedPorts.map(\.bsdName) == inventory.ports.map(\.bsdName))
        // Back comes before front on every Mac that says which is which.
        let faces = inventory.ports.compactMap(\.face).map(\.physicalRank)
        #expect(faces == faces.sorted())
    }
}

extension InventoryAggregateTests {
    @Test("A looped cable is what the refusals see as a looped cable")
    func mapsLoopedBackOntoObservedPorts() {
        var ports = Self.studioSixPorts
        ports[3].loopedBackTo = "en6"
        ports[4].loopedBackTo = "en5"
        let inventory = Inventory(
            model: HardwareModel(identifier: "Mac15,14", marketingName: "Mac Studio",
                                 chip: "M3 Ultra", archetype: .studioSix),
            ports: ports,
            rdma: .off
        )
        #expect(inventory.observedPorts.map(\.loopedBackTo) == [nil, nil, nil, "en6", "en5", nil])
        #expect(Refusals.loopedBackIntoThisMac(inventory.observedPorts)?.subjects == ["en5", "en6"])
        #expect(OperationPort(ports[3]).observed.loopedBackTo == "en6")
        #expect(Refusals.loopedBackIntoThisMac(Self.studioSixPorts.map(\.observed)) == nil)
    }
}
