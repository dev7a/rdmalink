//
//  StageMath.swift
//
//  Every number the stage needs that is not a RealityKit call: the orbit rig,
//  the dolly limits that keep a receptacle clickable (UX_SPEC §3.4, §8.4), the
//  easing for the 0.7 s camera arc (§3.5), and the rounded-rectangle outlines
//  the ring tracks are built from (§4.1).
//
//  This file imports nothing but Foundation, CoreGraphics and simd on purpose:
//  it is the only part of the stage that can be compiled and exercised on its
//  own, by script/test_stage_math.sh.
//

import CoreGraphics
import Foundation
import simd

enum StageMath {
    // MARK: - Angles

    /// The shortest way round from `from` to `to`, in radians, in `-π...π`.
    ///
    /// A camera arc from the front to the back must not take the long way
    /// because the two yaws happen to be written 0 and `π`.
    static func shortestAngleDelta(from: Double, to: Double) -> Double {
        var delta = to - from
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        return delta
    }

    /// `angle` folded into `0..<2π`.
    static func normalizedAngle(_ angle: Double) -> Double {
        let turn = 2 * Double.pi
        return (angle.truncatingRemainder(dividingBy: turn) + turn)
            .truncatingRemainder(dividingBy: turn)
    }

    /// UX_SPEC §3.4: "Orbit constrained to ±35° elevation so the user can
    /// never end up under the machine."
    static let maximumPitch = 35.0 * .pi / 180.0

    static func clampPitch(_ pitch: Double) -> Double {
        min(max(pitch, -maximumPitch), maximumPitch)
    }

    /// Which of the four faces the camera mostly sees, as an index into
    /// `[front, right, back, left]`.
    ///
    /// Yaw is the angle of the camera around `+y` measured so that 0 looks at
    /// the front face from `+z` and `π` looks at the back from `-z`, matching
    /// `docs/prototype/stage.html`.
    static func faceIndex(forYaw yaw: Double) -> Int {
        let a = normalizedAngle(yaw)
        let quarter = Double.pi / 4
        if a < quarter || a > 7 * quarter { return 0 }
        if a < 3 * quarter { return 1 }
        if a < 5 * quarter { return 2 }
        return 3
    }

    /// UX_SPEC §S4b's watching pose: the yaw that shows something of every one
    /// of `faces`, taking whichever of the two answers the camera is already
    /// nearer to.
    ///
    /// `faces` are camera yaws — the angle that looks square on at a face. Two
    /// opposite faces average to nothing at all, which is the case the
    /// perpendicular covers: the pose between a front and a back is a side, and
    /// from a side both of them are edge-on and visible.
    static func surveyYaw(facing faces: [Double], from current: Double) -> Double {
        guard let first = faces.first else { return current }
        guard faces.count > 1 else { return first }
        var sum = SIMD2<Double>(0, 0)
        for yaw in faces { sum += SIMD2(sin(yaw), cos(yaw)) }
        if simd_length(sum) > 0.2 { return atan2(sum.x, sum.y) }
        let left = first + .pi / 2, right = first - .pi / 2
        return abs(shortestAngleDelta(from: current, to: left))
            <= abs(shortestAngleDelta(from: current, to: right)) ? left : right
    }

    // MARK: - Orbit

    /// The camera position for a spherical rig around `target`.
    static func orbitPosition(
        target: SIMD3<Float>, yaw: Double, pitch: Double, radius: Double
    ) -> SIMD3<Float> {
        let cosPitch = cos(pitch)
        return SIMD3<Float>(
            target.x + Float(radius * sin(yaw) * cosPitch),
            target.y + Float(radius * sin(pitch)),
            target.z + Float(radius * cos(yaw) * cosPitch)
        )
    }

    // MARK: - Projection

    /// Where a world point lands in a viewport, for the same rig
    /// ``orbitPosition(target:yaw:pitch:radius:)`` places the camera on: a
    /// look-at from `camera` to `target` with `+y` up, and a perspective of
    /// `verticalFieldOfView` over `viewport` points, top-left origin.
    ///
    /// UX_SPEC §4.8's two overlays are laid out from this — the legend yields
    /// to the projected chassis and the callout sits beside the projected
    /// receptacle — so it is computed here, from the pose the stage is
    /// holding, rather than asked of the renderer. Nil for a point behind the
    /// camera or on its plane, which nothing on stage should ever be.
    static func project(
        _ point: SIMD3<Float>, camera: SIMD3<Float>, target: SIMD3<Float>,
        verticalFieldOfView: Double, viewport: CGSize
    ) -> CGPoint? {
        let forward = simd_normalize(target - camera)
        guard simd_length(forward) > 0.5 else { return nil }
        var right = simd_cross(forward, SIMD3<Float>(0, 1, 0))
        // Straight up or down, where the rig never goes (§3.4's ±35°).
        guard simd_length(right) > 1e-6 else { return nil }
        right = simd_normalize(right)
        let up = simd_cross(right, forward)
        let offset = point - camera
        let depth = simd_dot(offset, forward)
        guard depth > 1e-6, viewport.width > 0, viewport.height > 0 else { return nil }
        let focal = 1 / tan(verticalFieldOfView / 2)
        let aspect = viewport.width / viewport.height
        let x = Double(simd_dot(offset, right) / depth) * focal / aspect
        let y = Double(simd_dot(offset, up) / depth) * focal
        return CGPoint(
            x: viewport.width / 2 + x * viewport.width / 2,
            y: viewport.height / 2 - y * viewport.height / 2
        )
    }

