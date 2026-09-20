import Foundation
import Testing
@testable import RDMALinkCore

@Suite("Thunderbolt ports")
struct InventoryPortTests {

    // MARK: Link status

    @Test("IOLinkStatus 3 is a linked Mac, 1 is not")
    func masksLinkStatus() {
        #expect(LinkState.from(linkStatus: 3, deviceAttached: nil) == .macLinked)
        #expect(LinkState.from(linkStatus: 3, deviceAttached: true) == .macLinked)
        #expect(LinkState.from(linkStatus: 1, deviceAttached: nil) == .empty)
        #expect(LinkState.from(linkStatus: 0, deviceAttached: nil) == .empty)
        #expect(LinkState.from(linkStatus: 2, deviceAttached: nil) == .empty)
    }

    @Test("Bits outside the mask are ignored")
    func ignoresOtherLinkBits() {
        // kIONetworkLinkNoNetworkChange and anything else the driver adds.
        #expect(LinkState.from(linkStatus: 7, deviceAttached: nil) == .macLinked)
        #expect(LinkState.from(linkStatus: 5, deviceAttached: false) == .empty)
    }

    @Test("A dock is only a dock when something says so")
    func dockNeedsEnrichment() {
        #expect(LinkState.from(linkStatus: 1, deviceAttached: true) == .device)
        #expect(LinkState.from(linkStatus: 1, deviceAttached: false) == .empty)
        // No enrichment at all: empty is the honest answer, not a guessed dock.
        #expect(LinkState.from(linkStatus: 1, deviceAttached: nil) == .empty)
    }

    // MARK: Device-tree decoding

    @Test("A phandle is four little-endian bytes")
    func decodesPhandles() {
        #expect(DeviceTree.phandle(Data([0x93, 0x00, 0x00, 0x00])) == 147)   // acio0 on Mac15,14
        #expect(DeviceTree.phandle(Data([0x17, 0x01, 0x00, 0x00])) == 279)   // acio4
        #expect(DeviceTree.phandle(Data([0x38, 0x01, 0x00, 0x00])) == 312)   // acio5
        #expect(DeviceTree.phandle(Data([0xff, 0xff, 0xff, 0xff])) == 0xFFFF_FFFF)
    }

    @Test("A phandle of the wrong length is nil, never truncated")
    func rejectsMalformedPhandles() {
        #expect(DeviceTree.phandle(Data()) == nil)
        #expect(DeviceTree.phandle(Data([0x93, 0x00, 0x00])) == nil)
        #expect(DeviceTree.phandle(Data([0x93, 0x00, 0x00, 0x00, 0x00])) == nil)
    }

    @Test("Device-tree strings are NUL-terminated bytes")
    func decodesDeviceTreeStrings() {
        #expect(DeviceTree.string(Data("back-left\0".utf8)) == "back-left")
        #expect(DeviceTree.string(Data("front-right".utf8)) == "front-right")
        #expect(DeviceTree.string(Data([0])) == nil)
        #expect(DeviceTree.string(Data()) == nil)
    }

    @Test("Only acioN nodes carry a Thunderbolt controller")
    func recognizesAcioNodeNames() {
        #expect(ChassisProbe.isAcioNodeName("acio0"))
        #expect(ChassisProbe.isAcioNodeName("acio5"))
        #expect(ChassisProbe.isAcioNodeName("acio12"))
        #expect(!ChassisProbe.isAcioNodeName("acio"))
        #expect(!ChassisProbe.isAcioNodeName("acio-cpu0"))
        #expect(!ChassisProbe.isAcioNodeName("acio-phy-cpu3"))
        #expect(!ChassisProbe.isAcioNodeName("aciox1"))
    }

    // MARK: The join

