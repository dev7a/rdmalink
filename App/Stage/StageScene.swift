//
//  StageScene.swift
//
//  The live half of the stage: the camera rig, the cross-fades, the breath,
//  and the waking-ports beat. It owns no copy of the truth — every frame it
//  reads `StageModel` and moves entities to match.
//

import AppKit
import Foundation
import RealityKit
import RDMALinkCore
import SwiftUI
import simd

@MainActor
final class StageScene {
    /// UX_SPEC §3.4: a 35 mm-equivalent perspective camera. On a 36 × 24 mm
    /// frame that is a 37.85° vertical field of view.
    static let verticalFieldOfView = 2 * atan(12.0 / 35.0)

    /// §3.5: camera moves are 0.7 s; §8.6 replaces them with a 100 ms
    /// cross-fade between the same poses under Reduce Motion.
    private static let arcDuration = 0.7
    private static let reducedArcDuration = 0.1
    /// §3.5: rings, ribbons and glows cross-fade in 150 ms.
    private static let crossFade = 0.15
    /// §3.5 and §4.2: the link-coming-up breath, 8 → 18 % on a 1.6 s cycle.
    private static let breathPeriod = 1.6

    private(set) var graph: StageSceneGraph?
    let camera = PerspectiveCamera()

    /// Set by the view so hit tests and projections can be answered.
    var content: RealityViewCameraContent?

    /// The per-frame subscription. It dies the moment nothing holds it.
    var subscription: EventSubscription?

    /// What the installed entities were built from. It lives here rather than
    /// in `@State` so a rebuild decided inside `RealityView`'s update closure
    /// never writes SwiftUI state while SwiftUI is updating.
    var installedKey: StageBuildKey?

    var viewport = CGSize(width: 580, height: 600)
    /// Where the stage sits in the window, for the review hook alone.
    var frameInWindow: CGRect = .zero
    var appearance = StageAppearance()
    /// Told to the model when a drag or an arc brings a new face to the front.
    var onFaceChanged: ((PortFace) -> Void)?

    private var yaw = Double.pi - 0.55
    private var pitch = 0.30
    private var radius = 0.5
    private var target = SIMD3<Float>(0, 0, 0)
    private var arc: Arc?
    private var elapsed = 0.0
    private var reportedFace: PortFace?

    private var wakeStart: Double?
    private var handledWakeToken = -1
    /// §8.3's keyboard focus halo, and what the review hook renders with.
    private(set) var focusedID: StagePort.ID?

    private struct Arc {
        var yaw: Double, deltaYaw: Double
        var pitch: Double, deltaPitch: Double
        var radius: Double, deltaRadius: Double
        var elapsed = 0.0
        var duration: Double
        var bumps: Bool
    }

    init() {
        camera.components.set(
            PerspectiveCameraComponent(
                near: 0.01, far: 12,
                fieldOfViewInDegrees: Float(Self.verticalFieldOfView * 180 / .pi),
                fieldOfViewOrientation: .vertical
            )
        )
    }

    // MARK: - Building

    /// - Parameter keepingPose: true when only the appearance changed, so the
    ///   graph is new but the machine is not. Crossing sunset, or switching
    ///   Increase Contrast on, must not take a user who has orbited to inspect
    ///   `Back, far right` and put the camera back where it started.
    func install(
        _ graph: StageSceneGraph, into content: inout RealityViewCameraContent,
        keepingPose: Bool
    ) {
        content.entities.removeAll()
        let hadGraph = self.graph != nil
        self.graph = graph
        content.entities.append(graph.root)
        content.entities.append(camera)
        target = SIMD3(0, StageMesh.metres(graph.chassis.focus), 0)
        if keepingPose, hadGraph {
            // The pose survives; only the dolly limits are re-derived, because
            // a new chassis could have moved them.
            radius = StageMath.clamp(radius, dollyRange)
        } else {
            yaw = graph.chassis.resting.yaw
            pitch = StageMath.clampPitch(graph.chassis.resting.pitch)
            radius = StageMath.clamp(restingRadius, dollyRange)
            arc = nil
            // `reportedFace` is left nil so the first frame — not this view
            // update — is what tells the model which face is in front.
            reportedFace = nil
        }
        // The waking-ports beat is not replayed by a rebuild: switching to
        // dark mode is not a new launch (§9.2). `StageModel.wake()` is the one
        // thing that runs it, and the window calls that when the probe
        // finishes.
        place()
    }

