//
//  StageSceneBuilder.swift
//
//  Turns a `StageModel` and a `RDMALinkCore.Chassis` into entities. It runs
//  whenever the machine, the port list's shape or the appearance changes;
//  per-frame and per-state work belongs to `StageScene`.
//
//  The geometry comes from Core's `ReceptacleCatalogue`, which the CLI and the
//  tests read from the same table. Nothing here carries a number of its own.
//

import AppKit
import RealityKit
import RDMALinkCore
import simd

/// Which ring track an entity belongs to. Every one of these is a distinct
/// geometry, because that is what carries the meaning (UX_SPEC §4.6).
enum StageRingRole: Hashable, CaseIterable, Sendable {
    /// Inner track: a Mac is here (§4.2).
    case inner
    /// Outer track (§4.3).
    case bridge, ready, outside, drift
    /// §S6 and §S10: the same outer-track geometry part way through closing or
    /// re-opening. It stands in for ``bridge`` and ``ready`` for as long as a
    /// real operation is running on the receptacle, and its mesh is swapped —
    /// not cross-faded — because the five shapes *are* the progress (§3.5).
    case progress
    /// §S3's attention ring, which is also §S4b's Identify shimmer: one thin
    /// `.secondary` track, two behaviours, never both at once.
    case attention
    /// Interaction track (§4.6).
    case hover, selection, focus, bloom
    /// The light thread (§4.2, §9.7).
    case thread
    /// §S5's hover-to-preview: the service node beside the receptacle, and the
    /// hairline ring it gains when the addresses row is hovered.
    case serviceNode, serviceRing
}

/// Marks a collider with the port it stands for, so a hit test answers an id.
struct StagePortIdentity: Component {
    let id: String
}

/// Everything the scene needs to drive one receptacle.
@MainActor
final class StageReceptacleNode {
    let id: String
    let kind: FeatureKind
    let face: PortFace
    let root: Entity
    let proxy: Entity
    let stub: Entity
    /// Where this receptacle sits on the chassis, in centimetres in the
    /// chassis's own frame. §4.4's ribbon is drawn between these, which is why
    /// the node carries the number rather than only the transform it became.
    let anchor: SIMD3<Double>
    /// The opening the ring tracks were generated around, and the §3.6 scale
    /// they were generated at — everything ``StageScene`` needs to ask
    /// `StageMesh` for the same ring in a different shape.
    let opening: FeatureKind.Opening
    let ringScale: Double
    var layers: [StageRingRole: Entity] = [:]
    /// What each ring layer was generated from, so a ring whose *shape* has to
    /// change — §S6's closing gaps, §S5's widened ones — can be asked for again
    /// at the same size rather than guessed at from a number copied elsewhere.
    var ringSpec: [StageRingRole: (grow: Double, thickness: Double)] = [:]
    /// Current and target opacity per layer, for the 150 ms cross-fade (§3.5).
    var fades: [StageRingRole: (current: Float, target: Float)] = [:]
    /// The whole-receptacle dim a hovered USB-only hole takes (§4.5).
    var dim: Float = 1
    /// §S6: the ring whose mesh is swapped as gaps close, and the shape it is
    /// currently wearing.
    var progressRing: ModelEntity?
    var progressShape: StageMath.RingPattern?
    /// §4.3's bridge ring, held so §S5's hover-to-preview can widen its gaps.
    var bridgeRing: ModelEntity?
    var bridgeShape: StageMath.RingPattern = .segmented
    /// §S3's single breath and §S4b's bloom need a clock of their own; these
    /// are the moments they started, on the scene's elapsed time.
    var attentionStarted: Double?
    var bloomStarted: Double?
    /// §S8: when the returning pulse reached this receptacle and bloomed.
    var handoffBloomStarted: Double?

    init(
        id: String, kind: FeatureKind, face: PortFace, root: Entity, proxy: Entity,
        stub: Entity, anchor: SIMD3<Double>, opening: FeatureKind.Opening, ringScale: Double
    ) {
        self.id = id
        self.kind = kind
        self.face = face
        self.root = root
        self.proxy = proxy
        self.stub = stub
        self.anchor = anchor
        self.opening = opening
        self.ringScale = ringScale
    }

    var isThunderbolt: Bool { kind == .thunderbolt }
}