    // MARK: - §S8's handoff

    /// The world direction that is screen-right for a camera at `yaw`: the
    /// side the ghost second Mac slides in from, and where it comes to rest.
    static func screenRight(yaw: Double) -> SIMD3<Double> {
        SIMD3(cos(yaw), 0, -sin(yaw))
    }

    /// The outward normal of the face a camera at `yaw` looks square on to,
    /// which is the direction a cable leaves a receptacle on that face.
    static func outwardNormal(yaw: Double) -> SIMD3<Double> {
        SIMD3(sin(yaw), 0, cos(yaw))
    }

    /// Daylight between this Mac and the ghost, in centimetres: enough that
    /// the two read as two, not so much that the pair leaves the frame.
    static let handoffClearance = 6.0

    /// Centre-to-centre distance to the ghost. `extentAlongRight` is the ghost
    /// box's width along ``screenRight(yaw:)``; `across` is this Mac's
    /// footprint circumcircle, which is its silhouette at any pose.
    static func handoffGap(extentAlongRight: Double, across: Double) -> Double {
        extentAlongRight / 2 + across / 2 + handoffClearance
    }

    /// How far the ghost starts beyond its resting place before it slides in.
    static let handoffSlide = 10.0

    /// The cable stands off each face by this much before it turns.
    static let handoffStandoff = 0.3
    /// How far out of the faces the run between the two Macs is drawn.
    static let handoffReach = 3.2

    /// §S8's "single thin connecting line": out of the near port, across, and
    /// into the far one. Four points in the chassis's own centimetres, near
    /// end first. A straight line between two ports on the same face would
    /// lie *on* that face, over every other receptacle on it.
    static func handoffCable(
        from near: SIMD3<Double>, to far: SIMD3<Double>, normal: SIMD3<Double>
    ) -> [SIMD3<Double>] {
        [
            near + normal * handoffStandoff,
            near + normal * handoffReach,
            far + normal * handoffReach,
            far + normal * handoffStandoff,
        ]
    }

    /// Where the returning pulse is at `t` along the cable: `0` at the far
    /// end, `1` at the near port, moving at one speed over the whole run.
    static func cablePoint(_ path: [SIMD3<Double>], at t: Double) -> SIMD3<Double> {
        guard let first = path.first else { return .zero }
        guard path.count > 1 else { return first }
        let lengths = zip(path, path.dropFirst()).map { simd_length($1 - $0) }
        let total = lengths.reduce(0, +)
        guard total > 1e-9 else { return first }
        // From the far end back towards the near one.
        var remaining = (1 - min(max(t, 0), 1)) * total
        for (index, length) in lengths.enumerated() {
            if remaining <= length {
                let along = length > 1e-9 ? remaining / length : 0
                return path[index] + (path[index + 1] - path[index]) * along
            }
            remaining -= length
        }
        return path[path.count - 1]
    }

    // MARK: - Easing

