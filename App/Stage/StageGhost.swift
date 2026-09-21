//
//  StageGhost.swift
//
//  UX_SPEC §S8's ghost second Mac: "A featureless rounded box at 40 % opacity
//  slides in from the trailing side with a single thin connecting line between
//  the two. The near port carries its solid accent ring; the far port is
//  hollow and unlit. Nothing is written on either box, and the ghost never
//  gains detail, ever — it is explicitly *a Mac I can't see*. When the far end
//  answers on the link, a returning pulse travels back along the line and
//  blooms at the near receptacle, once."
//
//  The box is this Mac's own footprint with nothing on it, because the app
//  knows nothing about the other machine and a shape that claimed to would be
//  a lie (§1.3). It is built once with the graph, disabled at opacity 0, and
//  `StageScene` places it for the face the handoff is staged on and slides it
//  in; `StageScene.settle` puts it straight at its resting place for the
//  review hook's off-screen render.
//

import Foundation
import RealityKit
import RDMALinkCore
import simd

/// Where the ghost and its cable go for a handoff staged on one face, in the
/// chassis's own centimetres. Pure over the chassis, so the camera's framing
/// and the ghost's placement are one calculation. On the main actor only
/// because the face-to-yaw table it reads is the scene builder's.
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
    /// The ghost box's extent along `right` and along `normal`.
    let extentAlongRight: Double
    let extentAlongNormal: Double

    init(face: PortFace, chassis: Chassis) {
        let yaw = StageSceneBuilder.yaw(for: face)
        self.face = face
        right = StageMath.screenRight(yaw: yaw)
        normal = StageMath.outwardNormal(yaw: yaw)
        let alongFace = face == .back || face == .front
        extentAlongRight = alongFace ? chassis.width : chassis.depth
        extentAlongNormal = alongFace ? chassis.depth : chassis.width
        across = (chassis.width * chassis.width + chassis.depth * chassis.depth).squareRoot()
        gap = StageMath.handoffGap(extentAlongRight: extentAlongRight, across: across)
    }

    /// The ghost's centre on the ground plane.
    var centre: SIMD3<Double> { right * gap }

    /// Half way between the two Macs, on the ground plane: where the camera
    /// looks so that this Mac takes the leading third and the ghost the rest.
    var midpoint: SIMD3<Double> { right * (gap / 2) }

    /// The pair's silhouette, centre to centre plus both ends, for framing.
    var framingWidth: Double { gap + across }

    /// The ghost's port sits low on the ghost's near edge, so the cable is
    /// short and the two ports face the same way.
    static let portInset = 2.2

    /// The hollow port on the ghost, in world centimetres, at `height`.
    func farPort(height: Double) -> SIMD3<Double> {
        centre - right * (extentAlongRight / 2 - Self.portInset)
            + normal * (extentAlongNormal / 2) + SIMD3(0, height, 0)
    }
}

/// The ghost, its hollow port, the cable and the returning pulse.
@MainActor
final class StageGhostNode {
    /// §S8: "at 40 % opacity".
    static let restingOpacity: Float = 0.4
    /// The cable is a line, not a ribbon: thinner than a ring track and
    /// quieter than the ghost it joins. Constant over the whole run — §S8
    /// asks for "a single thin connecting line", and a line that thinned
    /// towards one end would say which Mac it belongs to.
    private static let cableRadius = 0.045
    private static let cableOpacity: Float = 0.6
    private static let pulseRadius = 0.16

    /// The box, a child of the graph's root. Its position is the ghost's
    /// resting place plus however much of the slide is left.
    let root: Entity
    /// The hollow, unlit far port, a child of ``root``.
    private let port: Entity
    /// The cable, in world coordinates under the graph's root: one swept
    /// tube, remade whenever the run moves (see ``place(face:near:)``).
    let cable: ModelEntity
    /// The returning pulse, in world coordinates under the graph's root.
    let pulse: ModelEntity