/// The built scene.
@MainActor
struct StageSceneGraph {
    var root: Entity
    /// The chassis and everything on it. Ribbons are added and removed here as
    /// bridge membership changes, without rebuilding the machine underneath.
    var body: Entity
    var chassis: Chassis
    var receptacles: [StageReceptacleNode]
    /// §4.4's ribbons, one per tie between two members of a bridge.
    var ribbons: [StageRibbonLink]
    /// §S8's ghost second Mac, off stage until a handoff is up.
    var ghost: StageGhostNode
    /// §6.2 R2's thread between the two ends of one cable, built when
    /// a check names a pair and taken down when it stops.
    var loop: StageLoopThread?
    var keyLight: DirectionalLight
    var fillLight: DirectionalLight
    var rimLight: DirectionalLight
}

@MainActor
enum StageSceneBuilder {
    private static let unit = 0.01  // centimetres to metres

    private static func m(_ centimetres: Double) -> Float { Float(centimetres * unit) }

    /// - Parameter chassis: the catalogue's chassis for this Mac. There is no
    ///   stand-in: an unrecognized Mac never reaches the builder, because the
    ///   stage draws R31's block in place of a scene (§3.4, §6.2 R31).
    static func build(
        ports: [StagePort], chassis: Chassis, palette: StagePalette,
        appearance: StageAppearance
    ) -> StageSceneGraph {
        StagePortIdentity.registerComponent()

        let root = Entity()
        root.name = "stage.root"

        let body = Entity()
        body.name = "stage.chassis"
        root.addChild(body)
        if chassis.isNotebook {
            buildNotebook(chassis, into: body, palette: palette)
        } else {
            buildBox(chassis, into: body, palette: palette)
        }

        for feature in chassis.scenery {
            body.addChild(makeFeature(feature, chassis: chassis, palette: palette))
        }

        var receptacles: [StageReceptacleNode] = []
        for (hole, port) in bind(ports: ports, to: chassis) {
            let node = makeReceptacle(
                hole: hole, port: port, chassis: chassis, palette: palette,
                appearance: appearance
            )
            body.addChild(node.root)
            receptacles.append(node)
        }

        // §4.4: the ribbons come last, so they lie over the chassis rather
        // than inside anything placed on it.
        let ribbons = StageRibbonBuilder.links(
            nodes: receptacles, ports: ports, chassis: chassis, palette: palette
        )
        for link in ribbons { body.addChild(link.root) }

        // §S8's ghost lives beside the chassis, not on it, so it hangs off the
        // stage root and not the body.
        let ghost = StageGhostNode(chassis: chassis, palette: palette, appearance: appearance)
        root.addChild(ghost.root)
        root.addChild(ghost.cable)
        root.addChild(ghost.pulse)

        let lights = makeLights(chassis: chassis, palette: palette, appearance: appearance)
        root.addChild(lights.key)
        root.addChild(lights.fill)
        root.addChild(lights.rim)

        return StageSceneGraph(
            root: root, body: body, chassis: chassis, receptacles: receptacles,
            ribbons: ribbons, ghost: ghost, keyLight: lights.key, fillLight: lights.fill,
            rimLight: lights.rim
        )
    }

    /// UX_SPEC §S8's ghost drawn as the model the user picked: "its shell and
    /// the holes in it", by the same code as this Mac's — the shell, the
    /// grille, every hole on it, and on a MacBook Pro the base and open lid
    /// "with no screen or keyboard laid on them" — and nothing that belongs
    /// to a port or to a Mac that is running: no ring, no plug, no collider,
    /// no identity, and a status light drawn as an unlit hole ("no lit status
    /// light"). No shadow either, as the featureless box casts none: a chosen
    /// model is "ghosted exactly as the box is". Its 40 % is the ghost's, set
    /// on an ancestor.
    static func ghostBody(_ chassis: Chassis, palette: StagePalette) -> Entity {
        let body = Entity()
        body.name = "ghost.chassis"
        if chassis.isNotebook {
            buildNotebook(chassis, into: body, palette: palette, asGhost: true)
        } else {
            buildBox(chassis, into: body, palette: palette, asGhost: true)
        }
        for feature in chassis.features {
            body.addChild(makeFeature(feature, chassis: chassis, palette: palette, lit: false))
        }
        return body
    }

    // MARK: - Binding ports to holes