    /// Mac15,14 (Mac Studio, M3 Ultra) as read on 2026-09-19: six receptacles,
    /// a dock or display in the first three, nothing in the fourth, and a Mac
    /// linked on each front port.
    private static let studioSixRows: [PortInventory.PortRow] = [
        .init(receptacle: 1, bsdName: "en2", linkStatus: 1),
        .init(receptacle: 2, bsdName: "en3", linkStatus: 1),
        .init(receptacle: 3, bsdName: "en4", linkStatus: 1),
        .init(receptacle: 4, bsdName: "en5", linkStatus: 1),
        .init(receptacle: 5, bsdName: "en6", linkStatus: 3),
        .init(receptacle: 6, bsdName: "en7", linkStatus: 3),
    ]

    private static let studioSixEnrichment: [Int: ReceptacleEnrichment] = [
        1: .init(position: PortPosition.parse("back-right"), deviceAttached: true),
        2: .init(position: PortPosition.parse("back-right-middle"), deviceAttached: true),
        3: .init(position: PortPosition.parse("back-left-middle"), deviceAttached: true),
        4: .init(position: PortPosition.parse("back-left"), deviceAttached: false),
        5: .init(position: PortPosition.parse("front-right"), deviceAttached: true),
        6: .init(position: PortPosition.parse("front-left"), deviceAttached: true),
    ]

    @Test("A recorded Mac Studio assembles into the spec's names and states")
    func assemblesRecordedStudio() {
        let ports = PortInventory.assemble(
            rows: Self.studioSixRows.shuffled(),
            archetype: .studioSix,
            enrichment: Self.studioSixEnrichment
        )
        #expect(ports.map(\.receptacle) == [1, 2, 3, 4, 5, 6])
        #expect(ports.map(\.bsdName) == ["en2", "en3", "en4", "en5", "en6", "en7"])
        #expect(ports.map(\.positionName) == [
            "Back, far right", "Back, middle right", "Back, middle left", "Back, far left",
            "Front, right", "Front, left",
        ])
        #expect(ports.map(\.face) == [.back, .back, .back, .back, .front, .front])
        #expect(ports.map(\.link) == [.device, .device, .device, .empty, .macLinked, .macLinked])
        #expect(ports.allSatisfy { $0.isThunderbolt })
        #expect(ports.map(\.id) == ports.map(\.bsdName))
    }

    @Test("Without enrichment the same Mac is numbered, not mislabelled")
    func assemblesWithoutEnrichment() {
        let ports = PortInventory.assemble(
            rows: Self.studioSixRows, archetype: .studioSix, enrichment: [:]
        )
        #expect(ports.map(\.positionName) == (1...6).map { "Thunderbolt port \($0)" })
        #expect(ports.allSatisfy { $0.face == nil })
        // A dock now reads as empty rather than as a device that was guessed at.
        #expect(ports.map(\.link) == [.empty, .empty, .empty, .empty, .macLinked, .macLinked])
    }

    @Test("An unrecognized Mac keeps its faces but numbers its ports")
    func assemblesUnknownArchetype() {
        let ports = PortInventory.assemble(
            rows: Self.studioSixRows,
            archetype: .unknown,
            enrichment: Self.studioSixEnrichment
        )
        #expect(ports.map(\.positionName) == (1...6).map { "Thunderbolt port \($0)" })
        #expect(ports.map(\.face) == [.back, .back, .back, .back, .front, .front])
    }

    @Test("Enrichment for a receptacle that is not there is ignored")
    func ignoresStrayEnrichment() {
        let ports = PortInventory.assemble(
            rows: [.init(receptacle: 2, bsdName: "en3", linkStatus: 1)],
            archetype: .studioSix,
            enrichment: Self.studioSixEnrichment
        )
        #expect(ports.count == 1)
        #expect(ports[0].positionName == "Back, middle right")
    }

    // MARK: The merge point

    @Test("Bridges and addresses merge in without disturbing the hardware facts")
    func mergesBridgesAndAddresses() {
        var port = PortInventory.assemble(
            rows: [Self.studioSixRows[4]],
            archetype: .studioSix,
            enrichment: Self.studioSixEnrichment
        )[0]
        #expect(port.bridges.isEmpty)
        #expect(port.linkLocal.isEmpty)

        port.apply(
            bridges: [
                .init(name: "bridge0", displayName: "Thunderbolt Bridge", isUp: true),
                .init(name: "bridge4", isUp: false),
            ],
            linkLocal: ["fe80::1c3d:5aff:fe22:9b04"]
        )
        #expect(port.bridges.map(\.name) == ["bridge0", "bridge4"])
        #expect(port.bridges.map(\.displayName) == ["Thunderbolt Bridge", nil])
        #expect(port.bridges.map(\.isUp) == [true, false])
        #expect(port.linkLocal == ["fe80::1c3d:5aff:fe22:9b04"])
        #expect(port.link == .macLinked)
        #expect(port.positionName == "Front, right")

        port.apply(bridges: [], linkLocal: [])
        #expect(port.bridges.isEmpty)
        #expect(port.linkLocal.isEmpty)
    }
}

