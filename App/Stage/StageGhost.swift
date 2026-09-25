//
//  StageGhost.swift
//
//  UX_SPEC §S8's ghost second Mac: "A ghost of the other Mac at 40 % opacity —
//  a featureless rounded box, or the chassis the `Other Mac:` pop-up names —
//  slides in from the trailing side with a single thin connecting line from
//  that port to it. … The near port carries its solid accent ring; the far
//  port is hollow and unlit." "The ghost stays featureless unless the user
//  says which Mac it is, and even then it carries no port states — no ring
//  but the far port's, no plug, no thread, no lit status light — and nothing
//  is written on it or on this Mac." "When the far end answers on the link, a
//  returning pulse travels back along the line and blooms at the near
//  receptacle, once."
//
//  The box is this Mac's own footprint with nothing on it, because the app
//  knows nothing about the other machine and a shape that claimed to would be
//  a lie (§1.3). A chosen model is that family's chassis from the catalogue,
//  drawn by the same builder as this Mac's (`StageSceneBuilder.ghostBody`) and
//  "ghosted exactly as the box is, at the same 40 % and with no shadow": the
//  user's word and the catalogue are the only things it is drawn from. The
//  ghost is built with the graph, disabled at opacity 0, and `StageScene`
//  places it for the face the handoff is staged on and slides it in;
//  `StageScene.settle` puts it straight at its resting place for the review
//  hook's off-screen render.
//

import Foundation
import RealityKit
import RDMALinkCore
import simd

/// Where the ghost and its cable go for a handoff staged on one face, in the
/// chassis's own centimetres. Pure over the two chassis, so the camera's
/// framing and the ghost's placement are one calculation. On the main actor
/// only because the face-to-yaw table and the face placement it reads are the
/// scene builder's.
@MainActor
struct StageHandoffLayout: Equatable {
    let face: PortFace
    /// Screen-right for a camera square on to `face`: the side the ghost
    /// slides in from and settles on.
    let right: SIMD3<Double>
    /// Out of `face`: the direction the cable leaves both ports.
    let normal: SIMD3<Double>
    /// Centre to centre.
    let gap: Double
    /// This Mac's footprint circumcircle — its silhouette at any pose.
    let across: Double
    /// What the ghost is drawn as: a chassis family, or `nil` for the box.
    let ghost: Archetype?
    /// The ghost's own face the line goes into. On the box it is `face`
    /// itself — the box is this Mac's footprint, standing the same way — and
    /// on a chosen model it is that model's usual face
    /// (``Chassis/usualCableFace``).
    let ghostFace: PortFace
    /// How far the ghost is turned about the vertical so that ``ghostFace``
    /// looks the way this Mac's `face` does: 0 on the box.
    let ghostYaw: Double
    /// The ghost's footprint extent along `right` and along `normal`.
    let extentAlongRight: Double
    let extentAlongNormal: Double
    /// The ghost's footprint circumcircle.
    let ghostAcross: Double
    /// How far along `right` the framing reaches from this Mac's centre:
    /// the ghost's far side, or the box's where that is further
    /// (``StageMath/handoffFarEdge(gap:ghostAcross:boxGap:across:)``).
    let farEdge: Double
    /// The pair's framing height and the height the camera looks at: this
    /// Mac's own on the box, the taller of the two with a chosen model — a
    /// MacBook Pro's open lid beside a Mac mini.
    let height: Double
    let focus: Double
    /// A chosen model's far port in its own chassis's frame, before the turn;
    /// `nil` on the box, whose port follows the near port's height.
    private let chosenPort: SIMD3<Double>?