    /// Ports are matched to catalogue receptacles by face and by their order
    /// within that face — `ChassisFeature.index` — which is the one thing both
    /// sides agree on. A port with no hole left on its face is dropped rather
    /// than drawn somewhere invented: the list in the assistant column is the
    /// complete truth, not the model (§8.1), so a missing receptacle costs
    /// nothing and a wrong one lies.
    private static func bind(
        ports: [StagePort], to chassis: Chassis
    ) -> [(ChassisFeature, StagePort)] {
        var remaining: [PortFace: [ChassisFeature]] = [:]
        for hole in chassis.receptacles { remaining[hole.face, default: []].append(hole) }
        var pairs: [(ChassisFeature, StagePort)] = []
        for port in ports {
            guard var holes = remaining[port.face], !holes.isEmpty else { continue }
            pairs.append((holes.removeFirst(), port))
            remaining[port.face] = holes
        }
        return pairs
    }

    // MARK: - Chassis

    /// - Parameter asGhost: §S8's ghost, which casts no shadow.
    private static func buildBox(
        _ chassis: Chassis, into body: Entity, palette: StagePalette, asGhost: Bool = false
    ) {
        let band = chassis.baseBand
        // The shell is extruded, not boxed. `Chassis.cornerRadius` is a *plan*
        // radius and `Chassis.bevel` is what rounds the top and bottom edges;
        // `MeshResource.generateBox(cornerRadius:)` cannot tell the two apart
        // and fillets all twelve edges by the one number, which on a Mac Studio
        // means a 2.4 cm fillet on an 8.5 cm shell — a bar of soap, with the
        // face receded out from under every receptacle placed on it.
        if let mesh = try? StageMesh.prism(
            width: chassis.width, height: chassis.depth,
            cornerRadius: chassis.cornerRadius, depth: chassis.height - band,
            bevel: chassis.bevel
        ) {
            let shell = ModelEntity(mesh: mesh, materials: [palette.chassisMaterial])
            shell.orientation = StageMesh.standing
            shell.position.y = m(band)
            if !asGhost { shell.components.set(GroundingShadowComponent(castsShadow: true)) }
            body.addChild(shell)
        }

        if band > 0 {
            // §3.4 allows a soft inset at the base and no other vent
            // treatment. It has to read as a shadow line under the body, so it
            // is set back and drawn in a tone between the chassis and a recess.
            // The prototype's 0.55 cm is the right inset now that the shell's
            // footprint really is `width × depth` everywhere above the bevel;
            // under the old fillet the band stood proud on every side.
            let inset = 0.55
            if let mesh = try? StageMesh.prism(
                width: chassis.width - 2 * inset, height: chassis.depth - 2 * inset,
                cornerRadius: max(chassis.cornerRadius - inset, 0.4),
                depth: band + 0.02, bevel: 0.05
            ) {
                let vent = ModelEntity(mesh: mesh, materials: [palette.baseInsetMaterial])
                vent.orientation = StageMesh.standing
                body.addChild(vent)
            }
        }

        if let grille = chassis.grille {
            body.addChild(makeGrille(grille, chassis: chassis, palette: palette))
        }
    }

    /// The perforated grille the catalogue puts on a face: one strip on the
    /// shell's outline wearing one alpha-masked tile, never a hole per hole —
    /// the Mac Studio's is some 9,900 of them, and a `studioSix` rebuild is
    /// already a visible hitch at 130 entities.
    ///
    /// It carries no collider, no input target and no `StagePortIdentity`, so
    /// `StageScene.portID(at:)` never sees it, exactly like the shell under it.
    private static func makeGrille(
        _ grille: Grille, chassis: Chassis, palette: StagePalette
    ) -> Entity {
        let room = chassis.height - chassis.baseBand
        guard
            let texture = try? StageMesh.grille(),
            let mesh = try? StageMesh.grilleStrip(
                face: grille.face, u0: grille.u0, u1: grille.u1,
                y0: chassis.baseBand + grille.v0 * room,
                y1: chassis.baseBand + grille.v1 * room,
                width: chassis.width, depth: chassis.depth, cornerRadius: chassis.cornerRadius
            )
        else { return Entity() }
        let strip = ModelEntity(mesh: mesh, materials: [palette.grilleMaterial(texture: texture)])
        strip.name = "stage.grille"
        return strip
    }

