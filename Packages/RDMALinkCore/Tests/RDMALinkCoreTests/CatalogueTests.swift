import Testing
@testable import RDMALinkCore

/// The chassis catalogue: the geometry the stage draws and the names the port
/// list prints, checked against the prototype's `MODELS` table and the
/// UX_SPEC §4.7 position-name table.
@Suite("The receptacle catalogue")
struct CatalogueTests {

    // MARK: What is on each chassis

    @Test("Every archetype carries the receptacles UX_SPEC §4.7 names, in order",
          arguments: [
            (Archetype.studioFour, ["Back, far left", "Back, middle left", "Back, middle right",
                                    "Back, far right", "Front, left", "Front, right"]),
            (.studioSix, ["Back, far left", "Back, middle left", "Back, middle right",
                          "Back, far right", "Front, left", "Front, right"]),
            (.mini, ["Back, left", "Back, middle", "Back, right", "Front, left", "Front, right"]),
            (.notebook, ["Left side, rear", "Left side, front", "Right side"]),
          ])
    func namesReceptaclesInPhysicalOrder(archetype: Archetype, names: [String]) {
        let chassis = ReceptacleCatalogue.chassis(for: archetype)
        #expect(chassis.receptacles.compactMap(\.positionName) == names)
    }

    @Test("Which receptacles are Thunderbolt and which are USB only",
          arguments: [
            (Archetype.studioFour, 4, 2),
            (.studioSix, 6, 0),
            (.mini, 3, 2),
            (.notebook, 3, 0),
          ])
    func countsReceptaclesByKind(archetype: Archetype, thunderbolt: Int, usb: Int) {
        let receptacles = ReceptacleCatalogue.chassis(for: archetype).receptacles
        #expect(receptacles.count { $0.kind == .thunderbolt } == thunderbolt)
        #expect(receptacles.count { $0.kind == .usbC } == usb)
        #expect(receptacles.count == thunderbolt + usb)
    }

    @Test("Every feature on every chassis, counted",
          arguments: [(Archetype.studioFour, 15), (.studioSix, 15), (.mini, 10), (.notebook, 7)])
    func countsEveryFeature(archetype: Archetype, features: Int) {
        #expect(ReceptacleCatalogue.chassis(for: archetype).features.count == features)
    }