    /// Ease-in-ease-out over `0...1` (§3.5: camera moves are 0.7 s,
    /// ease-in-ease-out).
    static func easeInOut(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// The 4 % dolly-out-and-back that rides on top of a camera arc (§3.5).
    /// Zero at both ends, 4 % of `radius` at the midpoint.
    static func dollyBump(_ t: Double, radius: Double) -> Double {
        sin(min(max(t, 0), 1) * .pi) * radius * 0.04
    }

    // MARK: - Framing

    /// The horizontal field of view of a camera whose vertical field of view is
    /// `vertical`, in a viewport `aspect` (width / height) wide.
    static func horizontalFieldOfView(vertical: Double, aspect: Double) -> Double {
        2 * atan(tan(vertical / 2) * max(aspect, 0.0001))
    }

    /// The distance at which `width` × `height` metres just fills a viewport of
    /// `viewport` points, with `margin` (1.0 = touching the edges).
    static func fitDistance(
        width: Double, height: Double, viewport: CGSize,
        verticalFieldOfView: Double, margin: Double
    ) -> Double {
        let aspect = viewport.height > 0 ? viewport.width / viewport.height : 1
        let horizontal = horizontalFieldOfView(vertical: verticalFieldOfView, aspect: aspect)
        let byWidth = (width / 2) / tan(horizontal / 2)
        let byHeight = (height / 2) / tan(verticalFieldOfView / 2)
        return max(byWidth, byHeight) * margin
    }

    /// How many points across a `metres`-wide feature reads at `distance`, in a
    /// viewport `viewportPoints` across whose full field of view is `fov`.
    static func pointSize(
        metres: Double, distance: Double, viewportPoints: Double, fieldOfView: Double
    ) -> Double {
        guard distance > 0, viewportPoints > 0, fieldOfView > 0 else { return 0 }
        return (metres / distance) / (2 * tan(fieldOfView / 2)) * viewportPoints
    }

    /// The inverse: the furthest the camera may sit and still leave a
    /// `metres`-wide feature `points` points across.
    static func distance(
        forPointSize points: Double, metres: Double,
        viewportPoints: Double, fieldOfView: Double
    ) -> Double {
        guard points > 0, fieldOfView > 0 else { return .infinity }
        return (metres * viewportPoints) / (points * 2 * tan(fieldOfView / 2))
    }

    /// UX_SPEC §8.4: every receptacle's hit target is at least 24 × 24 pt.
    static let minimumHitTargetPoints = 24.0

    /// How much room §3.4's product shot leaves around the machine.
    static let fitMargin = 1.06

    /// Everything the camera's framing depends on, in metres.
    ///
    /// The whole framing policy lives here rather than on ``StageScene`` so it
    /// can be exercised by `script/test_stage_math.sh`, which compiles this
    /// file alone. A number that decides whether a port is clickable should
    /// not be reachable only through RealityKit.
    struct Framing: Equatable, Sendable {
        /// The footprint's circumcircle — the silhouette at any orbit angle.
        var across: Double
        /// The visible height, lid included.
        var height: Double
        /// The receptacle collider, measured head-on.
        var proxy: CGSize

        init(across: Double, height: Double, proxy: CGSize) {
            self.across = across
            self.height = height
            self.proxy = proxy
        }
    }

    /// The distance that frames the whole machine.
    static func fitDistance(
        _ framing: Framing, viewport: CGSize, verticalFieldOfView: Double
    ) -> Double {
        fitDistance(
            width: framing.across, height: framing.height, viewport: viewport,
            verticalFieldOfView: verticalFieldOfView, margin: fitMargin
        )
    }

    /// How many points across the receptacle proxy reads at `distance`.
    static func receptaclePointSize(
        _ framing: Framing, distance: Double, viewport: CGSize, verticalFieldOfView: Double
    ) -> Double {
        let aspect = viewport.height > 0 ? viewport.width / viewport.height : 1
        return pointSize(
            metres: framing.proxy.width, distance: distance, viewportPoints: viewport.width,
            fieldOfView: horizontalFieldOfView(vertical: verticalFieldOfView, aspect: aspect)
        )
    }

    /// The dolly limits: a 1.4× range around the fit distance (§3.4), with the
    /// far end pulled in so a receptacle proxy never falls below 24 × 24 pt
    /// (§8.4).
    ///
    /// Where the two cannot both hold — a stage too narrow to show the whole
    /// machine and still leave 24 pt across a receptacle — §8.4 wins and the
    /// resting pose crops a little, because a target a motor-impaired user
    /// cannot hit is a broken app and a slightly cropped hero is a picture.
    /// The far end collapses onto the near end rather than inverting.
    static func dollyRange(
        _ framing: Framing, viewport: CGSize, verticalFieldOfView: Double
    ) -> (minimum: Double, maximum: Double) {
        let fit = fitDistance(
            framing, viewport: viewport, verticalFieldOfView: verticalFieldOfView
        )
        let aspect = viewport.height > 0 ? viewport.width / viewport.height : 1
        let horizontal = horizontalFieldOfView(vertical: verticalFieldOfView, aspect: aspect)
        let byWidth = distance(
            forPointSize: minimumHitTargetPoints, metres: framing.proxy.width,
            viewportPoints: viewport.width, fieldOfView: horizontal
        )
        let byHeight = distance(
            forPointSize: minimumHitTargetPoints, metres: framing.proxy.height,
            viewportPoints: viewport.height, fieldOfView: verticalFieldOfView
        )
        let ceiling = min(fit * 1.4, min(byWidth, byHeight))
        // The near limit never passes the far one: where the floor bites
        // harder than the 1.4× range, the whole range moves in rather than
        // inverting or collapsing onto a distance nothing can be clicked at.
        let minimum = min(fit * 0.72, ceiling)
        return (minimum, max(minimum, ceiling))
    }

    static func clamp(_ value: Double, _ range: (minimum: Double, maximum: Double)) -> Double {
        min(max(value, range.minimum), range.maximum)
    }

    // MARK: - The waking-ports beat

    /// UX_SPEC §9.2: the receptacles light in physical order with a 60 ms
    /// stagger, once per launch. Under Reduce Motion they appear together
    /// (§8.6), so the delay collapses to zero.
    static func wakeDelay(index: Int, reduceMotion: Bool) -> Duration {
        guard !reduceMotion else { return .zero }
        return .milliseconds(60 * max(index, 0))
    }

    // MARK: - Breathing

    /// UX_SPEC §3.5: "Nothing loops except the 'link coming up' breath (1.6 s,
    /// 8 → 18 % opacity) and the Identify shimmer", and §S4b makes the shimmer
    /// the same 1.6 s, 8 → 18 % cycle **in phase** on every eligible
    /// receptacle — which is what reads as *listening* rather than *loading*.
    static let breathPeriod = 1.6
    static let breathLow = 0.08
    static let breathHigh = 0.18

    /// The looping breath at `seconds` on the scene's own clock. In phase
    /// everywhere, because every receptacle reads the same clock.
    static func breath(seconds: Double) -> Double {
        let phase = seconds / breathPeriod * 2 * .pi
        return breathLow + (breathHigh - breathLow) * (0.5 + 0.5 * sin(phase))
    }

    /// The middle of the cycle: what Reduce Motion freezes the breath at, and
    /// what a still frame shows (§3.6).
    static let restingBreath = (breathLow + breathHigh) / 2

    /// UX_SPEC §S3: a receptacle a check names takes an attention ring "and a
    /// single 1.6 s breath" — one soft dip and back, after which the ring
    /// simply stays. It is a breath, not a loop, so it has an end.
    ///
    /// - Returns: a multiplier on the ring's steady opacity, 1 once the breath
    ///   is over.
    static func singleBreath(secondsSinceStart seconds: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion, seconds >= 0, seconds < breathPeriod else { return 1 }
        return 1 - 0.55 * sin(seconds / breathPeriod * .pi)
    }

    // MARK: - The bridge ribbon

    /// The distance from the chassis's vertical axis to its footprint at
    /// `angle`, measured the way the stage measures yaw: 0 looks out of the
    /// front face along `+z`, `π/2` out of the right face along `+x`.
    ///
    /// The footprint is taken as a sharp rectangle. The real one is rounded,
    /// which only ever pulls the surface further in, so a ribbon drawn against
    /// this never sinks into the body at a corner.
    static func footprintRadius(angle: Double, halfWidth: Double, halfDepth: Double) -> Double {
        let x = abs(sin(angle)), z = abs(cos(angle))
        let byWidth = x > 1e-9 ? halfWidth / x : Double.infinity
        let byDepth = z > 1e-9 ? halfDepth / z : Double.infinity
        return min(byWidth, byDepth)
    }

    /// UX_SPEC §4.4: "a soft translucent ribbon arcing **across the chassis
    /// surface** between the members of the same bridge".
    ///
    /// The path walks the footprint's outline from one receptacle to the other
    /// rather than cutting between them, so two ports on the same face get an
    /// arc along that face and two ports on different faces get one that wraps
    /// the corner instead of passing through the machine. It touches down
    /// exactly on both receptacles, so the ribbon reads as attached to them.
    ///
    /// - Parameters:
    ///   - lift: how far it stands off the surface at the middle — a hair, so
    ///     it stays a ribbon on the chassis rather than a cable in front of it.
    ///   - rise: how far it arcs **up the face** at the middle. Without this
    ///     the ribbon runs straight through the ring tracks of every receptacle
    ///     between its two ends, and §4.4 is explicit that the ribbon "never
    ///     replaces the segmented ring, which remains the primary state
    ///     signal". Arcing over them is what keeps that true.
    ///
    /// Centimetres, in the chassis's own frame, `y` up from the ground plane.
    static func ribbonPath(
        from start: SIMD3<Double>, to end: SIMD3<Double>,
        halfWidth: Double, halfDepth: Double, lift: Double, rise: Double, samples: Int
    ) -> [SIMD3<Double>] {
        let samples = max(samples, 2)
        let startAngle = atan2(start.x, start.z)
        let sweep = shortestAngleDelta(from: startAngle, to: atan2(end.x, end.z))
        // Where the two ends sit relative to the outline, so a receptacle that
        // is not exactly on the sharp rectangle still gets a ribbon that lands
        // on it rather than beside it.
        let startRadius = (start.x * start.x + start.z * start.z).squareRoot()
        let endRadius = (end.x * end.x + end.z * end.z).squareRoot()
        let startSlack = startRadius - footprintRadius(
            angle: startAngle, halfWidth: halfWidth, halfDepth: halfDepth
        )
        let endSlack = endRadius - footprintRadius(
            angle: startAngle + sweep, halfWidth: halfWidth, halfDepth: halfDepth
        )
        return (0...samples).map { step in
            let t = Double(step) / Double(samples)
            let angle = startAngle + sweep * t
            let outline = footprintRadius(
                angle: angle, halfWidth: halfWidth, halfDepth: halfDepth
            )
            let slack = startSlack + (endSlack - startSlack) * t
            let radius = outline + slack + lift * sin(t * .pi)
            let arc = sin(t * .pi)
            return SIMD3(
                radius * sin(angle),
                start.y + (end.y - start.y) * t + rise * arc,
                radius * cos(angle)
            )
        }
    }

    /// How far a ribbon stands off the chassis at its highest point: a hair on
    /// a short hop between neighbours, more on one that has to get round a
    /// corner, and never so much that it reads as a wire rather than a ribbon.
    static func ribbonLift(from start: SIMD3<Double>, to end: SIMD3<Double>) -> Double {
        let span = simd_length(end - start)
        // The floor clears the ring tracks, which stand about 1 mm off the
        // face; the ceiling keeps a ribbon that has to get from the back of a
        // Mac Studio to the front from becoming a handle on it.
        return min(max(span * 0.09, 0.32), 1.2)
    }

    /// UX_SPEC §6.2 R2's thread stands further off the chassis than a ribbon
    /// does: it is a cable's worth of light, not a tie on the surface, and
    /// "arcing across the chassis" has to read as *across* rather than
    /// *along*. Twice the ribbon's lift, with the same floor over the ring
    /// tracks and a ceiling that keeps a back-to-front loop on the machine.
    static func loopLift(from start: SIMD3<Double>, to end: SIMD3<Double>) -> Double {
        min(max(ribbonLift(from: start, to: end) * 2, 0.6), 2.2)
    }

    /// How far a ribbon arcs up the face, given how far apart its ends are and
    /// how much face there is above them.
    ///
    /// Enough to clear the ring tracks of everything it passes over, and never
    /// more than the face can hold — a notebook's side is 1.55 cm tall, and a
    /// ribbon that left it would be drawing in mid-air.
    static func ribbonRise(span: Double, room: Double) -> Double {
        min(min(max(span * 0.12, 0.55), 1.1), max(room, 0))
    }

    /// UX_SPEC §S6 and §9.3: the ribbon "detaches from the chosen receptacle
    /// and retracts into the others". `retraction` runs 0 → 1 from the end
    /// that let go, so the segment nearest it is the first to leave.
    ///
    /// - Parameter position: where a segment sits along the ribbon, 0 at the
    ///   end that detaches and 1 at the end it retracts into.
    static func ribbonSegmentOpacity(position: Double, retraction: Double) -> Double {
        // A soft edge, so the ribbon does not come apart one hard segment at a
        // time; §3.5 allows no bounce and no overshoot, and this has neither.
        // The edge is carried past both ends, so a ribbon at rest is whole and
        // a fully retracted one is gone, with nothing popping in between.
        let edge = 0.18
        let front = retraction * (1 + edge) - edge
        return min(max((position - front) / edge, 0), 1)
    }

    // MARK: - The light thread

    /// UX_SPEC §4.2's light thread, in centimetres in the receptacle's own
    /// frame: `z` out of the face, `y` up, `x` across it.
    ///
    /// A cubic, because a cable does not leave a port at an angle. It comes
    /// out along the receptacle's normal, carries that for a few centimetres
    /// and only then droops under its own weight — "a smooth curve with the
    /// sag of a real cable". The first control point is straight out in front
    /// of the opening, which is what fixes the departure; the second is
    /// already most of the way down, which is where the sag comes from. The
    /// far end is where §4.2 has the thread "fade out 40 pt from the frame
    /// edge".
    static func threadPath(samples: Int = 48) -> [SIMD3<Double>] {
        let samples = max(samples, 2)
        let start = SIMD3<Double>(0, 0, 0.4)
        let departure = SIMD3<Double>(0, -0.1, 5.0)
        let droop = SIMD3<Double>(0.3, -3.4, 9.2)
        let end = SIMD3<Double>(0.6, -7, 10)
        return (0..<samples).map { step in
            let t = Double(step) / Double(samples - 1)
            let inverse = 1 - t
            return inverse * inverse * inverse * start
                + 3 * inverse * inverse * t * departure
                + 3 * inverse * t * t * droop
                + t * t * t * end
        }
    }

    /// What is left of the thread's radius at the far end: §4.2's "tapering
    /// gently" has to still be a tube there, not a point.
    static let threadTipShare: Float = 0.25

    /// The taper, as a share of the radius at the receptacle. Straight, so
    /// the silhouette has no kink in it anywhere along the length.
    static func threadTaper(at u: Float) -> Float {
        1 - (1 - threadTipShare) * min(max(u, 0), 1)
    }

    /// The fade, as a share of the thread's opacity at the receptacle: §4.2's
    /// "fading along its length", squared so most of the fall happens over
    /// the second half and the thread reads as light leaving rather than as a
    /// rod dimmed evenly.
    static func threadFade(at u: Float) -> Float {
        let left = 1 - min(max(u, 0), 1)
        return left * left
    }

    /// A tube swept along a curve: positions, normals, texture coordinates and
    /// the triangles between them, in whatever unit the spine is in.
    struct SweptTube: Equatable, Sendable {
        var positions: [SIMD3<Float>]
        var normals: [SIMD3<Float>]
        var coordinates: [SIMD2<Float>]
        var indices: [UInt32]
        /// How many rings were swept, and how many vertices each one carries.
        var samples: Int
        var sides: Int
    }

    /// Sweeps a ring of `sides` vertices along `path`, `radius` wide at each
    /// point: **one** surface, which is what §4.2 means by "one continuous
    /// tube … never a chain of visible segments". A chain of cylinders shows
    /// every joint in the silhouette at exactly the bend a cable is for.
    ///
    /// The ring's frame is carried along the curve rather than rebuilt at
    /// each point — each step rotates the previous frame by the rotation
    /// between the two tangents, a parallel transport — so the tube never
    /// twists about its own axis, which a frame built from a fixed up vector
    /// does wherever the curve turns toward it.
    ///
    /// `u` runs 0 → 1 along the length, which is what the fade texture is
    /// read by, and `v` runs round the ring. The seam is deliberately not
    /// duplicated: nothing is ever mapped across the ring, so the one column
    /// where `v` wraps costs nothing and the vertex count stays exactly
    /// `samples × sides`.
    ///
    /// - Parameter radius: asked for at each `u`, so a taper is the caller's.
    static func sweep(
        along path: [SIMD3<Float>], sides: Int = 12, radius: (Float) -> Float
    ) -> SweptTube? {
        // A repeated point has no direction, and a spine that walks a
        // chassis's outline can easily arrive at one twice.
        var spine: [SIMD3<Float>] = []
        for point in path where spine.last.map({ simd_distance($0, point) > 1e-7 }) ?? true {
            spine.append(point)
        }
        guard spine.count >= 2, sides >= 3 else { return nil }

        // The tangent at an interior point is the chord across it, so the
        // ring lies square to the curve rather than to one of its two legs.
        let tangents: [SIMD3<Float>] = spine.indices.map { index in
            let run = switch index {
            case 0: spine[1] - spine[0]
            case spine.count - 1: spine[index] - spine[index - 1]
            default: spine[index + 1] - spine[index - 1]
            }
            return simd_normalize(run)
        }

        // Any vector across the first tangent will do to start; the transport
        // decides every one after it.
        var across = simd_cross(tangents[0], SIMD3<Float>(0, 1, 0))
        if simd_length(across) < 1e-4 {
            across = simd_cross(tangents[0], SIMD3<Float>(1, 0, 0))
        }
        var normal = simd_normalize(across)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []
        positions.reserveCapacity(spine.count * sides)
        normals.reserveCapacity(spine.count * sides)
        coordinates.reserveCapacity(spine.count * sides)

        for (index, centre) in spine.enumerated() {
            let tangent = tangents[index]
            if index > 0 {
                let turn = simd_cross(tangents[index - 1], tangent)
                let sine = simd_length(turn)
                if sine > 1e-7 {
                    let angle = atan2(sine, simd_dot(tangents[index - 1], tangent))
                    normal = simd_quatf(angle: angle, axis: turn / sine).act(normal)
                }
                // Rounding leaves the carried frame a hair off square; this
                // puts it back, so 48 steps do not accumulate into a lean.
                let leftover = normal - tangent * simd_dot(normal, tangent)
                guard simd_length(leftover) > 1e-6 else { return nil }
                normal = simd_normalize(leftover)
            }
            let binormal = simd_cross(tangent, normal)
            let u = Float(index) / Float(spine.count - 1)
            let width = max(radius(u), 1e-5)
            for side in 0..<sides {
                let angle = 2 * Float.pi * Float(side) / Float(sides)
                let outward = normal * cos(angle) + binormal * sin(angle)
                positions.append(centre + outward * width)
                normals.append(outward)
                coordinates.append(SIMD2(u, Float(side) / Float(sides)))
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity((spine.count - 1) * sides * 6)
        for ring in 0..<(spine.count - 1) {
            let near = UInt32(ring * sides)
            let far = UInt32((ring + 1) * sides)
            for side in 0..<sides {
                let next = UInt32((side + 1) % sides)
                let a = near + UInt32(side), b = near + next
                let c = far + next, d = far + UInt32(side)
                // Counter-clockwise seen from outside the tube: `tangent ×
                // ring direction` points inward, so this is the other winding.
                indices.append(contentsOf: [a, c, d, a, b, c])
            }
        }

        return SweptTube(
            positions: positions, normals: normals, coordinates: coordinates,
            indices: indices, samples: spine.count, sides: sides
        )
    }

    // MARK: - Rounded-rectangle outlines

    /// One point on a rounded-rectangle centreline, with the outward normal and
    /// the distance travelled to reach it.
    struct PathSample: Equatable, Sendable {
        var point: SIMD2<Double>
        var normal: SIMD2<Double>
        var distance: Double
    }

    /// The closed rounded-rectangle centreline, walked counter-clockwise from
    /// the left end of the bottom edge's flat, with exact outward normals.
    ///
    /// The last sample repeats the first point with the full perimeter as its
    /// distance, so a span that wraps past the start still interpolates.
    static func roundedRectPath(
        width: Double, height: Double, cornerRadius: Double, cornerSegments: Int = 6
    ) -> [PathSample] {
        let halfWidth = max(width, 0.0001) / 2
        let halfHeight = max(height, 0.0001) / 2
        let radius = min(max(cornerRadius, 0), min(halfWidth, halfHeight))
        let insetX = halfWidth - radius
        let insetY = halfHeight - radius
        let segments = max(cornerSegments, 1)

        var samples: [PathSample] = []
        var distance = 0.0
        var previous: SIMD2<Double>?

        func append(_ point: SIMD2<Double>, _ normal: SIMD2<Double>) {
            if let previous { distance += simd_length(point - previous) }
            previous = point
            samples.append(PathSample(point: point, normal: normal, distance: distance))
        }

        func corner(center: SIMD2<Double>, from start: Double, to end: Double) {
            // The first sample of an arc repeats the straight edge's last
            // point, so it is skipped; only the normal turns.
            for step in 1...segments {
                let angle = start + (end - start) * Double(step) / Double(segments)
                let normal = SIMD2(cos(angle), sin(angle))
                append(center + normal * radius, normal)
            }
        }

        let down = SIMD2(0.0, -1.0), right = SIMD2(1.0, 0.0)
        let up = SIMD2(0.0, 1.0), left = SIMD2(-1.0, 0.0)

        append(SIMD2(-insetX, -halfHeight), down)
        append(SIMD2(insetX, -halfHeight), down)
        corner(center: SIMD2(insetX, -insetY), from: -.pi / 2, to: 0)
        append(SIMD2(halfWidth, insetY), right)
        corner(center: SIMD2(insetX, insetY), from: 0, to: .pi / 2)
        append(SIMD2(-insetX, halfHeight), up)
        corner(center: SIMD2(-insetX, insetY), from: .pi / 2, to: .pi)
        append(SIMD2(-halfWidth, -insetY), left)
        corner(center: SIMD2(-insetX, -insetY), from: .pi, to: 1.5 * .pi)
        append(SIMD2(-insetX, -halfHeight), down)
        return samples
    }

    /// The length of one corner of ``roundedRectPath(width:height:cornerRadius:cornerSegments:)``
    /// as that path actually walks it: `cornerSegments` chords, which is a
    /// hair under the arc. Anything that places itself along the path by
    /// distance has to count the way the path counts.
    static func cornerLength(radius: Double, cornerSegments: Int) -> Double {
        let segments = Double(max(cornerSegments, 1))
        return segments * 2 * radius * sin(.pi / (4 * segments))
    }

    /// Where the middle of each face lies along ``roundedRectPath(width:height:cornerRadius:cornerSegments:)``
    /// walked as a footprint — `width` across, `depth` front to back — with
    /// `cornerSegments` chords per corner, the same count the path was built
    /// with.
    ///
    /// The path starts at the left end of the back face's flat and runs
    /// counter-clockwise seen from above: back, then the right side, the
    /// front, the left. A footprint is not square, so these are not quarters
    /// of the perimeter.
    static func faceCentreDistances(
        width: Double, depth: Double, cornerRadius: Double, cornerSegments: Int = 8
    ) -> (back: Double, right: Double, front: Double, left: Double) {
        let radius = min(max(cornerRadius, 0), min(width, depth) / 2)
        let flatAcross = width / 2 - radius, flatDeep = depth / 2 - radius
        let corner = cornerLength(radius: radius, cornerSegments: cornerSegments)
        let back = flatAcross
        let right = back + flatAcross + corner + flatDeep
        let front = right + flatDeep + corner + flatAcross
        let left = front + flatAcross + corner + flatDeep
        return (back, right, front, left)
    }

    /// The path distance from a face's middle to the point on the outline
    /// directly across from a position `offset` along that face, for a face
    /// `across` wide with `cornerRadius` corners walked in `cornerSegments`
    /// chords.
    ///
    /// On the flat part of the face this is the offset itself; past the end
    /// of the flat, the outline turns into the corner, and the point at that
    /// `x` is further along the outline than it is across. An offset beyond
    /// the footprint lands at the corner's end.
    static func arcOffset(
        fromFaceCentre offset: Double, across: Double, cornerRadius: Double,
        cornerSegments: Int = 8
    ) -> Double {
        let radius = min(max(cornerRadius, 0), across / 2)
        let flat = across / 2 - radius
        let magnitude = abs(offset)
        guard magnitude > flat, radius > 0 else { return offset }
        let into = min((magnitude - flat) / radius, 1)
        let corner = cornerLength(radius: radius, cornerSegments: cornerSegments)
        return (flat + corner * asin(into) / (.pi / 2)) * (offset < 0 ? -1 : 1)
    }

    /// The point and normal `distance` along `path`, interpolated.
    static func sample(_ path: [PathSample], at distance: Double) -> PathSample {
        guard let first = path.first, let last = path.last else {
            return PathSample(point: .zero, normal: SIMD2(1, 0), distance: 0)
        }
        if distance <= first.distance { return first }
        if distance >= last.distance { return last }
        var low = 0, high = path.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if path[mid].distance <= distance { low = mid } else { high = mid }
        }
        let a = path[low], b = path[high]
        let span = b.distance - a.distance
        let t = span > 0 ? (distance - a.distance) / span : 0
        let normal = simd_normalize(a.normal + (b.normal - a.normal) * t)
        return PathSample(
            point: a.point + (b.point - a.point) * t, normal: normal, distance: distance
        )
    }

    /// Spans of the perimeter, as fractions of its length, for each ring shape
    /// in UX_SPEC §4.3. Every span is `(start, end)` with `start < end`.
    enum RingPattern: Hashable, Sendable {
        /// One unbroken ring: ready, hover, selection.
        case solid
        /// Four arcs with four gaps: a bridge member.
        case segmented
        /// §S5's hover-to-preview: the same four arcs with the gaps widened a
        /// hair, which is what "Leave the Thunderbolt Bridge" looks like a
        /// moment before anyone agrees to it.
        case segmentedWide
        /// §S6: the segmented ring part way through closing. `gaps` is how many
        /// of the four have closed, so 0 is ``segmented`` and 4 is a solid
        /// ring. These five shapes are also exactly what Reduce Motion steps
        /// between (§3.6).
        case closing(gaps: Int)
        /// The drift ring.
        case dashed
    }

    /// The gap in ``RingPattern/segmented``, as a fraction of the perimeter.
    static let segmentedGap = 0.09
    /// §S5: "the segmented ring's gaps widen a hair."
    static let widenedGap = 0.13

    /// Four quarter arcs with `gap`-wide gaps between them, the first `closed`
    /// of which have closed up.
    ///
    /// Gaps close in the ring's own winding order, starting at the middle of
    /// the bottom edge — which is clockwise as drawn on a face the camera is
    /// square on to (§3.5's "closes clockwise"), because the outline is walked
    /// counter-clockwise in the receptacle's own frame and that frame faces the
    /// viewer.
    static func arcs(gap: Double, closed: Int) -> [(start: Double, end: Double)] {
        let closed = min(max(closed, 0), 4)
        guard closed < 4 else { return [(0, 1)] }
        var spans: [(start: Double, end: Double)] = []
        // The first span swallows one more quarter for every gap that closed.
        let first = (start: gap / 2, end: Double(closed + 1) / 4 - gap / 2)
        spans.append(first)
        for index in (closed + 1)..<4 {
            let start = Double(index) / 4 + gap / 2
            spans.append((start, start + 0.25 - gap))
        }
        return spans
    }

    /// How many of the four gaps have closed after `step` of `total` real
    /// steps (UX_SPEC §S6: one gap per **real completed step**, never a timer).
    ///
    /// The last step always lands on the solid ring and nothing before it does,
    /// so a checklist of five — §S6's — steps through all five shapes in order
    /// and one of four closes a gap a step.
    static func closedGaps(step: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        let step = min(max(step, 0), total)
        guard step < total else { return 4 }
        return min(Int(Double(step) / Double(total) * 4), 3)
    }

    static func spans(for pattern: RingPattern) -> [(start: Double, end: Double)] {
        switch pattern {
        case .solid:
            return [(0, 1)]
        case .segmented:
            return arcs(gap: segmentedGap, closed: 0)
        case .segmentedWide:
            return arcs(gap: widenedGap, closed: 0)
        case .closing(let gaps):
            return arcs(gap: segmentedGap, closed: gaps)
        case .dashed:
            let dash = 0.038, gap = 0.026
            let period = dash + gap
            let count = max(Int((1.0 / period).rounded()), 4)
            let exact = 1.0 / Double(count)
            return (0..<count).map { index in
                let start = Double(index) * exact
                return (start, start + exact * dash / period)
            }
        }
    }
}