    /// - Parameter asGhost: §S8's ghost: the base, the feet and the lid, and
    ///   none of the screen, keyboard and trackpad laid over them. Those are
    ///   flat inlays stacked on the shell, and at the ghost's 40 % each one
    ///   darkens the one under it, so the lid read as a black slab in the dark
    ///   appearance — not "ghosted exactly as the box is". No shadow either.
    private static func buildNotebook(
        _ chassis: Chassis, into body: Entity, palette: StagePalette, asGhost: Bool = false
    ) {
        guard let lid = chassis.lid else { return }
        // Extruded for the same reason the desktop shell is: a 1.55 cm base
        // filleted by a 1.0 cm plan radius is a cushion, and the two side
        // faces the notebook's receptacles sit on stop being flat.
        if let mesh = try? StageMesh.prism(
            width: chassis.width, height: chassis.depth,
            cornerRadius: chassis.cornerRadius, depth: chassis.height, bevel: chassis.bevel
        ) {
            let base = ModelEntity(mesh: mesh, materials: [palette.chassisMaterial])
            base.orientation = StageMesh.standing
            if !asGhost { base.components.set(GroundingShadowComponent(castsShadow: true)) }
            body.addChild(base)
        }

        let foot = MeshResource.generateCylinder(height: m(0.18), radius: m(0.7))
        for x in [-1.0, 1.0] {
            for z in [-1.0, 1.0] {
                let entity = ModelEntity(mesh: foot, materials: [palette.sceneryMaterial])
                entity.position = SIMD3(
                    m(x * (chassis.width / 2 - 2.6)), m(0.09),
                    m(z * (chassis.depth / 2 - 2.0))
                )
                body.addChild(entity)
            }
        }

        let panel = Entity()
        panel.position = SIMD3(0, m(chassis.height + 0.05), m(-chassis.depth / 2 + 0.55))
        panel.orientation = simd_quatf(
            angle: Float(-lid.openAngle * .pi / 180), axis: SIMD3(1, 0, 0)
        )
        // The prototype bevels the lid by 0.12 rather than by the body's own
        // bevel — 0.22 is more than half of a 0.42 cm panel.
        if let mesh = try? StageMesh.prism(
            width: chassis.width, height: lid.depth, cornerRadius: chassis.cornerRadius,
            depth: lid.thickness, bevel: 0.12
        ) {
            let shell = ModelEntity(mesh: mesh, materials: [palette.chassisMaterial])
            shell.orientation = StageMesh.standing
            shell.position = SIMD3(0, 0, m(lid.depth / 2))
            if !asGhost { shell.components.set(GroundingShadowComponent(castsShadow: true)) }
            panel.addChild(shell)
        }
        body.addChild(panel)
        guard !asGhost else { return }

        let wellZ = -chassis.depth / 2 + 1.2 + 5.7
        let well = ModelEntity(
            mesh: .generatePlane(width: m(27.4), height: m(11.4), cornerRadius: m(0.4)),
            materials: [palette.keyboardMaterial]
        )
        well.position = SIMD3(0, m(chassis.height + 0.012), m(wellZ))
        well.orientation = faceUp
        body.addChild(well)

        let key = MeshResource.generatePlane(width: m(1.55), height: m(1.5))
        let keyMaterial = palette.sceneryMaterial
        for row in 0..<5 {
            for column in 0..<14 {
                let cap = ModelEntity(mesh: key, materials: [keyMaterial])
                cap.position = SIMD3(
                    m(-12.35 + Double(column) * 1.9), m(chassis.height + 0.02),
                    m(-chassis.depth / 2 + 1.2 + 1.7 + Double(row) * 1.9)
                )
                cap.orientation = faceUp
                body.addChild(cap)
            }
        }

        let trackpad = ModelEntity(
            mesh: .generatePlane(width: m(13.0), height: m(8.2), cornerRadius: m(0.3)),
            materials: [palette.chassisMaterial]
        )
        trackpad.position = SIMD3(
            0, m(chassis.height + 0.014), m(chassis.depth / 2 - 0.8 - 4.1)
        )
        trackpad.orientation = faceUp
        body.addChild(trackpad)

        let bezel = ModelEntity(
            mesh: .generatePlane(
                width: m(chassis.width - 0.5), height: m(lid.depth - 0.7),
                cornerRadius: m(0.6)
            ),
            materials: [palette.screenMaterial]
        )
        bezel.position = SIMD3(
            0, m(lid.thickness + 0.01), m(lid.depth / 2 + 0.05)
        )
        bezel.orientation = faceUp
        panel.addChild(bezel)

        let screen = ModelEntity(
            mesh: .generatePlane(
                width: m(chassis.width - 1.4), height: m(lid.depth - 1.6),
                cornerRadius: m(0.35)
            ),
            materials: [palette.screenMaterial]
        )
        screen.position = SIMD3(
            0, m(lid.thickness + 0.02), m(lid.depth / 2 + 0.05)
        )
        screen.orientation = faceUp
        panel.addChild(screen)

        let notch = ModelEntity(
            mesh: .generatePlane(width: m(3.2), height: m(0.9)),
            materials: [palette.screenMaterial]
        )
        notch.position = SIMD3(
            0, m(lid.thickness + 0.03), m(lid.depth - 0.75 - 0.45)
        )
        notch.orientation = faceUp
        panel.addChild(notch)
    }