/// The Thunderbolt domain identities behind R2, as `ioreg` printed them on the
/// rig on 2026-09-20 (Mac Studio M3 Ultra, macOS 27.2): six local nodes, one
/// per receptacle, and two cross-domain links — both to the MacBook Pro
/// (`Mac17,7`) on the front ports. Docks and empty receptacles have no link.
@Suite("Thunderbolt domain identity")
struct DomainIdentityTests {
    private static let acio0 = "25FABFC5-ADB1-4CFF-8F2C-B0DDB355D95E"
    private static let acio1 = "E9444509-1D36-41AA-89C5-D898E7747649"
    private static let acio2 = "177E0353-6447-4F22-AB8B-276E12B7E3B9"
    private static let acio3 = "8FE237A7-666F-4AF5-A6C1-B63C1B260260"
    private static let acio4 = "54719E74-925A-4EED-A4CD-766B620335E0"
    private static let acio5 = "F09EA43C-9CF8-4ABC-8952-C32AB6983451"
    /// The MacBook's two controllers, as this Mac's XDomain links report them.
    private static let macBookOnEn6 = "537F4213-9E40-4E35-A37A-762A2ACCA158"
    private static let macBookOnEn7 = "C353FA51-755F-4DEE-9A09-27C2ED2ACEA2"

    private static let rig: [PortInventory.PortRow] = [
        .init(receptacle: 1, bsdName: "en2", linkStatus: 1, domainUUID: acio0),
        .init(receptacle: 2, bsdName: "en3", linkStatus: 1, domainUUID: acio1),
        .init(receptacle: 3, bsdName: "en4", linkStatus: 1, domainUUID: acio2),
        .init(receptacle: 4, bsdName: "en5", linkStatus: 1, domainUUID: acio3),
        .init(receptacle: 5, bsdName: "en6", linkStatus: 3, domainUUID: acio4,
              peerDomainUUIDs: [macBookOnEn6]),
        .init(receptacle: 6, bsdName: "en7", linkStatus: 3, domainUUID: acio5,
              peerDomainUUIDs: [macBookOnEn7]),
    ]

    /// The rig with one cable moved: en5's far end is now en6, and en6's is en5.
    private static let looped: [PortInventory.PortRow] = [
        rig[0], rig[1], rig[2],
        .init(receptacle: 4, bsdName: "en5", linkStatus: 3, domainUUID: acio3,
              peerDomainUUIDs: [acio4]),
        .init(receptacle: 5, bsdName: "en6", linkStatus: 3, domainUUID: acio4,
              peerDomainUUIDs: [acio3]),
        rig[5],
    ]