    /// Re-derives the framing after the stage has changed size.
    ///
    /// `fitDistance` and `dollyRange` both read `viewport`, so a camera framed
    /// against the placeholder size is wrong in every window that is not that
    /// size — badly so in §8.5's 180 pt strip. A camera still sitting at the
    /// old fit distance is re-fitted; one the user has dollied is only
    /// re-clamped, because their zoom is theirs.
    func reframe(previousViewport: CGSize) {
        guard graph != nil, viewport.width > 1, viewport.height > 1 else { return }
        let wasFramed = abs(radius - restingRadius(in: previousViewport)) < 1e-6
        radius = StageMath.clamp(wasFramed ? restingRadius : radius, dollyRange)
        place()
    }

    // MARK: - Framing

    /// The distance that frames the whole machine.
    ///
    /// The width used is the footprint's circumcircle, not one face's width.
    /// At the three-quarter resting pose a 19.7 × 19.7 cm box has a 27.1 cm
    /// silhouette, so framing the 19.7 cm face puts the two near corners off
    /// the sides of the stage — measured, not reasoned: at the face-framed
    /// distance the Mac Studio is cut off on the left and the bottom in a
    /// default 1000 × 660 window. A circle also does not change as the user
    /// orbits, so the framing never pumps mid-drag.
    var fitDistance: Double { fitDistance(in: viewport) }

    func fitDistance(in viewport: CGSize) -> Double {
        guard let graph else { return 0.5 }
        return StageMath.fitDistance(
            framing(graph.chassis), viewport: viewport,
            verticalFieldOfView: Self.verticalFieldOfView
        )
    }

    /// §3.4's 1.4× dolly range, with §8.4's 24 × 24 pt hit target enforced at
    /// its far end.
    ///
    /// The receptacle proxy is 1.6 cm across — well past the 0.985 cm gap
    /// between two receptacles on a Mac Studio's back row, which is what makes
    /// the floor reachable at all. The proxies therefore overlap, and
    /// ``portID(at:)`` picks the nearest projected centre, so the real target
    /// is the cell around each receptacle and is never narrower than the pitch.
    ///
    /// With that proxy, a 35 mm-equivalent camera (37.85° vertical) and
    /// `margin: 1.06`, every desktop holds the floor at the resting pose with
    /// the whole machine still in frame:
    ///
    /// | chassis | stage | fit | dolly range | rest | pt | crop |
    /// |---|---|---|---|---|---|---|
    /// | Mac Studio | 580 × 600 | 0.446 | 0.321–0.583 | 0.446 | 31.4 | — |
    /// | Mac Studio | 460 × 500 | 0.468 | 0.337–0.486 | 0.468 | 24.9 | — |
    /// | Mac Studio | 900 × 180 | 0.147 | 0.106–0.175 | 0.147 | 28.6 | — |
    /// | Mac mini | 580 × 600 | 0.287 | 0.207–0.402 | 0.287 | 48.7 | — |
    /// | MacBook | 580 × 600 | 0.612 | 0.441–0.583 | 0.583 | 24.0 | 1.05× |
    /// | MacBook | 460 × 500 | 0.643 | 0.463–0.486 | 0.486 | 24.0 | 1.32× |
    /// | MacBook | 900 × 180 | 0.354 | 0.175–0.175 | 0.175 | 24.0 | 2.02× |
    ///
    /// **The one place the two rules still disagree is a notebook in a small
    /// stage.** A 38 cm machine with a 1.6 cm target cannot be shown whole and
    /// leave 24 pt across a receptacle in a 460 pt window, and §8.5's 180 pt
    /// strip is worse. §8.4 is an accessibility floor and §3.4's framing is a
    /// picture, so the floor wins and the resting pose crops; the port list is
    /// the complete path either way (§8.1). ``receptaclePointSize`` reports the
    /// number actually achieved, and `script/test_stage_math.sh` asserts this
    /// whole table through the same `StageMath` functions.
    var dollyRange: (minimum: Double, maximum: Double) { dollyRange(in: viewport) }

    func dollyRange(in viewport: CGSize) -> (minimum: Double, maximum: Double) {
        guard let graph else { return (0.4, 0.6) }
        let limits = StageMath.dollyRange(
            framing(graph.chassis), viewport: viewport,
            verticalFieldOfView: Self.verticalFieldOfView
        )
        // `StageMath` collapses the far end onto the near one rather than
        // inverting; a range with no room at all would lock the wheel.
        return (minimum: min(limits.minimum, limits.maximum), maximum: limits.maximum)
    }