    // MARK: - Holes

    /// One hole or fitting on the chassis. This Mac's build passes scenery
    /// only, because its receptacles are ``makeReceptacle(hole:port:chassis:palette:appearance:)``'s;
    /// §S8's ghost passes every feature, receptacles as the bare recess that
    /// receptacle cuts.
    ///
    /// - Parameter lit: `false` on §S8's ghost, whose status light is a hole
    ///   like any other — a lit one would say the other Mac is on.
    private static func makeFeature(
        _ feature: ChassisFeature, chassis: Chassis, palette: StagePalette, lit: Bool = true
    ) -> Entity {
        let opening = feature.opening
        let entity = Entity()
        let placement = place(
            face: feature.face, u: feature.u, v: feature.v, chassis: chassis
        )
        entity.position = placement
        entity.orientation = orientation(for: feature.face)

        let material: AnyMaterialBox = switch feature.kind {
        case .indicator where lit: .unlit(palette.indicatorMaterial)
        case .thunderbolt: .surface(palette.recessMaterial)
        case .usbC: .surface(palette.usbRecessMaterial)
        default: .surface(palette.sceneryMaterial)
        }
        // Extruded rather than boxed so the catalogue's corner radius survives:
        // `generateBox` clamps it to half the smallest dimension, and the
        // smallest dimension here is the 0.16 cm depth, which would make the
        // Mac Studio's round power socket and its headphone jack rounded
        // squares at a radius of 0.08. A receptacle is as deep as
        // `makeReceptacle` cuts it.
        guard
            let mesh = try? StageMesh.prism(
                width: opening.width, height: opening.height,
                cornerRadius: opening.cornerRadius,
                depth: feature.kind.isReceptacle ? 0.22 : 0.16
            )
        else { return entity }
        let hole = ModelEntity(mesh: mesh, materials: [material.material])
        hole.position.z = m(0.01)
        entity.addChild(hole)
        return entity
    }