    /// - Parameter ghost: the chassis the user picked in §S8's pop-up, or
    ///   `nil` for **Any Mac**'s box.
    init(face: PortFace, chassis: Chassis, ghost: Chassis? = nil) {
        let yaw = StageSceneBuilder.yaw(for: face)
        self.face = face
        right = StageMath.screenRight(yaw: yaw)
        normal = StageMath.outwardNormal(yaw: yaw)
        across = chassis.footprintAcross

        let shape = ghost ?? chassis
        let port = ghost?.ghostPort
        self.ghost = ghost?.archetype
        ghostFace = port?.face ?? face
        ghostYaw = yaw - StageSceneBuilder.yaw(for: ghostFace)
        let alongFace = ghostFace == .back || ghostFace == .front
        extentAlongRight = alongFace ? shape.width : shape.depth
        extentAlongNormal = alongFace ? shape.depth : shape.width
        ghostAcross = shape.footprintAcross
        height = max(chassis.visibleHeight, ghost?.visibleHeight ?? 0)
        focus = max(chassis.focus, ghost?.focus ?? 0)
        chosenPort = port.flatMap { port in
            ghost.map {
                StageSceneBuilder.placeInCentimetres(face: port.face, u: port.u, v: port.v, chassis: $0)
            }
        }
        // A MacBook Pro's lid leans back over its hinge, and its hinge is on
        // the side nearest this Mac once its left side faces the camera, so
        // the daylight between the two is measured to the lid, not the base.
        let back = StageMath.turn(SIMD3(0, 0, -1), yaw: ghostYaw)
        let leansTowardThisMac = simd_dot(back, -right) > 0.5
        gap = StageMath.handoffGap(
            extentAlongRight: extentAlongRight, across: across,
            overhang: leansTowardThisMac ? (ghost?.lidLean ?? 0) : 0
        )
        // The box is this Mac's footprint standing the same way, so its gap
        // is this Mac's own extent along `right`.
        let boxGap = StageMath.handoffGap(
            extentAlongRight: face == .back || face == .front ? chassis.width : chassis.depth,
            across: across
        )
        farEdge = StageMath.handoffFarEdge(
            gap: gap, ghostAcross: ghostAcross, boxGap: boxGap, across: across
        )
    }

    /// The ghost's centre on the ground plane.
    var centre: SIMD3<Double> { right * gap }

    /// Half way across the framing, on the ground plane — from this Mac's
    /// leading side to ``farEdge`` — where the camera looks so that this Mac
    /// takes the leading third and the ghost the rest. On the box, which is
    /// this Mac's footprint, half way between the two centres; beside a
    /// smaller ghost, the same place: §S8 gives a ghost that fits where the
    /// box stood "the box's room".
    var midpoint: SIMD3<Double> { right * ((farEdge - across / 2) / 2) }

    /// The framing's width: this Mac's outer half and ``farEdge``.
    var framingWidth: Double { farEdge + across / 2 }

    /// The box's port sits low on the box's near edge, so the cable is short
    /// and the two ports face the same way.
    static let portInset = 2.2

    /// The box's height: this Mac's own, but a notebook's base is a plate,
    /// and a plate is not the "rounded box" §S8 draws, so the ghost of one is
    /// given a box's height.
    static func boxHeight(for chassis: Chassis) -> Double {
        chassis.isNotebook ? 5.0 : chassis.height
    }

    /// The hollow port on the ghost, in world centimetres. On the box it is
    /// at `nearHeight`, level with the near port; on a chosen model it is
    /// where that model's catalogue puts it.
    func farPort(nearHeight: Double) -> SIMD3<Double> {
        if let chosenPort { return centre + StageMath.turn(chosenPort, yaw: ghostYaw) }
        return centre - right * (extentAlongRight / 2 - Self.portInset)
            + normal * (extentAlongNormal / 2) + SIMD3(0, nearHeight, 0)
    }
}

/// The ghost, its hollow port, the cable and the returning pulse.
@MainActor
final class StageGhostNode {
    /// §S8: "at 40 % opacity".
    static let restingOpacity: Float = 0.4
    /// §S8: a new pick in the pop-up "redraws the ghost in place with a short
    /// cross-fade — under Reduce Motion it simply changes". Short against the
    /// camera's 0.7 s, so the new Mac has arrived while the camera is still
    /// framing it.
    static let crossFadeDuration = 0.3
    /// The cable is a line, not a ribbon: thinner than a ring track and
    /// quieter than the ghost it joins. Constant over the whole run — §S8
    /// asks for "a single thin connecting line", and a line that thinned
    /// towards one end would say which Mac it belongs to.
    private static let cableRadius = 0.045
    private static let cableOpacity: Float = 0.6
    private static let pulseRadius = 0.16

