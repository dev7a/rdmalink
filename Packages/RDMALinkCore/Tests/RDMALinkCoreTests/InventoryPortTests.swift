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

        port.apply(bridges: ["bridge0", "bridge4"], linkLocal: ["fe80::1c3d:5aff:fe22:9b04"])
        #expect(port.bridges == ["bridge0", "bridge4"])
        #expect(port.linkLocal == ["fe80::1c3d:5aff:fe22:9b04"])
        #expect(port.link == .macLinked)
        #expect(port.positionName == "Front, right")

        port.apply(bridges: [], linkLocal: [])
        #expect(port.bridges.isEmpty)
        #expect(port.linkLocal.isEmpty)
    }
}
