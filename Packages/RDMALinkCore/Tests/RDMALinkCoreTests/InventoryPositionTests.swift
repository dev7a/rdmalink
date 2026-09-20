import Testing
@testable import RDMALinkCore

@Suite("Port positions")
struct InventoryPositionTests {

    @Test("The six port-location values Mac15,14 publishes")
    func parsesRecordedStudioLocations() {
        #expect(PortPosition.parse("back-left") == PortPosition(face: .back, slot: .left))
        #expect(PortPosition.parse("back-left-middle") == PortPosition(face: .back, slot: .leftMiddle))
        #expect(PortPosition.parse("back-right-middle") == PortPosition(face: .back, slot: .rightMiddle))
        #expect(PortPosition.parse("back-right") == PortPosition(face: .back, slot: .right))
        #expect(PortPosition.parse("front-left") == PortPosition(face: .front, slot: .left))
        #expect(PortPosition.parse("front-right") == PortPosition(face: .front, slot: .right))
    }

    @Test("Side faces and single-receptacle faces")
    func parsesSideLocations() {
        #expect(PortPosition.parse("left-rear") == PortPosition(face: .left, slot: .rear))
        #expect(PortPosition.parse("left-front") == PortPosition(face: .left, slot: .front))
        #expect(PortPosition.parse("right") == PortPosition(face: .right, slot: .unspecified))
        #expect(PortPosition.parse("BACK-MIDDLE") == PortPosition(face: .back, slot: .middle))
    }

    @Test("An unfamiliar spelling is nil, never a guess")
    func rejectsUnknownLocations() {
        #expect(PortPosition.parse("") == nil)
        #expect(PortPosition.parse("underneath") == nil)
        #expect(PortPosition.parse("back-diagonal") == nil)
        #expect(PortPosition.parse("back-left-right") == nil)
        #expect(PortPosition.parse("left-rear-most") == nil)
    }

    @Test("Mac Studio names, in the words of UX_SPEC 4.7")
    func namesStudioPositions() {
        let names = [
            PortPosition(face: .back, slot: .left),
            PortPosition(face: .back, slot: .leftMiddle),
            PortPosition(face: .back, slot: .rightMiddle),
            PortPosition(face: .back, slot: .right),
            PortPosition(face: .front, slot: .left),
            PortPosition(face: .front, slot: .right),
        ].map { $0.name(archetype: .studioSix) }
        #expect(names == [
            "Back, far left", "Back, middle left", "Back, middle right", "Back, far right",
            "Front, left", "Front, right",
        ])
        #expect(PortPosition(face: .back, slot: .left).name(archetype: .studioFour)
            == "Back, far left")
    }

    @Test("Mac mini and MacBook Pro names")
    func namesOtherArchetypes() {
        #expect(PortPosition(face: .back, slot: .left).name(archetype: .mini) == "Back, left")
        #expect(PortPosition(face: .back, slot: .middle).name(archetype: .mini) == "Back, middle")
        #expect(PortPosition(face: .back, slot: .right).name(archetype: .mini) == "Back, right")
        #expect(PortPosition(face: .left, slot: .rear).name(archetype: .notebook)
            == "Left side, rear")
        #expect(PortPosition(face: .left, slot: .front).name(archetype: .notebook)
            == "Left side, front")
        #expect(PortPosition(face: .right, slot: .unspecified).name(archetype: .notebook)
            == "Right side")
    }

    @Test("An unrecognized Mac is never given a physical name")
    func unknownArchetypeHasNoNames() {
        for face in PortFace.allCases {
            #expect(PortPosition(face: face, slot: .left).name(archetype: .unknown) == nil)
        }
        // Nor is a name borrowed from the wrong chassis.
        #expect(PortPosition(face: .back, slot: .leftMiddle).name(archetype: .mini) == nil)
        #expect(PortPosition(face: .back, slot: .left).name(archetype: .notebook) == nil)
        #expect(PortPosition(face: .left, slot: .rear).name(archetype: .studioSix) == nil)
    }

    @Test("The numbered fallback")
    func numberedFallback() {
        #expect(ThunderboltPort.numberedName(receptacle: 1) == "Thunderbolt port 1")
        #expect(ThunderboltPort.numberedName(receptacle: 6) == "Thunderbolt port 6")
    }
}
