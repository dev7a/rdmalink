//
//  StageRibbon.swift
//
//  UX_SPEC §4.4's bridge ribbon: "a soft translucent ribbon arcing across the
//  chassis surface between the members of the same bridge, in `.secondary` tone
//  at low opacity."
//
//  It is what makes the hardest rule in the product visible rather than merely
//  stated — *a port must be out of **every** bridge, even an inactive one* —
//  so an inactive bridge draws the same ribbon at 40 % and a marginally cooler
//  value, and the ribbon never replaces the segmented ring it accompanies.
//
//  The curve itself is `StageMath.ribbonPath`, which walks the chassis's own
//  footprint rather than cutting between two receptacles, so two ports on one
//  face get a shallow arc along that face and two ports on different faces get
//  one that wraps the corner instead of passing through the machine.
//

import Foundation
import RealityKit
import RDMALinkCore
import simd

/// One tie between two members of the same bridge.
///
/// Built in segments for the same reason the light thread is: retraction is a
/// per-segment opacity, and one mesh would need a shader to come apart from
/// one end (§9.3 — "the ribbon lets go").
@MainActor
final class StageRibbonLink {
    /// The kernel bridge these two ports share, `bridge0`.
    let bridge: String
    /// §4.4: an inactive bridge draws at 40 % of the ribbon's opacity.
    let isActive: Bool
    /// The two members, in the order the segments run.
    let a: StagePort.ID
    let b: StagePort.ID
    let root: Entity
    /// Segments from `a` to `b`. `positions[i]` is where segment `i` sits along
    /// the ribbon, 0 at `a` and 1 at `b`.
    let segments: [Entity]
    let positions: [Double]

    /// The link's own opacity, cross-faded (§3.5).
    var opacity: Float = 0
    /// How far the ribbon has retracted away from each end, 0…1 (§S6).
    var retractionFromA: Float = 0
    var retractionFromB: Float = 0
    /// What was last written to each segment, so a settled ribbon costs nothing.
    var applied: [Float]

    init(
        bridge: String, isActive: Bool, a: StagePort.ID, b: StagePort.ID,
        root: Entity, segments: [Entity], positions: [Double]
    ) {
        self.bridge = bridge
        self.isActive = isActive
        self.a = a
        self.b = b
        self.root = root
        self.segments = segments
        self.positions = positions
        self.applied = Array(repeating: -1, count: segments.count)
    }

    func touches(_ id: StagePort.ID) -> Bool { a == id || b == id }
}

@MainActor
enum StageRibbonBuilder {
    /// How wide the ribbon is, in centimetres. Wide enough to read as a ribbon
    /// rather than a wire at the resting distance, narrow enough that it never
    /// competes with the ring tracks it arcs over — at 0.16 cm it is twice a
    /// ring's thickness and a sixth of its opacity.
    private static let width = 0.16
    /// One segment about every 8 mm of curve, so the retraction comes apart
    /// smoothly without generating meshes nobody can see.
    private static let segmentLength = 0.8
    private static let minimumSegments = 6
    private static let maximumSegments = 30

    /// Every ribbon this set of receptacles calls for.
    ///
    /// Members of a bridge are tied **consecutively**, in physical order, not
    /// all-to-all: §4.4 asks for a ribbon "between the members of the same
    /// bridge", and a chain says exactly that while a full mesh would put a
    /// cat's cradle over the machine. Leaving a chain is still leaving the
    /// ribbon: the links that touch the chosen receptacle are the ones that
    /// retract into the others (§S6).
    static func links(
        nodes: [StageReceptacleNode], ports: [StagePort], chassis: Chassis,
        palette: StagePalette
    ) -> [StageRibbonLink] {
        let anchors = Dictionary(
            nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        // Physical order is the order the ports arrive in, which is the order
        // the list draws and VoiceOver walks (§2.3).
        var members: [String: [StagePort]] = [:]
        var active: [String: Bool] = [:]
        for port in ports where port.isThunderbolt {
            for bridge in port.bridges {
                members[bridge.id, default: []].append(port)
                // A bridge is up or it is not; the ports agree, and if they
                // ever disagreed the honest answer is the quieter one.
                active[bridge.id] = (active[bridge.id] ?? true) && bridge.isActive
            }
        }

        var links: [StageRibbonLink] = []
        for name in members.keys.sorted() {
            let ports = members[name] ?? []
            guard ports.count > 1 else { continue }
            for index in 0..<(ports.count - 1) {
                guard
                    let from = anchors[ports[index].id],
                    let to = anchors[ports[index + 1].id],
                    let link = make(
                        bridge: name, isActive: active[name] ?? true,
                        from: from, to: to, chassis: chassis, palette: palette
                    )
                else { continue }
                links.append(link)
            }
        }
        return links
    }

    private static func make(
        bridge: String, isActive: Bool, from: StageReceptacleNode, to: StageReceptacleNode,
        chassis: Chassis, palette: StagePalette
    ) -> StageRibbonLink? {
        let start = from.anchor, end = to.anchor
        let span = simd_length(end - start)
        let count = min(
            max(Int((span / segmentLength).rounded()), minimumSegments), maximumSegments
        )
        // How much face there is above the two receptacles, which is what
        // decides how far the ribbon may arc over them. Receptacles sit low on
        // their face on every chassis in the catalogue except a notebook's
        // side, where there is barely any room at all and the arc is a hair.
        let room = (chassis.height - max(start.y, end.y)) * 0.45
        let path = StageMath.ribbonPath(
            from: start, to: end,
            halfWidth: chassis.width / 2, halfDepth: chassis.depth / 2,
            lift: StageMath.ribbonLift(from: start, to: end),
            rise: StageMath.ribbonRise(span: span, room: room), samples: count
        )
        guard path.count > 2 else { return nil }

        let material = palette.ribbonMaterial(active: isActive)
        let root = Entity()
        root.name = "ribbon.\(bridge).\(from.id)-\(to.id)"
        root.components.set(OpacityComponent(opacity: 0))
        root.isEnabled = false

        var segments: [Entity] = []
        var positions: [Double] = []
        for index in 0..<(path.count - 1) {
            guard
                let mesh = try? StageMesh.ribbonSegment(
                    from: path[index], to: path[index + 1], width: width
                )
            else { continue }
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.components.set(OpacityComponent(opacity: 1))
            root.addChild(entity)
            segments.append(entity)
            positions.append((Double(index) + 0.5) / Double(path.count - 1))
        }
        guard !segments.isEmpty else { return nil }
        return StageRibbonLink(
            bridge: bridge, isActive: isActive, a: from.id, b: to.id,
            root: root, segments: segments, positions: positions
        )
    }
}
