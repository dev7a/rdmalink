//
//  StageLoop.swift
//
//  UX_SPEC §6.2 R2's recovery: "both receptacles ring and a single light
//  thread is drawn between them, arcing across the chassis — the one time a
//  thread connects two ports of the same machine."
//
//  The rings are the receptacles' own attention rings (§S3). This is the
//  thread: the same light as §4.2's, run from one receptacle to the other
//  along the chassis's footprint the way §4.4's ribbon is, and lifted further
//  off the surface so it reads as a cable's worth of light rather than a tie.
//  While it is up the two receptacles' own outbound threads stand down
//  (StageScene), because two threads leaving for the frame edge is the
//  picture of two Macs, and R2 exists to correct exactly that reading.
//

import Foundation
import RealityKit
import RDMALinkCore
import simd

/// The one thread that connects two ports of the same machine.
@MainActor
final class StageLoopThread {
    let pair: StageLoopedPair
    let root: Entity
    /// The thread's own opacity, cross-faded with the attention rings (§3.5).
    var opacity: Float = 0

    private init(pair: StageLoopedPair, root: Entity) {
        self.pair = pair
        self.root = root
    }

    /// One thread about every 5 mm of curve: a bend between cylinders shows
    /// at a thread's radius sooner than at a ribbon's width.
    private static let segmentLength = 0.5
    private static let minimumSegments = 8
    private static let maximumSegments = 48

    static func make(
        pair: StageLoopedPair, nodes: [StageReceptacleNode], chassis: Chassis,
        palette: StagePalette
    ) -> StageLoopThread? {
        guard
            let from = nodes.first(where: { $0.id == pair.a }),
            let to = nodes.first(where: { $0.id == pair.b })
        else { return nil }
        let start = from.anchor, end = to.anchor
        let span = simd_length(end - start)
        let count = min(
            max(Int((span / segmentLength).rounded()), minimumSegments), maximumSegments
        )
        let room = (chassis.height - max(start.y, end.y)) * 0.45
        let path = StageMath.ribbonPath(
            from: start, to: end,
            halfWidth: chassis.width / 2, halfDepth: chassis.depth / 2,
            lift: StageMath.loopLift(from: start, to: end),
            rise: StageMath.ribbonRise(span: span, room: room), samples: count
        )
        let segments = StageMesh.loopThread(along: path)
        guard !segments.isEmpty else { return nil }

        let root = Entity()
        root.name = "loop.\(pair.a)-\(pair.b)"
        for segment in segments {
            var material = palette.inkMaterial
            material.blending = .transparent(opacity: .init(scale: segment.opacity))
            let entity = ModelEntity(mesh: segment.mesh, materials: [material])
            entity.transform = segment.transform
            root.addChild(entity)
        }
        root.components.set(OpacityComponent(opacity: 0))
        root.isEnabled = false
        return StageLoopThread(pair: pair, root: root)
    }

    func show() {
        root.components.set(OpacityComponent(opacity: opacity))
        let visible = opacity > 0.001
        if root.isEnabled != visible { root.isEnabled = visible }
    }
}