    /// The ghost, a child of the graph's root. Its position is the ghost's
    /// resting place plus however much of the slide is left; what it draws is
    /// ``shape``.
    let root: Entity
    /// The cable, in world coordinates under the graph's root: one swept
    /// tube, remade whenever the run moves (see
    /// ``place(face:ghost:near:crossFade:)``).
    let cable: ModelEntity
    /// The returning pulse, in world coordinates under the graph's root.
    let pulse: ModelEntity

    private let chassis: Chassis
    private let palette: StagePalette
    private let inkMaterial: UnlitMaterial
    private let ringScale: Double
    private(set) var layout: StageHandoffLayout?
    /// The cable's polyline, near end first (§S8's pulse runs it backwards).
    private(set) var path: [SIMD3<Double>] = []
    private var placedNear: SIMD3<Double>?
    /// What was last written, so a settled ghost costs nothing per frame.
    private(set) var opacity: Float = 0
    private var slide = -1.0

    /// What the ghost draws now, a child of ``root`` turned by the layout's
    /// ``StageHandoffLayout/ghostYaw``: the box and its port, or a chosen
    /// chassis with the far port's ring on it. Built on the first placement.
    private var shape: Entity?
    /// The box's port, which follows the near port's height. `nil` on a
    /// chosen chassis, whose port is where its catalogue puts it.
    private var boxPort: Entity?
    /// The shape a new pick replaced, fading out where it stood, and how far
    /// the cross-fade has run, 0…1.
    private var outgoing: Entity?
    private var crossFade = 1.0
    /// The opacity `outgoing` fades out from: full for a settled shape, less
    /// when a pick landed mid-fade (``StageMath/crossFadeHandover(progress:outgoingFrom:fading:)``).
    private var outgoingFrom = 1.0

    init(chassis: Chassis, palette: StagePalette, appearance: StageAppearance) {
        self.chassis = chassis
        self.palette = palette
        inkMaterial = palette.inkMaterial
        ringScale = appearance.ringScale

        root = Entity()
        root.name = "ghost"
        root.components.set(OpacityComponent(opacity: 0))
        root.isEnabled = false

        cable = ModelEntity()
        cable.name = "ghost.cable"
        cable.components.set(OpacityComponent(opacity: 0))
        cable.isEnabled = false

        pulse = ModelEntity(
            mesh: .generateSphere(radius: StageMesh.metres(Self.pulseRadius)),
            materials: [palette.accentMaterial]
        )
        pulse.name = "ghost.pulse"
        pulse.components.set(OpacityComponent(opacity: 0))
        pulse.isEnabled = false
    }

    /// Puts the ghost on the trailing side of `face`, drawn as `ghost` — a
    /// chassis family, or `nil` for the box — and runs the cable from `near`,
    /// a receptacle's anchor in centimetres, to the ghost's port. With no near
    /// port there is a ghost and no cable. Idempotent.
    ///
    /// - Parameter crossFade: a new `ghost` fades in over the shape it
    ///   replaces, which fades out where it stood. `false` puts it there at
    ///   once: under Reduce Motion, and whenever there is nothing on stage yet
    ///   to fade from.
    func place(face: PortFace, ghost: Archetype?, near: SIMD3<Double>?, crossFade fades: Bool) {
        let chosen = ghost.flatMap(ReceptacleCatalogue.chassis(for:))
        let layout = StageHandoffLayout(face: face, chassis: chassis, ghost: chosen)
        guard shape == nil || layout != self.layout || near != placedNear else { return }
        let previous = self.layout
        self.layout = layout
        placedNear = near

        if shape == nil || previous?.ghost != layout.ghost {
            replaceShape(
                with: chosen, fades: fades,
                // The shape going out stays where it stood while the ghost's
                // centre moves to where the new one stands.
                offset: (previous?.centre ?? layout.centre) - layout.centre
            )
        }
        shape?.orientation = simd_quatf(angle: Float(layout.ghostYaw), axis: SIMD3(0, 1, 0))

        let far = layout.farPort(
            nearHeight: near?.y ?? chassis.baseBand + 0.45 * (chassis.height - chassis.baseBand)
        )
        if let boxPort {
            // The box is not turned, so its own frame is the layout's.
            let local = far - layout.centre
            boxPort.position = SIMD3(
                StageMesh.metres(local.x), StageMesh.metres(local.y), StageMesh.metres(local.z)
            )
            boxPort.orientation = simd_quatf(
                angle: Float(StageSceneBuilder.yaw(for: face)), axis: SIMD3(0, 1, 0)
            )
        }

        path = near.map { StageMath.handoffCable(from: $0, to: far, normal: layout.normal) } ?? []
        // §S8 draws "a single thin connecting line", so the whole run — out
        // of the near face, across the daylight, into the ghost's port — is
        // one mesh swept along `path` by ``StageMesh/tube(along:radius:name:)``.
        // A cylinder per leg was a chain: each one ended in a flat cap, so
        // both turns read as joints, which is a linkage between the two Macs
        // rather than the single line the spec asks for. `path` is untouched,
        // so the returning pulse still walks the same polyline. A new pick
        // moves the line to the new far port with it.
        cable.model = StageMesh.tube(
            along: path, radius: Self.cableRadius, name: "ghost.cable"
        )
        .map { ModelComponent(mesh: $0, materials: [inkMaterial]) }
        // A re-aim mid-handoff lands where the previous placement was.
        slide = -1
    }

