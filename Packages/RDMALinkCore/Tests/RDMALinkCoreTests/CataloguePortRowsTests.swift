import Testing
@testable import RDMALinkCore

/// The port list the hub draws: what macOS reported, interleaved with the
/// USB-only receptacles only the catalogue knows about (UX_SPEC §S1, §4.5).
@Suite("The catalogue's port rows")
struct CataloguePortRowsTests {

    /// A port as the hardware read would hand it over: named from
    /// `port-location`, in physical order.
    private static func port(
        _ receptacle: Int, _ bsdName: String, _ name: String, face: PortFace?,
        link: LinkState = .empty
    ) -> ThunderboltPort {
        ThunderboltPort(
            id: bsdName, receptacle: receptacle, bsdName: bsdName,
            face: face, positionName: name, link: link
        )
    }

    /// Mac15,14: six Thunderbolt receptacles, four back and two front.
    private static let studioSixPorts: [ThunderboltPort] = [
        port(4, "en5", "Back, far left", face: .back),
        port(3, "en4", "Back, middle left", face: .back, link: .macLinked),
        port(2, "en3", "Back, middle right", face: .back, link: .device),
        port(1, "en2", "Back, far right", face: .back),
        port(6, "en7", "Front, left", face: .front),
        port(5, "en6", "Front, right", face: .front),
    ]

    /// A Mac Studio whose front two receptacles carry USB only, so macOS
    /// reports four Thunderbolt-IP ports and no more.
    private static let studioFourPorts: [ThunderboltPort] = Array(studioSixPorts.prefix(4))

    private static let miniPorts: [ThunderboltPort] = [
        port(1, "en2", "Back, left", face: .back, link: .macLinked),
        port(2, "en3", "Back, middle", face: .back),
        port(3, "en4", "Back, right", face: .back),
    ]

    // MARK: Nothing invented where nothing is missing

    @Test("A Mac whose front ports are Thunderbolt gets no USB rows")
    func leavesStudioSixAlone() {
        let rows = ReceptacleCatalogue.portRows(
            realPorts: Self.studioSixPorts, archetype: .studioSix)
        #expect(rows == Self.studioSixPorts)
        #expect(rows.allSatisfy { $0.isThunderbolt })
    }

    @Test("An unrecognized Mac gets exactly what macOS reported")
    func leavesUnknownAlone() {
        let numbered = [
            Self.port(1, "en2", "Thunderbolt port 1", face: .back),
            Self.port(2, "en3", "Thunderbolt port 2", face: .back),
        ]
        #expect(ReceptacleCatalogue.portRows(realPorts: numbered, archetype: .unknown) == numbered)
        #expect(ReceptacleCatalogue.portRows(realPorts: [], archetype: .unknown).isEmpty)
    }

    // MARK: The USB-only rows