    private static func makeReceptacle(
        hole: ChassisFeature, port: StagePort, chassis: Chassis, palette: StagePalette,
        appearance: StageAppearance
    ) -> StageReceptacleNode {
        // The catalogue has already turned the opening a quarter turn where the
        // chassis stands its receptacles on edge, so the size is read straight.
        let size = hole.opening
        let root = Entity()
        root.name = "receptacle.\(port.id)"
        let anchor = placeInCentimetres(
            face: hole.face, u: hole.u, v: hole.v, chassis: chassis
        )
        root.position = SIMD3(m(anchor.x), m(anchor.y), m(anchor.z))
        root.orientation = orientation(for: hole.face)

        // §3.4: a true inset slot with a darker interior, so an unlit port
        // reads as a hole and not a sticker. Extruded, so §4.5's "correct,
        // slightly different geometry" survives — a USB-C stadium is a 0.17
        // radius on a 0.35 cm extent, which `generateBox` would have clamped
        // to 0.11 by the recess depth and collapsed toward the Thunderbolt
        // slit it is supposed to differ from.
        if let mesh = try? StageMesh.prism(
            width: size.width, height: size.height,
            cornerRadius: size.cornerRadius, depth: 0.22
        ) {
            let recess = ModelEntity(
                mesh: mesh,
                materials: [
                    hole.kind == .usbC ? palette.usbRecessMaterial : palette.recessMaterial
                ]
            )
            recess.position.z = m(0.01)
            root.addChild(recess)
        }

        // §4.2: the plug stub, in a grey that deliberately does not match.
        let stub = ModelEntity(
            mesh: .generateBox(
                width: m(max(size.width - 0.16, 0.12)),
                height: m(max(size.height - 0.16, 0.12)),
                depth: m(0.55), cornerRadius: m(0.06)
            ),
            materials: [palette.stubMaterial]
        )
        stub.position.z = m(0.295)
        stub.isEnabled = false
        root.addChild(stub)

        // §8.4: a generous invisible collider, never smaller than 24 × 24 pt
        // at any zoom the dolly allows.
        let collider = hole.colliderSize
        let proxy = Entity()
        proxy.position.z = m(0.15)
        proxy.components.set(
            CollisionComponent(
                shapes: [
                    .generateBox(
                        width: m(collider.width), height: m(collider.height), depth: m(0.5)
                    )
                ],
                mode: .trigger
            )
        )
        proxy.components.set(InputTargetComponent())
        proxy.components.set(StagePortIdentity(id: port.id))
        root.addChild(proxy)

        let node = StageReceptacleNode(
            id: port.id, kind: hole.kind, face: hole.face, root: root, proxy: proxy,
            stub: stub, anchor: anchor, opening: size, ringScale: appearance.ringScale
        )

        // §4.5: USB-only receptacles never take a ring of any kind.
        guard hole.kind == .thunderbolt else { return node }

        let scale = appearance.ringScale
        @discardableResult
        func add(
            _ role: StageRingRole, grow: Double, thickness: Double,
            pattern: StageMath.RingPattern, accent: Bool, z: Double
        ) -> ModelEntity? {
            guard
                let mesh = try? StageMesh.ring(
                    width: size.width + grow, height: size.height + grow,
                    cornerRadius: size.cornerRadius + grow / 2, thickness: thickness * scale,
                    pattern: pattern
                )
            else { return nil }
            let entity = ModelEntity(
                mesh: mesh,
                materials: [accent ? palette.accentMaterial : palette.inkMaterial]
            )
            entity.position.z = m(z)
            entity.components.set(OpacityComponent(opacity: 0))
            entity.isEnabled = false
            root.addChild(entity)
            node.layers[role] = entity
            node.ringSpec[role] = (grow, thickness)
            node.fades[role] = (0, 0)
            return entity
        }

        add(.inner, grow: 0.16, thickness: 0.07, pattern: .solid, accent: false, z: 0.10)
        add(.attention, grow: 0.30, thickness: 0.07, pattern: .solid, accent: false, z: 0.10)
        node.bridgeRing = add(
            .bridge, grow: 0.50, thickness: 0.08, pattern: .segmented, accent: false, z: 0.10
        )
        add(.ready, grow: 0.50, thickness: 0.09, pattern: .solid, accent: true, z: 0.10)
        add(.drift, grow: 0.50, thickness: 0.08, pattern: .dashed, accent: false, z: 0.10)
        add(.hover, grow: 1.00, thickness: 0.08, pattern: .solid, accent: true, z: 0.12)
        add(.selection, grow: 1.00, thickness: 0.11, pattern: .solid, accent: true, z: 0.12)

        // §S6: the ring the work is drawn on. It is the bridge ring's geometry
        // in accent, because §S6 ends on "a solid accent ring" and the four
        // arcs it starts from are the same four the port is already wearing —
        // "the whole lifecycle of a port is one shape" (§4.3). Its mesh is
        // swapped as gaps close, so the five states are five shapes and not
        // five cross-fades.
        node.progressRing = add(
            .progress, grow: 0.50, thickness: 0.09, pattern: .closing(gaps: 0),
            accent: true, z: 0.105
        )
        node.progressShape = .closing(gaps: 0)

        // §S5's hover-to-preview: "a small accent node fades in beside the
        // receptacle", and "the node gains a single hairline ring". Beside is
        // read as the axis the receptacle is *not* long on — above a standing
        // desktop slot, off the end of a notebook's — which is the one
        // direction with room on every chassis in the catalogue.
        let isStanding = size.height > size.width
        // Far enough out to clear the selection ring and its bloom. A standing
        // slot has the whole face above it; a notebook's lies along a 1.55 cm
        // edge, where the only room is towards the next receptacle, so it gets
        // what there is and no more.
        let nodeOffset = max(size.width, size.height) / 2 + (isStanding ? 1.05 : 0.70)
        let nodeCentre = SIMD3<Float>(
            isStanding ? 0 : m(nodeOffset), isStanding ? m(nodeOffset) : 0, m(0.11)
        )
        let serviceDiameter = 0.30
        let serviceNode = ModelEntity(
            mesh: StageMesh.bloom(
                width: serviceDiameter, height: serviceDiameter,
                cornerRadius: serviceDiameter / 2
            ),
            materials: [palette.accentMaterial]
        )
        serviceNode.position = nodeCentre
        serviceNode.components.set(OpacityComponent(opacity: 0))
        serviceNode.isEnabled = false
        root.addChild(serviceNode)
        node.layers[.serviceNode] = serviceNode
        node.fades[.serviceNode] = (0, 0)

        if let mesh = try? StageMesh.ring(
            width: serviceDiameter + 0.26, height: serviceDiameter + 0.26,
            cornerRadius: (serviceDiameter + 0.26) / 2, thickness: 0.05 * scale,
            pattern: .solid
        ) {
            let serviceRing = ModelEntity(mesh: mesh, materials: [palette.accentMaterial])
            serviceRing.position = nodeCentre
            serviceRing.components.set(OpacityComponent(opacity: 0))
            serviceRing.isEnabled = false
            root.addChild(serviceRing)
            node.layers[.serviceRing] = serviceRing
            node.fades[.serviceRing] = (0, 0)
        }

        // §4.3: "set up outside RDMALink" is complete like ready, but drawn as
        // two thin concentric hairlines and never in accent, because it is not
        // RDMALink's.
        //
        // §4.1 fixes every track at 1.5 pt, which at the resting distance is
        // about 0.076 cm; a hairline is the one thing allowed to sit under
        // that, and 0.06 cm is as thin as it can go and still be drawn — the
        // 0.04 cm it was aliased away entirely at every zoom the dolly allows.
        // The two grows are set 0.12 cm apart so the pair still reads as two
        // concentric lines with a gap rather than as one thick ring.
        let outside = Entity()
        outside.position.z = m(0.10)
        for grow in [0.40, 0.64] {
            guard
                let mesh = try? StageMesh.ring(
                    width: size.width + grow, height: size.height + grow,
                    cornerRadius: size.cornerRadius + grow / 2, thickness: 0.06 * scale,
                    pattern: .solid
                )
            else { continue }
            outside.addChild(ModelEntity(mesh: mesh, materials: [palette.inkMaterial]))
        }
        outside.components.set(OpacityComponent(opacity: 0))
        outside.isEnabled = false
        root.addChild(outside)
        node.layers[.outside] = outside
        node.fades[.outside] = (0, 0)

        // §8.3: keyboard focus takes a halo visually separate from both hover
        // and selection — outermost, accent, and doubled rather than single.
        let focus = Entity()
        focus.position.z = m(0.13)
        for grow in [1.32, 1.56] {
            guard
                let mesh = try? StageMesh.ring(
                    width: size.width + grow, height: size.height + grow,
                    cornerRadius: size.cornerRadius + grow / 2, thickness: 0.05 * scale,
                    pattern: .solid
                )
            else { continue }
            focus.addChild(ModelEntity(mesh: mesh, materials: [palette.accentMaterial]))
        }
        focus.components.set(OpacityComponent(opacity: 0))
        focus.isEnabled = false
        root.addChild(focus)
        node.layers[.focus] = focus
        node.fades[.focus] = (0, 0)

        let bloom = ModelEntity(
            mesh: StageMesh.bloom(
                width: size.width + 1.6, height: size.height + 1.6,
                cornerRadius: size.cornerRadius + 0.8
            ),
            materials: [palette.accentMaterial]
        )
        bloom.position.z = m(0.11)
        bloom.components.set(OpacityComponent(opacity: 0))
        bloom.isEnabled = false
        root.addChild(bloom)
        node.layers[.bloom] = bloom
        node.fades[.bloom] = (0, 0)

        // §4.2's thread is one tube and one material; the fade along its
        // length is the material's texture, not a stack of opacities.
        let thread = Entity()
        if let mesh = StageMesh.thread(), let fade = try? StageMesh.threadFade() {
            thread.addChild(
                ModelEntity(mesh: mesh, materials: [palette.threadMaterial(fade: fade)])
            )
        }
        thread.components.set(OpacityComponent(opacity: 0))
        thread.isEnabled = false
        root.addChild(thread)
        node.layers[.thread] = thread
        node.fades[.thread] = (0, 0)

        return node
    }