    /// Where the camera opens: the chassis's own resting distance, clamped.
    var restingRadius: Double { restingRadius(in: viewport) }

    func restingRadius(in viewport: CGSize) -> Double {
        guard let graph else { return radius }
        return StageMath.clamp(
            fitDistance(in: viewport) * graph.chassis.resting.radiusScale,
            dollyRange(in: viewport)
        )
    }

    /// How many points across a receptacle's collider reads right now.
    ///
    /// This is the honest reporter for the §8.4 trade-off above, and
    /// `script/test_stage_math.sh` asserts the table's numbers through the
    /// same `StageMath` functions this computes from.
    var receptaclePointSize: Double {
        guard let graph else { return 0 }
        return StageMath.receptaclePointSize(
            framing(graph.chassis), distance: radius, viewport: viewport,
            verticalFieldOfView: Self.verticalFieldOfView
        )
    }

    /// Everything the framing depends on, in metres.
    private func framing(_ chassis: Chassis) -> StageMath.Framing {
        let proxy = ChassisFeature.colliderSize(
            of: .thunderbolt, vertical: chassis.hasVerticalReceptacles
        )
        return StageMath.Framing(
            across: (chassis.width * chassis.width + chassis.depth * chassis.depth)
                .squareRoot() * 0.01,
            height: chassis.visibleHeight * 0.01,
            proxy: CGSize(width: proxy.width * 0.01, height: proxy.height * 0.01)
        )
    }

    /// The rig, as a value — read by the review hook so its off-screen frame
    /// is the frame that is on screen.
    var pose: StageCameraPose {
        StageCameraPose(yaw: yaw, pitch: pitch, radius: radius, target: target)
    }

    var faceForCurrentYaw: PortFace {
        let order: [PortFace] = [.front, .right, .back, .left]
        return order[StageMath.faceIndex(forYaw: yaw)]
    }

    // MARK: - Camera intents

    func perform(_ request: StageCameraRequest) {
        switch request.kind {
        case .turn(let face): turn(to: face)
        case .fit: animate(yaw: yaw, pitch: pitch, radius: fitDistance, bumps: false)
        case .reset: reset()
        }
    }

    /// §3.5: a spherical arc with a simultaneous 4 % dolly-out and back.
    private func turn(to face: PortFace) {
        // The three-quarter offset keeps the top edge readable rather than
        // flattening the machine into an elevation drawing.
        let destination = StageSceneBuilder.yaw(for: face) - 0.55
        animate(
            yaw: yaw + StageMath.shortestAngleDelta(from: yaw, to: destination),
            pitch: pitch, radius: StageMath.clamp(radius, dollyRange), bumps: true
        )
    }

    private func reset() {
        guard let graph else { return }
        let resting = graph.chassis.resting
        let destination = StageMath.clamp(
            fitDistance * resting.radiusScale, dollyRange
        )
        animate(
            yaw: yaw + StageMath.shortestAngleDelta(from: yaw, to: resting.yaw),
            pitch: StageMath.clampPitch(resting.pitch), radius: destination, bumps: true
        )
    }

    private func animate(yaw destination: Double, pitch: Double, radius: Double, bumps: Bool) {
        arc = Arc(
            yaw: self.yaw, deltaYaw: destination - self.yaw,
            pitch: self.pitch, deltaPitch: pitch - self.pitch,
            radius: self.radius, deltaRadius: radius - self.radius,
            duration: appearance.reduceMotion ? Self.reducedArcDuration : Self.arcDuration,
            bumps: bumps && !appearance.reduceMotion
        )
    }

    /// Free yaw, pitch clamped to ±35°, roll locked — the rig has no roll to
    /// lock, which is the point of driving it in spherical coordinates.
    func orbit(deltaX: Double, deltaY: Double) {
        arc = nil
        yaw -= deltaX * 0.008
        pitch = StageMath.clampPitch(pitch + deltaY * 0.006)
        place()
        reportFaceIfChanged()
    }

    func dolly(by scroll: Double) {
        arc = nil
        radius = StageMath.clamp(radius * (1 + scroll * 0.0015), dollyRange)
        place()
    }

    func setFocus(_ id: StagePort.ID?) { focusedID = id }

    // MARK: - Scroll-wheel dolly