    @Test("The two Mac Studios are one box that differs only at the front")
    func studiosShareOneBox() {
        let four = ReceptacleCatalogue.studioFour
        let six = ReceptacleCatalogue.studioSix
        #expect(four.width == six.width)
        #expect(four.height == six.height)
        #expect(four.depth == six.depth)
        #expect(four.features(on: .back).map(\.kind) == six.features(on: .back).map(\.kind))
        #expect(four.features(on: .front).map(\.kind)
            == [.usbC, .usbC, .sdCard, .indicator])
        #expect(six.features(on: .front).map(\.kind)
            == [.thunderbolt, .thunderbolt, .sdCard, .indicator])
    }

    // MARK: The invariants every chassis holds

    @Test("No two features share a place on a face", arguments: Archetype.allCases)
    func placesEveryFeatureOnceOnItsFace(archetype: Archetype) {
        let chassis = ReceptacleCatalogue.chassis(for: archetype, reportedThunderboltPorts: 6)
        for face in chassis.faces {
            let coordinates = chassis.features(on: face).map(\.u)
            #expect(Set(coordinates).count == coordinates.count)
            #expect(coordinates == coordinates.sorted())
            #expect(coordinates.allSatisfy { $0 > 0 && $0 < 1 })
            #expect(chassis.features(on: face).allSatisfy { $0.v > 0 && $0.v < 1 })
        }
    }

    @Test("Every Thunderbolt and USB receptacle is named and numbered, and nothing else is",
          arguments: Archetype.allCases)
    func namesAndNumbersReceptaclesOnly(archetype: Archetype) {
        let chassis = ReceptacleCatalogue.chassis(for: archetype, reportedThunderboltPorts: 6)
        for feature in chassis.features {
            if feature.kind.isReceptacle {
                #expect(feature.positionName?.isEmpty == false)
                #expect(feature.index != nil)
            } else {
                #expect(feature.positionName == nil)
                #expect(feature.index == nil)
            }
        }
        // A name is a row in the port list, so two of them would be two rows
        // for one hole.
        let names = chassis.receptacles.compactMap(\.positionName)
        #expect(Set(names).count == names.count)
        #expect(Set(chassis.features.map(\.id)).count == chassis.features.count)
    }

    @Test("The index is the rank along the face, and finds the receptacle again",
          arguments: Archetype.allCases)
    func looksUpByFaceAndIndex(archetype: Archetype) {
        let chassis = ReceptacleCatalogue.chassis(for: archetype, reportedThunderboltPorts: 6)
        for face in chassis.faces {
            let onFace = chassis.features(on: face).filter(\.kind.isReceptacle)
            #expect(onFace.map(\.index) == (0..<onFace.count).map { $0 })
            for receptacle in onFace {
                #expect(chassis.receptacle(face: face, index: receptacle.index ?? -1) == receptacle)
            }
            #expect(chassis.receptacle(face: face, index: onFace.count) == nil)
        }
    }

    @Test("Faces come out back before front, left before right")
    func ordersFaces() {
        #expect(ReceptacleCatalogue.studioSix.faces == [.back, .front])
        #expect(ReceptacleCatalogue.mini.faces == [.back, .front])
        #expect(ReceptacleCatalogue.notebook.faces == [.left, .right])
    }

    // MARK: The box itself

    @Test("The Mac Studio's box, in centimetres")
    func transcribesTheStudioBox() {
        let chassis = ReceptacleCatalogue.studioSix
        #expect(chassis.width == 19.7)
        #expect(chassis.height == 9.5)
        #expect(chassis.depth == 19.7)
        #expect(chassis.cornerRadius == 2.4)
        #expect(chassis.bevel == 0.22)
        #expect(chassis.baseBand == 1.0)
        #expect(chassis.lid == nil)
    }

    @Test("The Mac mini's box, in centimetres")
    func transcribesTheMiniBox() {
        let chassis = ReceptacleCatalogue.mini
        #expect(chassis.width == 12.7)
        #expect(chassis.height == 5.0)
        #expect(chassis.depth == 12.7)
        #expect(chassis.cornerRadius == 1.4)
        #expect(chassis.bevel == 0.16)
        #expect(chassis.baseBand == 0.7)
    }

    @Test("The notebook is the one chassis with a lid")
    func transcribesTheNotebook() {
        let chassis = ReceptacleCatalogue.notebook
        #expect(chassis.width == 31.26)
        #expect(chassis.height == 1.55)
        #expect(chassis.depth == 22.12)
        #expect(chassis.cornerRadius == 1.0)
        #expect(chassis.bevel == 0.22)
        #expect(chassis.baseBand == 0)
        #expect(chassis.lid == Lid(depth: 22.0, thickness: 0.42, openAngle: 104))
    }

    // MARK: Openings

    @Test("Only the desktops turn their receptacles a quarter turn")
    func turnsReceptaclesOnVerticalChassis() {
        for chassis in [ReceptacleCatalogue.studioSix, ReceptacleCatalogue.mini] {
            #expect(chassis.features.allSatisfy { $0.isVertical == $0.kind.isReceptacle })
        }
        #expect(ReceptacleCatalogue.notebook.features.allSatisfy { !$0.isVertical })
    }

    @Test("A turned opening is the same hole on its side")
    func rotatesTheOpening() throws {
        let studio = try #require(ReceptacleCatalogue.studioSix.receptacle(face: .back, index: 0))
        #expect(studio.opening == FeatureKind.Opening(width: 0.35, height: 0.95, cornerRadius: 0.17))
        let notebook = try #require(ReceptacleCatalogue.notebook.receptacle(face: .left, index: 0))
        #expect(notebook.opening == FeatureKind.thunderbolt.opening)
        // Everything that is not a receptacle keeps its own orientation.
        let ethernet = try #require(ReceptacleCatalogue.mini.features(on: .back)
            .first { $0.kind == .ethernet })
        #expect(ethernet.opening == FeatureKind.ethernet.opening)
    }

    /// The prototype gives USB-C a much smaller corner radius than Thunderbolt
    /// on the same-sized hole: a Thunderbolt receptacle's 0.17 on a 0.35-tall
    /// opening is a half-round end cap, and USB-C's 0.08 is a squarer mouth.
    /// That is the "correct, slightly different geometry" UX_SPEC §4.5 asks
    /// for, and it is the whole difference between the two openings.
    @Test("USB-only receptacles are the squarer hole")
    func usbIsSquarerThanThunderbolt() {
        #expect(FeatureKind.usbC.opening.cornerRadius < FeatureKind.thunderbolt.opening.cornerRadius)
        #expect(FeatureKind.usbC.opening.width == FeatureKind.thunderbolt.opening.width)
        #expect(FeatureKind.usbC.opening.height == FeatureKind.thunderbolt.opening.height)
    }

    /// A radius does not rotate. Turning a receptacle a quarter turn swaps the
    /// two extents and leaves the corner alone, so the hole keeps its shape.
    @Test("Turning an opening leaves its corner radius alone")
    func rotationKeepsTheCornerRadius() {
        let flat = FeatureKind.thunderbolt.opening
        #expect(flat.rotated.cornerRadius == flat.cornerRadius)
        #expect(flat.rotated.rotated == flat)
    }

    @Test("Only Thunderbolt and USB-C are receptacles")
    func knowsWhichKindsAreReceptacles() {
        #expect(FeatureKind.allCases.filter(\.isReceptacle) == [.thunderbolt, .usbC])
    }

    // MARK: The stand-in

    @Test("An unrecognized Mac gets a plain box with numbered receptacles",
          arguments: [1, 2, 3, 6, 8])
    func buildsTheStandIn(count: Int) {
        let chassis = ReceptacleCatalogue.generic(receptacleCount: count)
        #expect(chassis.archetype == .unknown)
        #expect(chassis.lid == nil)
        #expect(chassis.faces == [.back])
        #expect(chassis.receptacles.count == count)
        #expect(chassis.receptacles.allSatisfy { $0.kind == .thunderbolt })
        #expect(chassis.receptacles.compactMap(\.positionName)
            == (1...count).map { "Thunderbolt port \($0)" })
        // Centred, in order, and on the face.
        let coordinates = chassis.receptacles.map(\.u)
        #expect(coordinates == coordinates.sorted())
        #expect(coordinates.allSatisfy { $0 > 0 && $0 < 1 })
        #expect(abs((coordinates.reduce(0, +) / Double(count)) - 0.5) < 1e-9)
    }

    @Test("A stand-in for a Mac with nothing on it is a box with nothing on it")
    func buildsAnEmptyStandIn() {
        #expect(ReceptacleCatalogue.generic(receptacleCount: 0).features.isEmpty)
        #expect(ReceptacleCatalogue.generic(receptacleCount: -3).features.isEmpty)
        #expect(ReceptacleCatalogue.generic(receptacleCount: 0).faces.isEmpty)
    }

    @Test("The unknown archetype is the stand-in, and the others ignore the count")
    func dispatchesOnArchetype() {
        #expect(ReceptacleCatalogue.chassis(for: .unknown, reportedThunderboltPorts: 3)
            == ReceptacleCatalogue.generic(receptacleCount: 3))
        #expect(ReceptacleCatalogue.chassis(for: .studioSix, reportedThunderboltPorts: 3)
            == ReceptacleCatalogue.studioSix)
        #expect(ReceptacleCatalogue.chassis(for: .mini) == ReceptacleCatalogue.mini)
        #expect(ReceptacleCatalogue.chassis(for: .notebook) == ReceptacleCatalogue.notebook)
        #expect(ReceptacleCatalogue.chassis(for: .studioFour) == ReceptacleCatalogue.studioFour)
    }

    @Test("Every chassis knows where the camera rests")
    func transcribesTheRestingPose() {
        #expect(ReceptacleCatalogue.studioSix.resting
            == RestingPose(yaw: .pi - 0.55, pitch: 0.30, radiusScale: 1.0))
        #expect(ReceptacleCatalogue.studioFour.resting == ReceptacleCatalogue.studioSix.resting)
        #expect(ReceptacleCatalogue.mini.resting
            == RestingPose(yaw: .pi - 0.55, pitch: 0.34, radiusScale: 1.0))
        #expect(ReceptacleCatalogue.notebook.resting
            == RestingPose(yaw: -.pi / 2 + 0.75, pitch: 0.32, radiusScale: 1.05))
    }

    @Test("The stand-in box grows with the row rather than crowding it")
    func growsTheStandIn() {
        #expect(ReceptacleCatalogue.generic(receptacleCount: 0).width == 16.0)
        #expect(ReceptacleCatalogue.generic(receptacleCount: 2).width == 16.0)
        #expect(ReceptacleCatalogue.generic(receptacleCount: 8).width == 23.6)
        let wide = ReceptacleCatalogue.generic(receptacleCount: 8)
        let pitches = zip(wide.receptacles.dropFirst(), wide.receptacles)
            .map { ($0.u - $1.u) * wide.width }
        #expect(pitches.allSatisfy { abs($0 - 1.6) < 1e-9 })
    }

    // MARK: The names the rest of the app uses

    @Test("Every name in the catalogue is one PortPosition would produce")
    func agreesWithThePositionTable() {
        // The two halves of UX_SPEC §4.7 have to meet: the hardware read names
        // a receptacle from `port-location`, the catalogue names the same one
        // from this table, and the port list joins them on that string.
        for archetype in [Archetype.studioFour, .studioSix, .mini, .notebook] {
            let fromPositions = Set(
                PortFace.allCases.flatMap { face in
                    [PortSlot.left, .leftMiddle, .middle, .rightMiddle, .right,
                     .rear, .front, .unspecified].compactMap {
                        PortPosition(face: face, slot: $0).name(archetype: archetype)
                    }
                }
            )
            let fromCatalogue = Set(
                ReceptacleCatalogue.chassis(for: archetype).receptacles.compactMap(\.positionName)
            )
            #expect(fromCatalogue.isSubset(of: fromPositions))
        }
    }
}
