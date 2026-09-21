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
    func namesReceptaclesInPhysicalOrder(archetype: Archetype, names: [String]) throws {
        let chassis = try #require(ReceptacleCatalogue.chassis(for: archetype))
        #expect(chassis.receptacles.compactMap(\.positionName) == names)
    }

    @Test("Which receptacles are Thunderbolt and which are USB only",
          arguments: [
            (Archetype.studioFour, 4, 2),
            (.studioSix, 6, 0),
            (.mini, 3, 2),
            (.notebook, 3, 0),
          ])
    func countsReceptaclesByKind(archetype: Archetype, thunderbolt: Int, usb: Int) throws {
        let receptacles = try #require(ReceptacleCatalogue.chassis(for: archetype)).receptacles
        #expect(receptacles.count { $0.kind == .thunderbolt } == thunderbolt)
        #expect(receptacles.count { $0.kind == .usbC } == usb)
        #expect(receptacles.count == thunderbolt + usb)
    }

    @Test("Every feature on every chassis, counted",
          arguments: [(Archetype.studioFour, 15), (.studioSix, 15), (.mini, 10), (.notebook, 7)])
    func countsEveryFeature(archetype: Archetype, features: Int) {
        #expect(ReceptacleCatalogue.chassis(for: archetype)?.features.count == features)
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

    @Test("No two features share a place on a face", arguments: drawn)
    func placesEveryFeatureOnceOnItsFace(archetype: Archetype) throws {
        let chassis = try #require(ReceptacleCatalogue.chassis(for: archetype))
        for face in chassis.faces {
            let coordinates = chassis.features(on: face).map(\.u)
            #expect(Set(coordinates).count == coordinates.count)
            #expect(coordinates == coordinates.sorted())
            #expect(coordinates.allSatisfy { $0 > 0 && $0 < 1 })
            #expect(chassis.features(on: face).allSatisfy { $0.v > 0 && $0.v < 1 })
        }
    }

    @Test("Every Thunderbolt and USB receptacle is named and numbered, and nothing else is",
          arguments: drawn)
    func namesAndNumbersReceptaclesOnly(archetype: Archetype) throws {
        let chassis = try #require(ReceptacleCatalogue.chassis(for: archetype))
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
          arguments: drawn)
    func looksUpByFaceAndIndex(archetype: Archetype) throws {
        let chassis = try #require(ReceptacleCatalogue.chassis(for: archetype))
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
        #expect(chassis.grille?.face == .back)
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

    // MARK: The grille

    @Test("The Mac Studio carries the prototype's back grille, and the others carry none")
    func transcribesTheGrille() {
        let grille = Grille(face: .back, u0: 0.06, u1: 0.94, v0: 0.40, v1: 0.94)
        #expect(ReceptacleCatalogue.studioSix.grille == grille)
        #expect(ReceptacleCatalogue.studioFour.grille == grille)
        #expect(ReceptacleCatalogue.mini.grille == nil)
        #expect(ReceptacleCatalogue.notebook.grille == nil)
    }

    @Test("The grille is a surface, not a feature: it adds no row to the face")
    func grilleIsNotAFeature() {
        // The counts `countsEveryFeature` pins are the prototype's rows; the
        // rectangle is a property of the box, exactly as in `MODELS.studio`.
        #expect(ReceptacleCatalogue.studioSix.features.count == 15)
        #expect(ReceptacleCatalogue.studioSix.features(on: .back).count == 11)
        #expect(ReceptacleCatalogue.studioSix.faces == [.back, .front])
    }

    @Test("The grille sits on its face and never reaches into an opening",
          arguments: drawn)
    func grilleClearsEveryOpening(archetype: Archetype) throws {
        let chassis = try #require(ReceptacleCatalogue.chassis(for: archetype))
        guard let grille = chassis.grille else { return }
        #expect(grille.u0 > 0 && grille.u0 < grille.u1 && grille.u1 < 1)
        #expect(grille.v0 > 0 && grille.v0 < grille.v1 && grille.v1 < 1)
        #expect(chassis.faces.contains(grille.face))
        // The renderer stands the grille 0.02 cm proud of the face and every
        // opening 0.01 cm proud, so the two may never overlap in the plane:
        // the grille's lower edge must clear the top of every hole below it.
        let room = chassis.height - chassis.baseBand
        let lowerEdge = chassis.baseBand + grille.v0 * room
        for feature in chassis.features(on: grille.face) {
            let top = chassis.baseBand + feature.v * room + feature.opening.height / 2
            #expect(top < lowerEdge, "\(feature.id) reaches \(top), the grille starts at \(lowerEdge)")
        }
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

    // MARK: Dispatch

    /// The archetypes the catalogue can draw. ``Archetype/unknown`` has no
    /// chassis at all (UX_SPEC §3.4, §6.2 R31), and every test that walks the
    /// catalogue walks these.
    static let drawn = Archetype.allCases.filter { $0 != .unknown }

    @Test("Each archetype dispatches to its own chassis, and the unknown one to none")
    func dispatchesOnArchetype() {
        #expect(ReceptacleCatalogue.chassis(for: .studioSix) == ReceptacleCatalogue.studioSix)
        #expect(ReceptacleCatalogue.chassis(for: .mini) == ReceptacleCatalogue.mini)
        #expect(ReceptacleCatalogue.chassis(for: .notebook) == ReceptacleCatalogue.notebook)
        #expect(ReceptacleCatalogue.chassis(for: .studioFour) == ReceptacleCatalogue.studioFour)
        #expect(ReceptacleCatalogue.chassis(for: .unknown) == nil)
        for archetype in Self.drawn {
            #expect(ReceptacleCatalogue.chassis(for: archetype)?.archetype == archetype)
        }
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

    // MARK: The names the rest of the app uses

    @Test("Every name in the catalogue is one PortPosition would produce")
    func agreesWithThePositionTable() {
        // The two halves of UX_SPEC §4.7 have to meet: the hardware read names
        // a receptacle from `port-location`, the catalogue names the same one
        // from this table, and the port list joins them on that string.
        for archetype in Self.drawn {
            let fromPositions = Set(
                PortFace.allCases.flatMap { face in
                    [PortSlot.left, .leftMiddle, .middle, .rightMiddle, .right,
                     .rear, .front, .unspecified].compactMap {
                        PortPosition(face: face, slot: $0).name(archetype: archetype)
                    }
                }
            )
            let fromCatalogue = Set(
                ReceptacleCatalogue.chassis(for: archetype)?.receptacles.compactMap(\.positionName) ?? []
            )
            #expect(fromCatalogue.isSubset(of: fromPositions))
        }
    }
}