    @Test("A Domain UUID is compared in one spelling, and only when it is a UUID")
    func parsesDomainUUID() {
        #expect(PortInventory.domainUUID(Self.acio4) == Self.acio4)
        #expect(PortInventory.domainUUID(Self.acio4.lowercased()) == Self.acio4)
        #expect(PortInventory.domainUUID(" \(Self.acio4)\n") == Self.acio4)
        #expect(PortInventory.domainUUID("") == nil)
        #expect(PortInventory.domainUUID("Mac17,7") == nil)
        #expect(PortInventory.domainUUID("54719E74-925A-4EED-A4CD") == nil)
    }

    @Test("Two cables to another Mac are not a loop")
    func rigIsNotLooped() {
        #expect(PortInventory.loopedBackPartners(Self.rig).isEmpty)
        let ports = PortInventory.assemble(rows: Self.rig, archetype: .studioSix, enrichment: [:])
        #expect(ports.allSatisfy { $0.loopedBackTo == nil })
        #expect(ports.map(\.domainUUID) == [Self.acio0, Self.acio1, Self.acio2, Self.acio3,
                                            Self.acio4, Self.acio5])
        #expect(ports.map(\.peerDomainUUIDs) == [[], [], [], [], [Self.macBookOnEn6],
                                                 [Self.macBookOnEn7]])
    }

    @Test("A cable whose far end is another receptacle of this Mac pairs the two")
    func pairsALoopedCable() {
        #expect(PortInventory.loopedBackPartners(Self.looped) == ["en5": "en6", "en6": "en5"])
        let ports = PortInventory.assemble(rows: Self.looped, archetype: .studioSix,
                                           enrichment: [:])
        #expect(ports.map(\.loopedBackTo) == [nil, nil, nil, "en6", "en5", nil])
    }

    @Test("Docks, empty receptacles and a Mac that says nothing are never paired")
    func silentWhenUnknown() {
        // No identity at all: the key is private and may not exist.
        let mute: [PortInventory.PortRow] = [
            .init(receptacle: 1, bsdName: "en2", linkStatus: 1),
            .init(receptacle: 2, bsdName: "en3", linkStatus: 3),
        ]
        #expect(PortInventory.loopedBackPartners(mute).isEmpty)
        // A dock: own domain, no link.
        #expect(PortInventory.loopedBackPartners([Self.rig[0], Self.rig[1]]).isEmpty)
        // A peer that is nobody's own domain: another Mac.
        #expect(PortInventory.loopedBackPartners([Self.rig[4], Self.rig[5]]).isEmpty)
    }

    @Test("The match has to be mutual")
    func requiresMutualClaim() {
        var oneSided = Self.looped
        oneSided[4].peerDomainUUIDs = []
        #expect(PortInventory.loopedBackPartners(oneSided).isEmpty)
        // A port that names itself is not a loop either.
        var selfClaim = Self.rig
        selfClaim[3].peerDomainUUIDs = [Self.acio3]
        #expect(PortInventory.loopedBackPartners(selfClaim).isEmpty)
    }

    @Test("Two receptacles on one controller set nothing rather than guess")
    func refusesSharedDomains() {
        // en4 and en5 claim the same own domain; en6 links to it. Which
        // receptacle the cable is in cannot be known, so nothing is said.
        var shared = Self.looped
        shared[2].domainUUID = Self.acio3
        shared[2].peerDomainUUIDs = [Self.acio4]
        #expect(PortInventory.loopedBackPartners(shared).isEmpty)
        // A dock on en6 with two cables back into this Mac: en6's controller
        // sees two peers, and both name it back. en6 has two candidate
        // partners, so it pairs with neither — and without en6 naming one of
        // them uniquely, neither of them pairs with en6. Nothing is guessed.
        var twoPeers = Self.looped
        twoPeers[4].peerDomainUUIDs = [Self.acio3, Self.acio2]
        twoPeers[2].peerDomainUUIDs = [Self.acio4]
        #expect(PortInventory.loopedBackPartners(twoPeers).isEmpty)
    }
}