    private let chassis: Chassis
    private let inkMaterial: UnlitMaterial
    private(set) var layout: StageHandoffLayout?
    /// The cable's polyline, near end first (§S8's pulse runs it backwards).
    private(set) var path: [SIMD3<Double>] = []
    private var placedNear: SIMD3<Double>?
    /// What was last written, so a settled ghost costs nothing per frame.
    private(set) var opacity: Float = 0
    private var slide = -1.0

    init(chassis: Chassis, palette: StagePalette, appearance: StageAppearance) {
        self.chassis = chassis
        inkMaterial = palette.inkMaterial

        root = Entity()
        root.name = "ghost"
        root.components.set(OpacityComponent(opacity: 0))
        root.isEnabled = false

        // A rounded box and nothing else. A notebook's base is a plate, and a
        // plate is not the "rounded box" §S8 draws, so the ghost of one is
        // given a box's height; every other chassis lends its own.
        let height = chassis.isNotebook ? 5.0 : chassis.height
        if let mesh = try? StageMesh.prism(
            width: chassis.width, height: chassis.depth,
            cornerRadius: chassis.cornerRadius, depth: height, bevel: chassis.bevel
        ) {
            let shell = ModelEntity(mesh: mesh, materials: [palette.chassisMaterial])
            shell.orientation = StageMesh.standing
            root.addChild(shell)
        }

        // The far port: a hole and a thin hollow ring in ink, never accent,
        // never an inner ring — nothing is linked and nothing is lit.
        port = Entity()
        let opening = FeatureKind.thunderbolt.opening
        let size = chassis.hasVerticalReceptacles ? opening.rotated : opening
        if let mesh = try? StageMesh.prism(
            width: size.width, height: size.height, cornerRadius: size.cornerRadius, depth: 0.22
        ) {
            let recess = ModelEntity(mesh: mesh, materials: [palette.recessMaterial])
            recess.position.z = StageMesh.metres(0.01)
            port.addChild(recess)
        }
        if let mesh = try? StageMesh.ring(
            width: size.width + 0.5, height: size.height + 0.5,
            cornerRadius: size.cornerRadius + 0.25, thickness: 0.07 * appearance.ringScale,
            pattern: .solid
        ) {
            let ring = ModelEntity(mesh: mesh, materials: [palette.inkMaterial])
            ring.position.z = StageMesh.metres(0.10)
            ring.components.set(OpacityComponent(opacity: 0.55))
            port.addChild(ring)
        }
        root.addChild(port)

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

    /// Puts the ghost on the trailing side of `face` and runs the cable from
    /// `near` — a receptacle's anchor, in centimetres — to the ghost's port.
    /// With no near port there is a ghost and no cable. Idempotent.
    func place(face: PortFace, near: SIMD3<Double>?) {
        let layout = StageHandoffLayout(face: face, chassis: chassis)
        guard layout != self.layout || near != placedNear else { return }
        self.layout = layout
        placedNear = near

        let height = near?.y ?? chassis.baseBand + 0.45 * (chassis.height - chassis.baseBand)
        let far = layout.farPort(height: height)
        let local = far - layout.centre
        port.position = SIMD3(
            StageMesh.metres(local.x), StageMesh.metres(local.y), StageMesh.metres(local.z)
        )
        port.orientation = simd_quatf(
            angle: Float(StageSceneBuilder.yaw(for: face)), axis: SIMD3(0, 1, 0)
        )

        path = near.map { StageMath.handoffCable(from: $0, to: far, normal: layout.normal) } ?? []
        // §S8 draws "a single thin connecting line", so the whole run — out
        // of the near face, across the daylight, into the ghost's port — is
        // one mesh swept along `path` by ``StageMesh/tube(along:radius:name:)``.
        // A cylinder per leg was a chain: each one ended in a flat cap, so
        // both turns read as joints, which is a linkage between the two Macs
        // rather than the single line the spec asks for. `path` is untouched,
        // so the returning pulse still walks the same polyline.
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
}