    /// Draws the ghost `slide` of the way out (1 = fully out, 0 = at rest) at
    /// `opacity`, and the cable with it.
    func show(slide: Double, opacity: Float) {
        guard let layout else { return }
        if slide != self.slide {
            self.slide = slide
            let position = layout.centre + layout.right * (StageMath.handoffSlide * slide)
            root.position = SIMD3(
                StageMesh.metres(position.x), StageMesh.metres(position.y),
                StageMesh.metres(position.z)
            )
        }
        guard opacity != self.opacity else { return }
        self.opacity = opacity
        let visible = opacity > 0.001
        if root.isEnabled != visible { root.isEnabled = visible }
        let cableVisible = visible && !path.isEmpty
        if cable.isEnabled != cableVisible { cable.isEnabled = cableVisible }
        guard visible else { return }
        root.components.set(OpacityComponent(opacity: opacity))
        cable.components.set(
            OpacityComponent(opacity: opacity / Self.restingOpacity * Self.cableOpacity)
        )
    }

    /// Runs a new pick's cross-fade on by `deltaTime`. Nothing to do once it
    /// has run, so a settled ghost costs nothing per frame.
    func advanceCrossFade(by deltaTime: TimeInterval) {
        guard crossFade < 1 else { return }
        crossFade = min(1, crossFade + deltaTime / Self.crossFadeDuration)
        applyCrossFade()
    }

    /// The returning pulse at `t` along the cable — 0 at the ghost, 1 at the
    /// near port — or nowhere.
    func showPulse(at t: Double?) {
        guard let t, !path.isEmpty else {
            if pulse.isEnabled { pulse.isEnabled = false }
            return
        }
        let point = StageMath.cablePoint(path, at: t)
        pulse.position = SIMD3(
            StageMesh.metres(point.x), StageMesh.metres(point.y), StageMesh.metres(point.z)
        )
        if !pulse.isEnabled {
            pulse.isEnabled = true
            pulse.components.set(OpacityComponent(opacity: 0.9))
        }
    }

    // MARK: - The shapes