    // MARK: - Lighting

    private static func makeLights(
        chassis: Chassis, palette: StagePalette, appearance: StageAppearance
    ) -> (key: DirectionalLight, fill: DirectionalLight, rim: DirectionalLight) {
        let target = SIMD3<Float>(0, m(chassis.focus), 0)

        // §3.4: one key from upper-left for a defined top edge, plus a soft
        // contact shadow. The IBL is the generated environment, not a light.
        let key = DirectionalLight()
        key.light = DirectionalLightComponent(
            color: .white, intensity: appearance.isDark ? 1800 : 2600
        )
        key.shadow = DirectionalLightComponent.Shadow(
            shadowProjection: .automatic(maximumDistance: 1.2), depthBias: 1.4
        )
        key.look(at: target, from: SIMD3(m(-18), m(32), m(14)), relativeTo: nil)

        let fill = DirectionalLight()
        fill.light = DirectionalLightComponent(color: .white, intensity: 620)
        fill.shadow = nil
        fill.look(at: target, from: SIMD3(m(10), m(6), m(26)), relativeTo: nil)

        // §3.4: in dark mode a cool rim light carries the silhouette.
        let rim = DirectionalLight()
        rim.light = DirectionalLightComponent(
            color: NSColor(srgbRed: 0.87, green: 0.90, blue: 1.0, alpha: 1),
            intensity: appearance.isDark ? 1400 : 420
        )
        rim.shadow = nil
        rim.look(at: target, from: SIMD3(m(22), m(12), m(-26)), relativeTo: nil)

        return (key, fill, rim)
    }