    /// SwiftUI has no scroll-wheel modifier for a plain view, so the wheel is
    /// read from a local event monitor gated on the pointer actually being
    /// over the stage. Nothing else in the window can lose a scroll to it.
    var isPointerInside = false

    private var scrollMonitor: Any?

    func startScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let delta = event.scrollingDeltaY
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard self.isPointerInside else { return false }
                self.dolly(by: -Double(delta))
                return true
            }
            return consumed ? nil : event
        }
    }

    func stopScrollMonitor() {
        guard let scrollMonitor else { return }
        NSEvent.removeMonitor(scrollMonitor)
        self.scrollMonitor = nil
    }

    // MARK: - Hit testing

    /// The port under a point in the view's own coordinate space, or nil.
    ///
    /// §8.4's 24 pt floor needs a collider wider than the 0.985 cm gap between
    /// two receptacles on a Mac Studio's back row, so the proxies overlap and a
    /// hit test can answer with several. The nearest projected centre is the
    /// one the pointer meant: the effective target becomes the cell around each
    /// receptacle, which has no dead band in it anywhere.
    func portID(at point: CGPoint) -> StagePort.ID? {
        guard let content else { return nil }
        var best: (id: StagePort.ID, distance: Double)?
        for entity in content.entities(at: point, in: .local) {
            guard let id = identity(of: entity) else { continue }
            let projected = content.project(point: entity.position(relativeTo: nil), to: .local)
            let distance = projected.map {
                Double(hypot($0.x - point.x, $0.y - point.y))
            } ?? Double.infinity
            if let current = best, current.distance <= distance { continue }
            best = (id, distance)
        }
        return best?.id
    }

    func portID(of entity: Entity) -> StagePort.ID? { identity(of: entity) }

    private func identity(of entity: Entity) -> StagePort.ID? {
        var current: Entity? = entity
        while let node = current {
            if let identity = node.components[StagePortIdentity.self] { return identity.id }
            current = node.parent
        }
        return nil
    }

    // MARK: - Per-frame

    func update(deltaTime: TimeInterval, model: StageModel) {
        elapsed += deltaTime
        step(arc: deltaTime)
        apply(model: model, deltaTime: deltaTime)
        place()
        reportFaceIfChanged()
    }

    private func step(arc deltaTime: TimeInterval) {
        guard var current = arc else { return }
        current.elapsed += deltaTime
        let t = min(current.elapsed / current.duration, 1)
        let eased = appearance.reduceMotion ? t : StageMath.easeInOut(t)
        yaw = current.yaw + current.deltaYaw * eased
        pitch = StageMath.clampPitch(current.pitch + current.deltaPitch * eased)
        radius = current.radius + current.deltaRadius * eased
            + (current.bumps ? StageMath.dollyBump(t, radius: current.radius) : 0)
        arc = t >= 1 ? nil : current
    }

    private func place() {
        let position = StageMath.orbitPosition(
            target: target, yaw: yaw, pitch: pitch, radius: radius
        )
        camera.look(at: target, from: position, relativeTo: nil)
    }

    private func reportFaceIfChanged() {
        let face = faceForCurrentYaw
        guard face != reportedFace else { return }
        reportedFace = face
        onFaceChanged?(face)
    }

    // MARK: - State

    private func apply(model: StageModel, deltaTime: TimeInterval) {
        guard let graph else { return }

        if model.wakeToken != handledWakeToken {
            handledWakeToken = model.wakeToken
            wakeStart = elapsed
        }

        let breath = appearance.reduceMotion
            ? Self.restingBreath
            : 0.08 + 0.10 * (0.5 + 0.5 * sin(elapsed / Self.breathPeriod * 2 * .pi))

        for node in graph.receptacles {
            guard let port = model.ports.first(where: { $0.id == node.id }) else { continue }
            Self.setStub(node, to: port.link != .empty)
            guard node.isThunderbolt else {
                // §4.5: a USB-only receptacle never takes a ring and never
                // takes a hover glow; it dims 15 % and that is the whole
                // answer the model gives.
                let dim: Float = port.hovered ? 0.85 : 1
                if node.dim != dim {
                    node.dim = dim
                    node.root.components.set(OpacityComponent(opacity: dim))
                }
                continue
            }

            let awake = isAwake(index: port.physicalIndex)
            for role in StageRingRole.allCases {
                let target = awake
                    ? Self.targetOpacity(
                        role, port: port, breath: Float(breath),
                        focused: port.id == focusedID
                    )
                    : 0
                fade(node: node, role: role, to: target, deltaTime: deltaTime)
            }
        }
    }

    /// §4.2's breath at the middle of its cycle. Also what Reduce Motion
    /// freezes it at, and what a still frame should show.
    private static let restingBreath = 0.13

    private static func setStub(_ node: StageReceptacleNode, to enabled: Bool) {
        guard node.stub.isEnabled != enabled else { return }
        node.stub.isEnabled = enabled
    }

    /// Puts a freshly built graph into the state ``apply(model:deltaTime:)``
    /// would settle it in, with no cross-fade left to run and the wake beat
    /// already over.
    ///
    /// Entities belong to exactly one scene, so the review hook renders its own
    /// graph (see App/Stage/StageSnapshot.swift) — and a graph no `StageScene`
    /// has ever ticked has every ring disabled at opacity 0, which is a picture
    /// of bare aluminium with §4.2 and §4.3 missing from it entirely.
    static func settle(_ graph: StageSceneGraph, ports: [StagePort], focused: StagePort.ID?) {
        for node in graph.receptacles {
            guard let port = ports.first(where: { $0.id == node.id }) else { continue }
            setStub(node, to: port.link != .empty)
            guard node.isThunderbolt else {
                let dim: Float = port.hovered ? 0.85 : 1
                node.dim = dim
                node.root.components.set(OpacityComponent(opacity: dim))
                continue
            }
            for role in StageRingRole.allCases {
                guard let entity = node.layers[role] else { continue }
                let target = targetOpacity(
                    role, port: port, breath: Float(restingBreath),
                    focused: port.id == focused
                )
                node.fades[role] = (target, target)
                entity.isEnabled = target > 0.001
                entity.components.set(OpacityComponent(opacity: target))
            }
        }
    }

    /// §9.2: the receptacles light in physical order with a 60 ms stagger, one
    /// readable beat, once per launch.
    private func isAwake(index: Int) -> Bool {
        guard let wakeStart else { return false }
        let delay = StageMath.wakeDelay(
            index: max(index - 1, 0), reduceMotion: appearance.reduceMotion
        )
        return elapsed - wakeStart >= Double(delay.components.attoseconds) / 1e18
            + Double(delay.components.seconds)
    }

    private static func targetOpacity(
        _ role: StageRingRole, port: StagePort, breath: Float, focused: Bool
    ) -> Float {
        switch role {
        case .inner:
            switch port.link {
            case .macLinked: 1
            case .macLinkComingUp: breath
            case .empty, .device: 0
            }
        case .thread:
            port.link == .macLinked ? 1 : 0
        case .bridge:
            port.cfg == .bridge ? 1 : 0
        case .ready:
            port.cfg == .ready ? 1 : 0
        case .outside:
            port.cfg == .outside ? 1 : 0
        case .drift:
            port.cfg == .drift ? 1 : 0
        case .attention:
            port.attention ? 1 : 0
        case .hover:
            // §4.6: hover is 45 % accent, and selection replaces it.
            port.hovered && !port.selected ? 0.45 : 0
        case .selection:
            port.selected ? 1 : 0
        case .bloom:
            port.selected ? 0.16 : (port.cfg == .ready ? 0.10 : 0)
        case .focus:
            focused ? 1 : 0
        }
    }

    private func fade(
        node: StageReceptacleNode, role: StageRingRole, to target: Float,
        deltaTime: TimeInterval
    ) {
        guard let entity = node.layers[role], var fade = node.fades[role] else { return }
        fade.target = target
        if appearance.reduceMotion || Self.crossFade <= 0 {
            fade.current = target
        } else {
            let step = Float(deltaTime / Self.crossFade)
            let delta = fade.target - fade.current
            fade.current = abs(delta) <= step ? fade.target : fade.current + step * (delta < 0 ? -1 : 1)
        }
        // A settled layer is left alone. Every `components.set` re-registers
        // the entity in the transparency pass, and a still scene with six
        // `.outside` receptacles was writing a dozen of them a frame forever.
        let settled = fade.current == fade.target && fade.current == node.fades[role]?.current
        node.fades[role] = fade
        let visible = fade.current > 0.001
        if entity.isEnabled != visible { entity.isEnabled = visible }
        guard visible, !settled else { return }
        entity.components.set(OpacityComponent(opacity: fade.current))
    }
}
