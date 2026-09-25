import Testing
@testable import RDMALinkCore

@Suite("Hardware model")
struct InventoryHardwareTests {

    @Test("The catalogue names the Macs the spec draws")
    func catalogueNamesKnownMacs() {
        #expect(HardwareModel.catalog["Mac15,14"]
            == HardwareModel.KnownMac(marketingName: "Mac Studio", archetype: .studioSix))
        #expect(HardwareModel.catalog["Mac16,9"]
            == HardwareModel.KnownMac(marketingName: "Mac Studio", archetype: .studioFour))
        #expect(HardwareModel.catalog["Mac16,11"]
            == HardwareModel.KnownMac(marketingName: "Mac mini", archetype: .mini))
        #expect(HardwareModel.catalog["Mac16,6"]
            == HardwareModel.KnownMac(marketingName: "MacBook Pro", archetype: .notebook))
        #expect(HardwareModel.catalog["Mac17,7"]
            == HardwareModel.KnownMac(marketingName: "MacBook Pro", archetype: .notebook))
        // Apple's "Identify your MacBook Pro model" page, read 2026-09-20.
        for identifier in ["Mac17,2", "Mac17,6", "Mac17,8", "Mac17,9"] {
            #expect(HardwareModel.catalog[identifier]?.archetype == .notebook, "\(identifier)")
        }
        // Not on that page: it was never a MacBook Pro identifier.
        #expect(HardwareModel.catalog["Mac17,1"] == nil)
        // Apple's Mac Studio and Mac mini Identify pages and the two specs
        // pages, read 2026-09-25: the M5 Max has USB-C in front, the M5 Ultra
        // Thunderbolt 5, and both 2026 minis share the one mini chassis.
        #expect(HardwareModel.catalog["Mac17,14"]
            == HardwareModel.KnownMac(marketingName: "Mac Studio", archetype: .studioFour))
        #expect(HardwareModel.catalog["Mac17,15"]
            == HardwareModel.KnownMac(marketingName: "Mac Studio", archetype: .studioSix))
        #expect(HardwareModel.catalog["Mac17,16"]
            == HardwareModel.KnownMac(marketingName: "Mac mini", archetype: .mini))
        #expect(HardwareModel.catalog["Mac18,5"]
            == HardwareModel.KnownMac(marketingName: "Mac mini", archetype: .mini))
    }

    @Test("The catalogue's archetype is readable by identifier, and only by one it lists")
    func archetypeByIdentifier() {
        #expect(HardwareModel.archetype(forIdentifier: "Mac17,14") == .studioFour)
        #expect(HardwareModel.archetype(forIdentifier: "Mac17,16") == .mini)
        #expect(HardwareModel.archetype(forIdentifier: "Mac17,7") == .notebook)
        #expect(HardwareModel.archetype(forIdentifier: "Mac99,99") == nil)
        #expect(HardwareModel.archetype(forIdentifier: "") == nil)
    }

    @Test("The rig's MacBook Pro spellings parse to the notebook's three names")
    func macBookProSpellingsParse() {
        // Verified on Mac17,7 (2026-09-20): `right`, `left-back`, `left-front`.
        let names = ["left-back", "left-front", "right"].map {
            PortPosition.parse($0)?.name(archetype: .notebook)
        }
        #expect(names == ["Left side, rear", "Left side, front", "Right side"])
        #expect(HardwareModel.productFamily(fromProductName: "MacBook Pro (14-inch, M5 Max)") == "MacBook Pro")
    }

    @Test("An identifier nobody has checked is unknown, not guessed")
    func unknownIdentifierStaysUnknown() {
        #expect(HardwareModel.catalog["Mac99,99"] == nil)
        // A Mac Studio identifier that does not exist yet must not be inferred
        // from the ones that do.
        #expect(HardwareModel.catalog["Mac16,10"]?.archetype == .mini)
        #expect(HardwareModel.catalog["Mac15,13"] == nil)
    }

    @Test("The chip name drops Apple's prefix and nothing else")
    func chipNameStripsPrefix() {
        #expect(HardwareModel.chipName(fromBrandString: "Apple M3 Ultra") == "M3 Ultra")
        #expect(HardwareModel.chipName(fromBrandString: "Apple M4 Pro") == "M4 Pro")
        #expect(HardwareModel.chipName(fromBrandString: " Apple M5 \n") == "M5")
        #expect(HardwareModel.chipName(fromBrandString: "M5 Ultra") == "M5 Ultra")
        #expect(HardwareModel.chipName(fromBrandString: "") == "")
    }

    @Test("An unrecognized Mac is named plainly, has no chassis, and is refused (R31)")
    func unrecognizedModelIsReadOnly() {
        let model = HardwareModel(
            identifier: "Mac99,99", marketingName: "Mac", chip: "M9", archetype: .unknown
        )
        #expect(!model.isRecognized)
        #expect(model.marketingName == "Mac")
        #expect(model.recognition == .none)
        #expect(ReceptacleCatalogue.chassis(for: model.archetype) == nil)
        #expect(Refusals.macRecognized(model)?.code == .macNotRecognized)
    }

    @Test("A fixture built without saying how it was recognized means by identifier")
    func recognitionDefaultsFromTheArchetype() {
        let studio = HardwareModel(
            identifier: "Mac15,14", marketingName: "Mac Studio", chip: "M3 Ultra", archetype: .studioSix
        )
        #expect(studio.recognition == .identifier)
        #expect(studio.isRecognized)
        let explicit = HardwareModel(
            identifier: "Mac99,99", marketingName: "Mac Studio", chip: "M9", archetype: .studioSix,
            recognition: .familyAndLayout
        )
        #expect(explicit.recognition == .familyAndLayout)
        #expect(explicit.isRecognized)
    }

    // MARK: The product family

    @Test("The product family is the device tree's name without its parenthesis",
          arguments: [
            ("Mac Studio (2025)", "Mac Studio"),
            ("MacBook Pro (16-inch, 2026)", "MacBook Pro"),
            ("Mac mini (2024)", "Mac mini"),
            ("  MacBook Pro  ", "MacBook Pro"),
            ("Mac Studio", "Mac Studio"),
          ])
    func parsesTheProductFamily(name: String, family: String) {
        #expect(HardwareModel.productFamily(fromProductName: name) == family)
    }

    @Test("No product name, or nothing before the parenthesis, is no family",
          arguments: ["", "(2025)", "   ", " (16-inch, 2026)"])
    func refusesAnEmptyFamily(name: String) {
        #expect(HardwareModel.productFamily(fromProductName: name) == nil)
    }

    @Test("An absent product node is no family")
    func refusesAnAbsentProductName() {
        #expect(HardwareModel.productFamily(fromProductName: nil) == nil)
    }

    // MARK: Recognition by family and layout

    /// The Mac Studio's six `port-location` values, as Mac15,14 publishes them.
    static let studioSixPositions: [PortPosition?] = [
        PortPosition(face: .back, slot: .left),
        PortPosition(face: .back, slot: .leftMiddle),
        PortPosition(face: .back, slot: .rightMiddle),
        PortPosition(face: .back, slot: .right),
        PortPosition(face: .front, slot: .left),
        PortPosition(face: .front, slot: .right),
    ]

    static let studioBackFour = Array(studioSixPositions.prefix(4))

    /// A MacBook Pro's three, as `PortPosition.parse` would read
    /// `left-rear`, `left-front` and `right`.
    static let notebookPositions: [PortPosition?] = [
        PortPosition(face: .left, slot: .rear),
        PortPosition(face: .left, slot: .front),
        PortPosition(face: .right, slot: .unspecified),
    ]

    static func unlisted(_ family: String) -> HardwareModel {
        HardwareModel(identifier: "Mac99,99", marketingName: family, chip: "M9 Max", archetype: .unknown)
    }

    @Test("A Mac Studio with the six known positions is the six-port Studio")
    func recognizesStudioSixByLayout() {
        let model = Self.unlisted("Mac Studio").recognizing(thunderboltPositions: Self.studioSixPositions)
        #expect(model.archetype == .studioSix)
        #expect(model.recognition == .familyAndLayout)
        #expect(model.isRecognized)
        // Nothing else about the model moves.
        #expect(model.identifier == "Mac99,99")
        #expect(model.marketingName == "Mac Studio")
        #expect(model.chip == "M9 Max")
    }

    @Test("A Mac Studio with only the back four is the four-port Studio")
    func recognizesStudioFourByLayout() {
        let model = Self.unlisted("Mac Studio").recognizing(thunderboltPositions: Self.studioBackFour)
        #expect(model.archetype == .studioFour)
        #expect(model.recognition == .familyAndLayout)
    }

    @Test("A Mac Studio with five back positions matches neither Studio")
    func refusesAFifthBackPosition() {
        let five = Self.studioBackFour + [PortPosition(face: .back, slot: .middle)]
        let model = Self.unlisted("Mac Studio").recognizing(thunderboltPositions: five)
        #expect(model.archetype == .unknown)
        #expect(model.recognition == .none)
    }

    @Test("One position the Mac did not publish is enough to refuse")
    func refusesAMissingPosition() {
        var positions = Self.studioSixPositions
        positions[2] = nil
        let model = Self.unlisted("Mac Studio").recognizing(thunderboltPositions: positions)
        #expect(model.archetype == .unknown)
        #expect(model.recognition == .none)
        // Nor is the count alone evidence: six entries with a hole in them
        // are not the six-port Studio.
        #expect(positions.count == 6)
    }

    @Test("A family the table does not list stays unknown whatever its layout")
    func refusesAnUnlistedFamily() {
        let model = Self.unlisted("iMac").recognizing(thunderboltPositions: Self.studioBackFour)
        #expect(model.archetype == .unknown)
        #expect(model.recognition == .none)
        #expect(Self.unlisted("Mac").recognizing(thunderboltPositions: Self.studioSixPositions)
            .archetype == .unknown)
    }

    @Test("A MacBook Pro with two left and one right is the notebook")
    func recognizesTheNotebookByLayout() {
        let model = Self.unlisted("MacBook Pro").recognizing(thunderboltPositions: Self.notebookPositions)
        #expect(model.archetype == .notebook)
        #expect(model.recognition == .familyAndLayout)
    }

    @Test("A MacBook Pro with two right ports is not the notebook")
    func refusesTwoRightPorts() {
        let positions: [PortPosition?] = Self.notebookPositions
            + [PortPosition(face: .right, slot: .unspecified)]
        let model = Self.unlisted("MacBook Pro").recognizing(thunderboltPositions: positions)
        #expect(model.archetype == .unknown)
        #expect(model.recognition == .none)
    }

    @Test("Two positions that share one name are two rows for one hole, and refused")
    func refusesTwoPositionsWithOneName() {
        // `right-front` and `right-rear` both name "Right side" on the
        // notebook: a Mac reporting both cannot be the chassis with one.
        let positions: [PortPosition?] = [
            PortPosition(face: .left, slot: .rear),
            PortPosition(face: .left, slot: .front),
            PortPosition(face: .right, slot: .front),
            PortPosition(face: .right, slot: .rear),
        ]
        let model = Self.unlisted("MacBook Pro").recognizing(thunderboltPositions: positions)
        #expect(model.archetype == .unknown)
        #expect(model.recognition == .none)
    }

    @Test("A Mac the catalogue lists is never re-decided by its layout")
    func keepsTheIdentifierDecision() {
        let studio = HardwareModel(
            identifier: "Mac15,14", marketingName: "Mac Studio", chip: "M3 Ultra", archetype: .studioSix
        )
        // The layout says four-port; the catalogue said six-port, and wins.
        let decided = studio.recognizing(thunderboltPositions: Self.studioBackFour)
        #expect(decided == studio)
        #expect(decided.recognition == .identifier)
        // Even against a layout that matches nothing at all.
        #expect(studio.recognizing(thunderboltPositions: [nil, nil]) == studio)
    }

    @Test("A receptacle the probe could not place is a hole in the layout, not a shorter one")
    func refusesAReceptacleTheProbeMissed() {
        // Six Thunderbolt receptacles as macOS lists them, of which the probe
        // joined only the back four to a position: the two front nodes are
        // absent from its map, not nil in it. Read from the map alone the
        // layout would be exactly studioFour's table.
        let rows = (1...6).map {
            PortInventory.PortRow(receptacle: $0, bsdName: "en\($0)", linkStatus: 0)
        }
        var enrichment = ChassisEnrichment()
        for (receptacle, position) in zip(1...4, Self.studioBackFour) {
            enrichment.byReceptacle[receptacle] = ReceptacleEnrichment(position: position)
        }
        let positions = Inventory.thunderboltPositions(rows: rows, enrichment: enrichment)
        #expect(positions.count == 6)
        #expect(positions.compactMap { $0 }.count == 4)
        #expect(positions[4] == nil && positions[5] == nil)

        let model = Self.unlisted("Mac Studio").recognizing(thunderboltPositions: positions)
        #expect(model.archetype == .unknown)
        #expect(model.recognition == .none)

        // With the two front nodes joined, the same six receptacles are the
        // six-port Studio — so it was the missing entries that refused.
        for (receptacle, position) in zip(5...6, Self.studioSixPositions.suffix(2)) {
            enrichment.byReceptacle[receptacle] = ReceptacleEnrichment(position: position)
        }
        let placed = Inventory.thunderboltPositions(rows: rows, enrichment: enrichment)
        #expect(Self.unlisted("Mac Studio").recognizing(thunderboltPositions: placed).archetype == .studioSix)
    }

    @Test("Recognition reads as payload text, not as an enum case")
    func describesRecognition() {
        #expect("\(Recognition.identifier)" == "by identifier")
        #expect("\(Recognition.familyAndLayout)" == "by product family and layout")
        #expect("\(Recognition.none)" == "not recognized")
    }
}