    // MARK: - Placement

    /// Faces: back is `-z`, front `+z`, left `-x`, right `+x`; `u` runs from
    /// the viewer's left as they look at that face, which is what makes
    /// "Back, far left" land on the correct hole.
    static func place(
        face: PortFace, u: Double, v: Double, chassis: Chassis
    ) -> SIMD3<Float> {
        let centimetres = placeInCentimetres(face: face, u: u, v: v, chassis: chassis)
        return SIMD3(m(centimetres.x), m(centimetres.y), m(centimetres.z))
    }

    /// The same placement in centimetres, which is what §4.4's ribbon is drawn
    /// from: it walks the chassis's own footprint between two of these, and
    /// every number in the catalogue is a centimetre.
    static func placeInCentimetres(
        face: PortFace, u: Double, v: Double, chassis: Chassis
    ) -> SIMD3<Double> {
        let across = (face == .back || face == .front) ? chassis.width : chassis.depth
        let along = (u - 0.5) * across
        let band = chassis.baseBand
        let y = band + v * (chassis.height - band)
        switch face {
        case .back: return SIMD3(-along, y, -chassis.depth / 2)
        case .front: return SIMD3(along, y, chassis.depth / 2)
        case .left: return SIMD3(-chassis.width / 2, y, along)
        case .right: return SIMD3(chassis.width / 2, y, -along)
        }
    }

    /// The yaw that points an entity's `+z` out of a face, so that its `+x`
    /// runs the same way `u` does.
    static func yaw(for face: PortFace) -> Double {
        switch face {
        case .front: 0
        case .right: .pi / 2
        case .back: .pi
        case .left: -.pi / 2
        }
    }

    private static func orientation(for face: PortFace) -> simd_quatf {
        simd_quatf(angle: Float(yaw(for: face)), axis: SIMD3(0, 1, 0))
    }

    /// Lays a generated plane — built in XY, facing `+z` — flat, facing `+y`.
    private static let faceUp = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
}

/// `PhysicallyBasedMaterial` and `UnlitMaterial` are different types; this is
/// the one place the stage has to hold either.
private enum AnyMaterialBox {
    case surface(PhysicallyBasedMaterial)
    case unlit(UnlitMaterial)

    var material: any Material {
        switch self {
        case .surface(let value): value
        case .unlit(let value): value
        }
    }
}
