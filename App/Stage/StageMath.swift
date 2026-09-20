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

    // MARK: - Rounded-rectangle outlines

    /// One point on a rounded-rectangle centreline, with the outward normal and
    /// the distance travelled to reach it.
    struct PathSample: Equatable, Sendable {
        var point: SIMD2<Double>
        var normal: SIMD2<Double>
        var distance: Double
    }

    /// The closed rounded-rectangle centreline, walked counter-clockwise from
    /// the middle of the bottom edge, with exact outward normals.
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
        /// The drift ring.
        case dashed
    }

    static func spans(for pattern: RingPattern) -> [(start: Double, end: Double)] {
        switch pattern {
        case .solid:
            return [(0, 1)]
        case .segmented:
            // Four gaps, one at each quarter, each 9 % of the perimeter.
            let gap = 0.09
            return (0..<4).map { index in
                let start = Double(index) / 4 + gap / 2
                return (start, start + 0.25 - gap)
            }
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