    /// Swaps what the ghost draws. `offset` is where the old shape stood
    /// relative to the new centre, in centimetres.
    private func replaceShape(with chosen: Chassis?, fades: Bool, offset: SIMD3<Double>) {
        // A pick that lands mid-fade keeps whichever of the two shapes is
        // showing more, at the opacity it has now, and lets the other go, so
        // running through several picks never snaps one back to full.
        let handover = StageMath.crossFadeHandover(
            progress: crossFade, outgoingFrom: outgoingFrom,
            fading: crossFade < 1 && outgoing != nil)
        let leaving = handover.keepsOutgoing ? outgoing : shape
        (handover.keepsOutgoing ? shape : outgoing)?.removeFromParent()
        outgoing = nil
        if let leaving {
            if fades {
                // It stays where it stood while the ghost's centre moves.
                leaving.position += SIMD3(
                    StageMesh.metres(offset.x), StageMesh.metres(offset.y),
                    StageMesh.metres(offset.z)
                )
                outgoing = leaving
                outgoingFrom = handover.from
            } else {
                leaving.removeFromParent()
            }
        }
        boxPort = nil
        let new = chosen.map(makeChassis) ?? makeBox()
        root.addChild(new)
        shape = new
        crossFade = outgoing == nil ? 1 : 0
        applyCrossFade()
    }

    private func applyCrossFade() {
        guard crossFade < 1, let outgoing else {
            outgoing?.removeFromParent()
            outgoing = nil
            shape?.components.remove(OpacityComponent.self)
            return
        }
        let shown = Float(StageMath.easeInOut(crossFade))
        shape?.components.set(OpacityComponent(opacity: shown))
        outgoing.components.set(OpacityComponent(opacity: Float(outgoingFrom) * (1 - shown)))
    }

    /// **Any Mac**: a rounded box and nothing else but the far port.
    private func makeBox() -> Entity {
        let shape = Entity()
        shape.name = "ghost.box"
        if let mesh = try? StageMesh.prism(
            width: chassis.width, height: chassis.depth,
            cornerRadius: chassis.cornerRadius,
            depth: StageHandoffLayout.boxHeight(for: chassis), bevel: chassis.bevel
        ) {
            let shell = ModelEntity(mesh: mesh, materials: [palette.chassisMaterial])
            shell.orientation = StageMesh.standing
            shape.addChild(shell)
        }
        let opening = FeatureKind.thunderbolt.opening
        let port = makeFarPort(
            opening: chassis.hasVerticalReceptacles ? opening.rotated : opening, cutsHole: true
        )
        shape.addChild(port)
        boxPort = port
        return shape
    }

    /// A family the user picked: its chassis, holes and all, and the far
    /// port's ring around the receptacle ``Chassis/ghostPort`` names. The hole
    /// itself is the chassis's own.
    private func makeChassis(_ ghost: Chassis) -> Entity {
        let shape = StageSceneBuilder.ghostBody(ghost, palette: palette)
        if let feature = ghost.ghostPort {
            let port = makeFarPort(opening: feature.opening, cutsHole: false)
            let anchor = StageSceneBuilder.placeInCentimetres(
                face: feature.face, u: feature.u, v: feature.v, chassis: ghost
            )
            port.position = SIMD3(
                StageMesh.metres(anchor.x), StageMesh.metres(anchor.y), StageMesh.metres(anchor.z)
            )
            port.orientation = simd_quatf(
                angle: Float(StageSceneBuilder.yaw(for: feature.face)), axis: SIMD3(0, 1, 0)
            )
            shape.addChild(port)
        }
        return shape
    }

    /// The far port: a thin hollow ring in ink, never accent, never an inner
    /// ring — nothing is linked and nothing is lit — around a hole the box
    /// has to cut for itself.
    private func makeFarPort(opening size: FeatureKind.Opening, cutsHole: Bool) -> Entity {
        let port = Entity()
        port.name = "ghost.port"
        if cutsHole, let mesh = try? StageMesh.prism(
            width: size.width, height: size.height, cornerRadius: size.cornerRadius, depth: 0.22
        ) {
            let recess = ModelEntity(mesh: mesh, materials: [palette.recessMaterial])
            recess.position.z = StageMesh.metres(0.01)
            port.addChild(recess)
        }
        if let mesh = try? StageMesh.ring(
            width: size.width + 0.5, height: size.height + 0.5,
            cornerRadius: size.cornerRadius + 0.25, thickness: 0.07 * ringScale,
            pattern: .solid
        ) {
            let ring = ModelEntity(mesh: mesh, materials: [inkMaterial])
            ring.position.z = StageMesh.metres(0.10)
            ring.components.set(OpacityComponent(opacity: 0.55))
            port.addChild(ring)
        }
        return port
    }
}