    @Test("A four-port Mac Studio's front receptacles come from the catalogue")
    func addsTheStudioFourFrontRow() throws {
        let rows = ReceptacleCatalogue.portRows(
            realPorts: Self.studioFourPorts, archetype: .studioFour)
        #expect(rows.map(\.positionName) == [
            "Back, far left", "Back, middle left", "Back, middle right", "Back, far right",
            "Front, left", "Front, right",
        ])
        #expect(rows.map(\.isThunderbolt) == [true, true, true, true, false, false])
        let front = rows.suffix(2)
        #expect(front.allSatisfy { $0.bsdName.isEmpty })
        #expect(front.allSatisfy { $0.face == .front })
        #expect(front.allSatisfy { $0.link == .empty })
        #expect(front.allSatisfy { $0.bridges.isEmpty && $0.linkLocal.isEmpty })
        #expect(front.map(\.receptacle) == [0, 1])
        #expect(front.map(\.id) == ["usb.front.0", "usb.front.1"])
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test("A Mac mini's two front receptacles are USB only too")
    func addsTheMiniFrontRow() {
        let rows = ReceptacleCatalogue.portRows(realPorts: Self.miniPorts, archetype: .mini)
        #expect(rows.map(\.positionName) == [
            "Back, left", "Back, middle", "Back, right", "Front, left", "Front, right",
        ])
        #expect(rows.map(\.isThunderbolt) == [true, true, true, false, false])
        #expect(rows.map(\.link) == [.macLinked, .empty, .empty, .empty, .empty])
    }

    @Test("A notebook has no USB-only receptacles to add")
    func leavesTheNotebookAlone() {
        let ports = [
            Self.port(1, "en1", "Left side, rear", face: .left),
            Self.port(2, "en2", "Left side, front", face: .left),
            Self.port(3, "en3", "Right side", face: .right),
        ]
        #expect(ReceptacleCatalogue.portRows(realPorts: ports, archetype: .notebook) == ports)
    }

    // MARK: What the app has observed wins

    @Test("A receptacle macOS really reported is never replaced by a catalogue row")
    func prefersTheObservedPort() {
        // If a Mac Studio this app thinks has USB-only front ports reports a
        // Thunderbolt-IP port there, the hardware is right and the table is
        // wrong, and the row is the real port.
        let real = Self.studioFourPorts + [
            Self.port(6, "en7", "Front, left", face: .front, link: .macLinked),
        ]
        let rows = ReceptacleCatalogue.portRows(realPorts: real, archetype: .studioFour)
        #expect(rows.count == 6)
        #expect(rows[4].bsdName == "en7")
        #expect(rows[4].isThunderbolt)
        #expect(rows[5].positionName == "Front, right")
        #expect(!rows[5].isThunderbolt)
    }

    @Test("A Thunderbolt receptacle macOS did not report is simply not in the list")
    func inventsNoThunderboltPort() {
        let rows = ReceptacleCatalogue.portRows(
            realPorts: Array(Self.studioSixPorts.dropFirst()), archetype: .studioSix)
        #expect(rows.count == 5)
        #expect(!rows.map(\.positionName).contains("Back, far left"))
    }

    @Test("A port the catalogue has no name for keeps its place at the end")
    func keepsUnmatchedPortsInOrder() {
        // A Mac that published a position for some receptacles and not others:
        // the numbered ones follow the named ones, in the order they arrived.
        let real = Array(Self.studioSixPorts.prefix(2)) + [
            Self.port(9, "en9", "Thunderbolt port 9", face: nil),
            Self.port(8, "en8", "Thunderbolt port 8", face: nil),
        ]
        let rows = ReceptacleCatalogue.portRows(realPorts: real, archetype: .studioFour)
        #expect(rows.map(\.bsdName) == ["en5", "en4", "", "", "en9", "en8"])
        #expect(Array(rows.suffix(2)).map(\.positionName)
            == ["Thunderbolt port 9", "Thunderbolt port 8"])
        // The two empty ones are the front USB receptacles, in their place in
        // the middle of the list; the numbered ports follow them.
        #expect(rows.map(\.isThunderbolt) == [true, true, false, false, true, true])

        // The same two numbered ports on a Mac whose front receptacles are
        // Thunderbolt: nothing is invented, and they still come last.
        let six = ReceptacleCatalogue.portRows(realPorts: real, archetype: .studioSix)
        #expect(six.map(\.bsdName) == ["en5", "en4", "en9", "en8"])
    }

    @Test("Nothing macOS reported is ever dropped", arguments: Archetype.allCases)
    func keepsEveryRealPort(archetype: Archetype) {
        let rows = ReceptacleCatalogue.portRows(
            realPorts: Self.studioSixPorts, archetype: archetype)
        let real = rows.filter { !$0.bsdName.isEmpty }
        #expect(Set(real.map(\.bsdName)) == Set(Self.studioSixPorts.map(\.bsdName)))
    }

    @Test("A Mac that placed none of its ports gets no catalogue rows either")
    func inventsNothingWithoutAPlacedPort() {
        // The archetype is known from `hw.model`, but this Mac published no
        // `port-location`, so every port is numbered. Where the front
        // receptacles are relative to these is anybody's guess, and the app
        // does not guess.
        let numbered = (1...3).map {
            Self.port($0, "en\($0 + 1)", "Thunderbolt port \($0)", face: nil)
        }
        #expect(ReceptacleCatalogue.portRows(realPorts: numbered, archetype: .mini) == numbered)
        #expect(ReceptacleCatalogue.portRows(realPorts: numbered, archetype: .studioFour)
            == numbered)
    }

    @Test("A Mac reporting no Thunderbolt ports at all is still reporting none")
    func staysEmptyForR24() {
        // R24 is "macOS reports no Thunderbolt-IP ports". Two USB rows would
        // make the hub think it had something to show.
        for archetype in Archetype.allCases {
            #expect(ReceptacleCatalogue.portRows(realPorts: [], archetype: archetype).isEmpty)
        }
    }

    @Test("A cable in a USB-only receptacle reaches its row")
    func carriesTheCableIntoTheUSBRow() {
        // UX_SPEC §4.5: "If a cable is physically in one, it is the only place
        // a plug stub appears on that face, and the hub shows a tip row
        // unprompted." Nothing else in the read can see that cable: these
        // receptacles have no Thunderbolt-IP port and so no receptacle index
        // to join on, which is why `ChassisProbe` keeps their position nodes.
        let cabled: Set<PortPosition> = [PortPosition(face: .front, slot: .right)]
        for (archetype, ports) in [
            (Archetype.studioFour, Self.studioFourPorts), (.mini, Self.miniPorts),
        ] {
            let rows = ReceptacleCatalogue.portRows(
                realPorts: ports, archetype: archetype, cabledPositions: cabled
            )
            let usb = rows.filter { !$0.isThunderbolt }
            #expect(usb.count == 2)
            #expect(usb.first { $0.positionName == "Front, right" }?.link == .device)
            #expect(usb.first { $0.positionName == "Front, left" }?.link == .empty)
        }
    }

    @Test("With nothing plugged in, a USB-only row says nothing is plugged in")
    func leavesTheUSBRowEmptyWithoutAProbe() {
        let rows = ReceptacleCatalogue.portRows(
            realPorts: Self.studioFourPorts, archetype: .studioFour
        )
        #expect(rows.filter { !$0.isThunderbolt }.allSatisfy { $0.link == .empty })
    }

    // MARK: What the rest of the app makes of them

    @Test("A USB-only row is not a Thunderbolt port to anything downstream")
    func keepsUSBRowsOutOfTheThunderboltPaths() {
        let rows = ReceptacleCatalogue.portRows(realPorts: Self.miniPorts, archetype: .mini)
        let inventory = Inventory(
            model: HardwareModel(identifier: "Mac16,11", marketingName: "Mac mini",
                                 chip: "M4 Pro", archetype: .mini),
            ports: rows,
            rdma: .off
        )
        #expect(inventory.thunderboltBSDNames == ["en2", "en3", "en4"])
        // One Mac on one cable is not R1, whatever the USB rows do.
        #expect(Refusals.oneCableOnly(inventory.observedPorts) == nil)
    }
}
