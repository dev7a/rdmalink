#!/usr/bin/env bash
# Exercises App/Stage/StageMath.swift on its own.
#
# The stage's numbers — the orbit clamps, the 24 pt dolly floor, the easing and
# the rounded-rectangle outlines the ring tracks are built from — are the part
# of the 3D code that can be wrong without looking wrong. StageMath imports
# nothing but Foundation and simd so exactly this is possible: no Xcode
# project, no RealityKit, no window.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/main.swift" <<'SWIFT'
import Foundation
import simd

var failures = 0

@MainActor func check(_ condition: Bool, _ what: String) {
    if condition { return }
    failures += 1
    FileHandle.standardError.write(Data("FAIL: \(what)\n".utf8))
}

func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool {
    abs(a - b) <= tolerance
}

// Shortest way round, so a front-to-back arc never takes the long way.
check(near(StageMath.shortestAngleDelta(from: 0.1, to: 0.4), 0.3, 1e-12), "delta forward")
check(near(StageMath.shortestAngleDelta(from: 0.1, to: 6.0), 5.9 - 2 * .pi, 1e-12), "delta wraps backwards")
check(abs(StageMath.shortestAngleDelta(from: 0, to: .pi * 1.9)) <= .pi, "delta stays in -pi...pi")

// Elevation is clamped to +-35 degrees (UX_SPEC 3.4).
check(near(StageMath.clampPitch(2.0), StageMath.maximumPitch), "pitch clamps up")
check(near(StageMath.clampPitch(-2.0), -StageMath.maximumPitch), "pitch clamps down")
check(near(StageMath.maximumPitch, 35 * .pi / 180), "pitch limit is 35 degrees")

// Face order is [front, right, back, left].
check(StageMath.faceIndex(forYaw: 0) == 0, "yaw 0 shows the front")
check(StageMath.faceIndex(forYaw: .pi / 2) == 1, "yaw pi/2 shows the right")
check(StageMath.faceIndex(forYaw: .pi) == 2, "yaw pi shows the back")
check(StageMath.faceIndex(forYaw: -.pi / 2) == 3, "yaw -pi/2 shows the left")
// The three-quarter poses the camera actually rests at must resolve the same.
check(StageMath.faceIndex(forYaw: .pi - 0.55) == 2, "desktop rest pose shows the back")
check(StageMath.faceIndex(forYaw: -.pi / 2 + 0.75) == 3, "notebook rest pose shows the left")

// Easing and the 4 % dolly bump.
check(near(StageMath.easeInOut(0), 0), "ease starts at 0")
check(near(StageMath.easeInOut(1), 1), "ease ends at 1")
check(near(StageMath.easeInOut(0.5), 0.5, 1e-12), "ease is symmetric")
check(near(StageMath.dollyBump(0, radius: 1), 0), "bump starts at 0")
check(near(StageMath.dollyBump(1, radius: 1), 0, 1e-12), "bump ends at 0")
check(near(StageMath.dollyBump(0.5, radius: 1), 0.04, 1e-12), "bump peaks at 4 %")

// Orbit placement: yaw pi puts the camera behind the machine.
let behind = StageMath.orbitPosition(target: .zero, yaw: .pi, pitch: 0, radius: 2)
check(abs(behind.z + 2) < 1e-5 && abs(behind.x) < 1e-5, "yaw pi sits at -z")
let above = StageMath.orbitPosition(target: .zero, yaw: 0, pitch: .pi / 2, radius: 2)
check(abs(above.y - 2) < 1e-5, "pitch pi/2 sits overhead")

// Projection round-trips.
let viewport = CGSize(width: 580, height: 600)
let fov = 2 * atan(12.0 / 35.0)
let size = StageMath.pointSize(
    metres: 0.009, distance: 0.34, viewportPoints: viewport.height, fieldOfView: fov
)
let back = StageMath.distance(
    forPointSize: size, metres: 0.009, viewportPoints: viewport.height, fieldOfView: fov
)
check(near(back, 0.34, 1e-9), "point size and distance are inverses")

// The framing policy, over the chassis the catalogue actually carries.
// Numbers in centimetres from Packages/.../ReceptacleCatalogue.swift, and the
// proxy from ChassisFeature.colliderSize -- 1.6 x 1.65 cm on a desktop.
let studioProxy = CGSize(width: 0.016, height: 0.0165)
let studio = StageMath.Framing(
    across: (0.197 * 0.197 + 0.197 * 0.197).squareRoot(), height: 0.095, proxy: studioProxy
)
let mini = StageMath.Framing(
    across: (0.127 * 0.127 + 0.127 * 0.127).squareRoot(), height: 0.050, proxy: studioProxy
)
let notebook = StageMath.Framing(
    across: (0.3126 * 0.3126 + 0.2212 * 0.2212).squareRoot(), height: 0.2298,
    proxy: CGSize(width: 0.016, height: 0.016)
)

@MainActor func restingRadius(_ framing: StageMath.Framing, _ viewport: CGSize, _ scale: Double) -> Double {
    let fit = StageMath.fitDistance(framing, viewport: viewport, verticalFieldOfView: fov)
    let range = StageMath.dollyRange(framing, viewport: viewport, verticalFieldOfView: fov)
    check(range.maximum >= range.minimum, "range does not invert at \(viewport)")
    check(range.minimum <= fit * 0.72 + 1e-12, "near limit is at most 0.72x at \(viewport)")
    check(range.minimum <= range.maximum, "near limit never passes the far one at \(viewport)")
    check(range.maximum <= fit * 1.4 + 1e-12, "far limit is at most 1.4x at \(viewport)")
    return StageMath.clamp(fit * scale, range)
}

// UX_SPEC 8.4: every receptacle's hit target is at least 24 x 24 pt, at the
// pose the app opens in, in every stage the window can produce -- the default
// split, the minimum window, and 8.5's 180 pt strip. This is the property
// StageScene.dollyRange and StageScene.restingRadius are built to hold; it
// fails the moment the collider is narrowed back inside the 0.985 cm pitch.
let stages = [
    CGSize(width: 580, height: 600),
    CGSize(width: 460, height: 500),
    CGSize(width: 900, height: 180),
]
for stage in stages {
    for (name, framing, scale) in [
        ("Mac Studio", studio, 1.0), ("Mac mini", mini, 1.0), ("MacBook", notebook, 1.05),
    ] {
        let radius = restingRadius(framing, stage, scale)
        let points = StageMath.receptaclePointSize(
            framing, distance: radius, viewport: stage, verticalFieldOfView: fov
        )
        check(points >= 24 - 0.01, "\(name) rests at 24 pt in \(stage), got \(points)")
    }
}

// The far limit of the range is where 24 pt is reached exactly, or the 1.4x
// ceiling where the geometry was roomy enough that it was never in danger.
for stage in stages {
    let range = StageMath.dollyRange(studio, viewport: stage, verticalFieldOfView: fov)
    let points = StageMath.receptaclePointSize(
        studio, distance: range.maximum, viewport: stage, verticalFieldOfView: fov
    )
    check(points >= 24 - 1e-6, "StageMath honours its own 24 pt ceiling in \(stage)")
}

// Framing: a wider viewport needs no more distance than a square one.
let wide = StageMath.fitDistance(
    width: 0.197, height: 0.095, viewport: CGSize(width: 1200, height: 600),
    verticalFieldOfView: fov, margin: 1.15
)
let narrow = StageMath.fitDistance(
    width: 0.197, height: 0.095, viewport: CGSize(width: 400, height: 600),
    verticalFieldOfView: fov, margin: 1.15
)
check(wide <= narrow, "a wider stage frames a face no further away")

// The rounded-rectangle outline the ring tracks are built from.
let path = StageMath.roundedRectPath(width: 2, height: 1, cornerRadius: 0.25, cornerSegments: 24)
check(path.count > 8, "path has samples")
let perimeter = path.last!.distance
let analytic = 2 * (2 - 0.5) + 2 * (1 - 0.5) + 2 * .pi * 0.25
check(abs(perimeter - analytic) < 0.01, "perimeter matches the analytic rounded rect")
check(simd_length(path.first!.point - path.last!.point) < 1e-12, "path closes")
for sample in path {
    check(abs(simd_length(sample.normal) - 1) < 1e-9, "normals are unit length")
    check(sample.point.x >= -1.0001 && sample.point.x <= 1.0001, "points stay in x bounds")
    check(sample.point.y >= -0.5001 && sample.point.y <= 0.5001, "points stay in y bounds")
}
var walked = -1.0
for sample in path {
    check(sample.distance >= walked, "distance never goes backwards")
    walked = sample.distance
}
// A degenerate corner radius must not produce NaN.
let square = StageMath.roundedRectPath(width: 1, height: 1, cornerRadius: 0)
check(square.allSatisfy { $0.point.x.isFinite && $0.point.y.isFinite }, "zero radius is finite")
let overRadius = StageMath.roundedRectPath(width: 1, height: 1, cornerRadius: 10)
check(overRadius.allSatisfy { $0.point.x.isFinite }, "an over-large radius is clamped")

// The opening profiles the stage extrudes (UX_SPEC 4.3, 4.5). A radius equal
// to half of both extents is a circle, and a radius equal to half the smaller
// one is a stadium -- the Mac Studio's power socket and the USB-C mouth. This
// is the clamp MeshResource.generateBox got wrong by also clamping against the
// extrusion depth; the profile must be clamped by its own two extents only.
let circle = StageMath.roundedRectPath(width: 1.9, height: 1.9, cornerRadius: 0.95, cornerSegments: 24)
for sample in circle {
    check(abs(simd_length(sample.point) - 0.95) < 1e-9, "a radius of half the extent is a circle")
}
let stadium = StageMath.roundedRectPath(width: 0.95, height: 0.35, cornerRadius: 0.17, cornerSegments: 24)
let stadiumWidth = stadium.map(\.point.x).max()! - stadium.map(\.point.x).min()!
let stadiumHeight = stadium.map(\.point.y).max()! - stadium.map(\.point.y).min()!
check(abs(stadiumWidth - 0.95) < 1e-9, "the stadium keeps its width")
check(abs(stadiumHeight - 0.35) < 1e-9, "the stadium keeps its height")
check(
    stadium.contains { abs($0.point.x) > 0.95 / 2 - 0.17 + 1e-9 },
    "the stadium's ends are round, not clipped"
)

// The grille strip's walk round the footprint (StageMesh.grilleStrip). Face
// middles lie where the path puts them -- in the path's own chords, not the
// analytic arc -- and an offset along a face turns into the corner rather
// than floating off it.
let studioPath = StageMath.roundedRectPath(width: 19.7, height: 19.7, cornerRadius: 2.4, cornerSegments: 8)
let studioPerimeter = studioPath.last!.distance
let corner = StageMath.cornerLength(radius: 2.4, cornerSegments: 8)
check(corner < .pi * 2.4 / 2 && corner > .pi * 2.4 / 2 - 0.01, "eight chords are a hair under the quarter arc")
check(near(4 * corner + 4 * 14.9, studioPerimeter, 1e-9), "and four of them plus the flats are the path's own perimeter")
let centres = StageMath.faceCentreDistances(width: 19.7, depth: 19.7, cornerRadius: 2.4, cornerSegments: 8)
check(near(centres.back, 7.45, 1e-12), "the back face's middle is half a flat from where the path starts")
check(near(centres.right, 7.45 + 7.45 + corner + 7.45, 1e-12), "the right face's middle is a flat, a corner and a flat on")
check(near(centres.front, 7.45 + studioPerimeter / 2, 1e-9), "the front face's middle is half way round from the back's")
check(near(centres.left, 7.45 + studioPerimeter * 3 / 4, 1e-9), "the left face's middle is three quarters round from the back's")
let backFaceMiddle = StageMath.sample(studioPath, at: centres.back)
check(abs(backFaceMiddle.point.x) < 1e-9 && near(backFaceMiddle.point.y, -9.85, 1e-9), "the back middle lands on the back face")
let rightMiddle = StageMath.sample(studioPath, at: centres.right)
check(near(rightMiddle.point.x, 9.85, 1e-9) && abs(rightMiddle.point.y) < 1e-9, "the right middle lands on the right face")
let frontMiddle = StageMath.sample(studioPath, at: centres.front)
check(near(frontMiddle.point.y, 9.85, 1e-9) && abs(frontMiddle.point.x) < 1e-9, "the front middle lands on the front face")
let oblongPath = StageMath.roundedRectPath(width: 31.26, height: 22.12, cornerRadius: 1.0, cornerSegments: 8)
let oblong = StageMath.faceCentreDistances(width: 31.26, depth: 22.12, cornerRadius: 1.0, cornerSegments: 8)
let oblongLeft = StageMath.sample(oblongPath, at: oblong.left)
check(near(oblongLeft.point.x, -15.63, 1e-9) && abs(oblongLeft.point.y) < 1e-9, "an oblong's left middle is on the left, not at three quarters")
check(near(StageMath.arcOffset(fromFaceCentre: 3.0, across: 19.7, cornerRadius: 2.4), 3.0, 1e-12), "on the flat the arc is the offset")
check(near(StageMath.arcOffset(fromFaceCentre: -7.45, across: 19.7, cornerRadius: 2.4), -7.45, 1e-12), "the end of the flat is the end of the flat")
let intoCorner = StageMath.arcOffset(fromFaceCentre: 8.668, across: 19.7, cornerRadius: 2.4, cornerSegments: 8)
check(intoCorner > 8.668 && intoCorner < 7.45 + corner, "past the flat the outline is longer than the offset and shorter than the corner")
let cornerPoint = StageMath.sample(studioPath, at: centres.back + intoCorner)
check(near(cornerPoint.point.x, 8.668, 0.01), "and it lands at the asked x on the outline")
check(cornerPoint.point.y > -9.85 && cornerPoint.point.y < -9.4, "on the corner, not floating off the face")
check(near(StageMath.arcOffset(fromFaceCentre: 50, across: 19.7, cornerRadius: 2.4, cornerSegments: 8), 7.45 + corner, 1e-12), "past the footprint the outline stops at the corner's end")
check(near(StageMath.arcOffset(fromFaceCentre: 0.7, across: 1, cornerRadius: 0), 0.7, 1e-12), "a square corner has no arc")

// Sampling by arc length.
let middle = StageMath.sample(path, at: perimeter / 2)
check(abs(middle.distance - perimeter / 2) < 1e-9, "sample lands at the asked distance")
check(abs(simd_length(middle.normal) - 1) < 1e-9, "sampled normal is unit length")
check(StageMath.sample(path, at: -5).distance == 0, "sampling before the start clamps")
check(abs(StageMath.sample(path, at: perimeter * 2).distance - perimeter) < 1e-12,
      "sampling past the end clamps")

// Ring patterns (UX_SPEC 4.3).
let solid = StageMath.spans(for: .solid)
check(solid.count == 1 && solid[0].start == 0 && solid[0].end == 1, "solid is one span")
let segmented = StageMath.spans(for: .segmented)
check(segmented.count == 4, "a bridge member is four arcs")
let arcLength = segmented.reduce(0.0) { $0 + ($1.end - $1.start) }
check(near(arcLength, 1 - 4 * 0.09, 1e-12), "four gaps of 9 percent")
let dashed = StageMath.spans(for: .dashed)
check(dashed.count >= 4, "the drift ring has several dashes")
for span in segmented + dashed {
    check(span.start >= 0 && span.end <= 1.0000001, "spans stay inside the perimeter")
    check(span.end > span.start, "spans run forwards")
}

// The waking-ports stagger (UX_SPEC 9.2).
check(StageMath.wakeDelay(index: 0, reduceMotion: false) == .zero, "the first port wakes now")
check(StageMath.wakeDelay(index: 3, reduceMotion: false) == .milliseconds(180), "60 ms stagger")
check(StageMath.wakeDelay(index: 3, reduceMotion: true) == .zero, "Reduce Motion drops the stagger")

// The ring that closes as the work gets done (UX_SPEC S6, 9.4). Five shapes,
// one per real completed step, ending on the solid ring and on nothing else.
check(StageMath.closedGaps(step: 0, of: 5) == 0, "nothing done is the open ring")
check(
    (1...4).map { StageMath.closedGaps(step: $0, of: 5) } == [0, 1, 2, 3],
    "five steps walk the five shapes"
)
check(StageMath.closedGaps(step: 5, of: 5) == 4, "the last step is the solid ring")
check(
    (1...4).map { StageMath.closedGaps(step: $0, of: 4) } == [1, 2, 3, 4],
    "four steps close one gap each"
)
check(StageMath.closedGaps(step: 9, of: 4) == 4, "an over-run step still lands on solid")
check(StageMath.closedGaps(step: -3, of: 4) == 0, "a negative step is the open ring")
check(StageMath.closedGaps(step: 1, of: 0) == 0, "no steps at all is the open ring")
// Restore is the same map, inverted: solid to segmented, and a failed
// verification leaves it half-open (S10, R20).
check(
    (1...3).map { 4 - StageMath.closedGaps(step: $0, of: 3) } == [3, 2, 0],
    "restore re-opens the gaps"
)

// The five shapes themselves. Closing a gap merges two arcs; closing all four
// is one unbroken ring.
for closed in 0...3 {
    let spans = StageMath.spans(for: .closing(gaps: closed))
    check(spans.count == 4 - closed, "\(closed) closed leaves \(4 - closed) arcs")
    var walked = -1.0
    for span in spans {
        check(span.start > walked, "closing spans are ordered at \(closed)")
        check(span.end > span.start, "closing spans run forwards at \(closed)")
        check(span.end <= 1.0001, "closing spans stay on the perimeter at \(closed)")
        walked = span.end
    }
    let drawn = spans.reduce(0.0) { $0 + ($1.end - $1.start) }
    check(
        near(drawn, 1 - Double(4 - closed) * StageMath.segmentedGap, 1e-12),
        "\(4 - closed) gaps are left at \(closed)"
    )
}
let closedAll = StageMath.spans(for: .closing(gaps: 4))
check(closedAll.count == 1 && closedAll[0].start == 0 && closedAll[0].end == 1,
      "every gap closed is the solid ring")
check(StageMath.spans(for: .closing(gaps: 9)).count == 1, "an over-large count clamps")
// S5: the gaps widen a hair, and a hair is all.
let widenedSpans = StageMath.spans(for: .segmentedWide)
check(widenedSpans.count == 4, "the widened ring is still four arcs")
let widenedDrawn = widenedSpans.reduce(0.0) { $0 + ($1.end - $1.start) }
let segmentedDrawn = StageMath.spans(for: .segmented).reduce(0.0) { $0 + ($1.end - $1.start) }
check(widenedDrawn < segmentedDrawn, "widened gaps take more of the perimeter")
check(segmentedDrawn - widenedDrawn < 0.2, "and only a hair more")

// The breath (UX_SPEC 3.5): 1.6 s, 8 to 18 %, in phase everywhere.
for seconds in stride(from: 0.0, through: 3.2, by: 0.05) {
    let value = StageMath.breath(seconds: seconds)
    check(value >= StageMath.breathLow - 1e-12, "the breath never dips under 8 %")
    check(value <= StageMath.breathHigh + 1e-12, "the breath never rises over 18 %")
}
check(
    near(StageMath.breath(seconds: 0), StageMath.breath(seconds: StageMath.breathPeriod), 1e-12),
    "the breath is periodic at 1.6 s"
)
check(
    near(StageMath.restingBreath, (StageMath.breathLow + StageMath.breathHigh) / 2, 1e-12),
    "Reduce Motion freezes the breath at the middle of its cycle"
)
// S3's single breath has an end, and Reduce Motion never starts it.
check(near(StageMath.singleBreath(secondsSinceStart: 0, reduceMotion: false), 1, 1e-12),
      "the single breath starts at the steady ring")
check(StageMath.singleBreath(secondsSinceStart: 0.8, reduceMotion: false) < 0.5,
      "the single breath dips in the middle")
check(near(StageMath.singleBreath(secondsSinceStart: 1.6, reduceMotion: false), 1, 1e-12),
      "the single breath ends on the steady ring")
check(near(StageMath.singleBreath(secondsSinceStart: 12, reduceMotion: false), 1, 1e-12),
      "and stays there")
check(near(StageMath.singleBreath(secondsSinceStart: 0.8, reduceMotion: true), 1, 1e-12),
      "Reduce Motion is a static ring")

// The bridge ribbon (UX_SPEC 4.4). The path walks the chassis's footprint, so
// it lands on both receptacles and never passes through the machine.
let halfWidth = 19.7 / 2, halfDepth = 19.7 / 2
check(
    near(StageMath.footprintRadius(angle: .pi, halfWidth: halfWidth, halfDepth: halfDepth),
         halfDepth, 1e-12),
    "straight at the back face the outline is half the depth"
)
check(
    near(StageMath.footprintRadius(angle: .pi / 2, halfWidth: halfWidth, halfDepth: halfDepth),
         halfWidth, 1e-12),
    "straight at the right face the outline is half the width"
)
let backLeft = SIMD3(-3.0, 1.9, -halfDepth)
let backMiddle = SIMD3(-2.0, 1.9, -halfDepth)
let neighbourSpan = simd_length(backMiddle - backLeft)
let neighbourRise = StageMath.ribbonRise(span: neighbourSpan, room: (9.5 - 1.9) * 0.45)
let neighbours = StageMath.ribbonPath(
    from: backLeft, to: backMiddle, halfWidth: halfWidth, halfDepth: halfDepth,
    lift: StageMath.ribbonLift(from: backLeft, to: backMiddle), rise: neighbourRise,
    samples: 12
)
check(simd_length(neighbours.first! - backLeft) < 1e-9, "the ribbon starts on its receptacle")
check(simd_length(neighbours.last! - backMiddle) < 1e-9, "and ends on the other one")
// It arcs over whatever is between its two ends rather than through it (4.4).
let climb = neighbours.map { $0.y - backLeft.y }.max()!
check(near(climb, neighbourRise, 1e-9), "the ribbon arcs up the face between its ends")
check(climb > 0.5, "far enough to clear the ring tracks it passes over")
check(
    StageMath.ribbonRise(span: 40, room: 0.35) <= 0.35 + 1e-12,
    "a notebook's side never gets more arc than it has face"
)
check(StageMath.ribbonRise(span: 40, room: 99) <= 1.1 + 1e-12, "and the arc has a ceiling")
check(
    neighbours.allSatisfy { $0.z <= -halfDepth + 1e-9 },
    "a ribbon along the back face never sinks into it"
)
let hump = neighbours.map { -halfDepth - $0.z }.max()!
check(hump > 0.2 && hump < 1.3, "it stands a hair off the face, and only a hair")

// Back to front: the ribbon wraps a side rather than cutting through the box.
let front = SIMD3(-3.0, 1.9, halfDepth)
let around = StageMath.ribbonPath(
    from: backLeft, to: front, halfWidth: halfWidth, halfDepth: halfDepth,
    lift: StageMath.ribbonLift(from: backLeft, to: front),
    rise: StageMath.ribbonRise(
        span: simd_length(front - backLeft), room: (9.5 - 1.9) * 0.45
    ),
    samples: 48
)
for point in around {
    let outside = abs(point.x) >= halfWidth - 1e-6 || abs(point.z) >= halfDepth - 1e-6
    check(outside, "every ribbon sample stays on or outside the footprint")
}
check(around.contains { abs($0.x) > halfWidth - 1e-6 }, "it really goes round a side")

// Retraction (UX_SPEC S6, 9.3): whole at rest, gone when it has let go, and
// nothing pops at either end.
check(
    near(StageMath.ribbonSegmentOpacity(position: 0, retraction: 0), 1, 1e-12),
    "a ribbon at rest is whole at the end that will let go"
)
check(
    near(StageMath.ribbonSegmentOpacity(position: 1, retraction: 1), 0, 1e-12),
    "a fully retracted ribbon is gone"
)
for position in stride(from: 0.0, through: 1.0, by: 0.1) {
    var previous = 2.0
    for retraction in stride(from: 0.0, through: 1.0, by: 0.05) {
        let value = StageMath.ribbonSegmentOpacity(position: position, retraction: retraction)
        check(value <= previous + 1e-9, "a retracting ribbon only ever leaves")
        check(value >= -1e-9 && value <= 1 + 1e-9, "segment opacity stays in 0...1")
        previous = value
    }
}

// S4b's watching pose: between the faces, on the side the camera is nearer to.
let front0 = 0.0, back0 = Double.pi
check(near(StageMath.surveyYaw(facing: [back0], from: 0.3), back0, 1e-12),
      "one face is simply that face")
@MainActor func checkAngle(_ yaw: Double, _ expected: Double, _ what: String) {
    check(abs(StageMath.shortestAngleDelta(from: yaw, to: expected)) < 1e-9, what)
}
checkAngle(
    StageMath.surveyYaw(facing: [back0, front0], from: .pi - 0.55), .pi / 2,
    "from a back three-quarter pose the survey goes to the near side"
)
checkAngle(
    StageMath.surveyYaw(facing: [back0, front0], from: -.pi + 0.55), -.pi / 2,
    "and to the other side from the other three-quarter"
)
let sides = StageMath.surveyYaw(facing: [-.pi / 2, .pi / 2], from: 0.2)
check(abs(StageMath.shortestAngleDelta(from: sides, to: 0)) < 1e-9
      || abs(StageMath.shortestAngleDelta(from: sides, to: .pi)) < 1e-9,
      "two side faces survey from the front or the back")

// UX_SPEC S8: the ghost second Mac sits to the screen's right and the cable
// leaves the face straight out, whichever face the camera is square on to.
let rightOfFront = StageMath.screenRight(yaw: 0)
check(near(rightOfFront.x, 1) && near(rightOfFront.z, 0), "looking at the front, right is +x")
let rightOfBack = StageMath.screenRight(yaw: .pi)
check(near(rightOfBack.x, -1) && near(rightOfBack.z, 0, 1e-9), "looking at the back, right is -x")
let backNormal = StageMath.outwardNormal(yaw: .pi)
check(near(backNormal.x, 0, 1e-9) && near(backNormal.z, -1), "the back's outward normal is -z")
for yaw in stride(from: -Double.pi, through: .pi, by: 0.37) {
    check(near(simd_dot(StageMath.screenRight(yaw: yaw), StageMath.outwardNormal(yaw: yaw)), 0, 1e-9),
          "right is always perpendicular to the face normal")
    check(near(StageMath.screenRight(yaw: yaw).y, 0), "right is always level")
}
check(near(StageMath.handoffGap(extentAlongRight: 19.7, across: 27.86), 9.85 + 13.93 + 6),
      "the gap is half the ghost, half this Mac's silhouette, and the clearance")
let nearPort = SIMD3<Double>(8, 4, -9.85), farPort = SIMD3<Double>(-22, 4, -9.85)
let cable = StageMath.handoffCable(from: nearPort, to: farPort, normal: backNormal)
check(cable.count == 4, "the cable is out, across and in")
check(near(cable[0].z, -9.85 - StageMath.handoffStandoff) && near(cable[3].z, -9.85 - StageMath.handoffStandoff),
      "both ends stand off their face")
check(near(cable[1].z, cable[2].z) && near(cable[1].z, -9.85 - StageMath.handoffReach),
      "the run between the Macs is clear of both faces")
check(cable.allSatisfy { near($0.y, 4) }, "the cable stays at the ports' height")
let farEnd = StageMath.cablePoint(cable, at: 0), nearEnd = StageMath.cablePoint(cable, at: 1)
check(near(farEnd.x, cable[3].x) && near(farEnd.z, cable[3].z), "the pulse starts at the far end")
check(near(nearEnd.x, cable[0].x) && near(nearEnd.z, cable[0].z), "and ends at the near port")
let midway = StageMath.cablePoint(cable, at: 0.5)
check(near(midway.z, -9.85 - StageMath.handoffReach) && midway.x > -22 && midway.x < 8,
      "half way, the pulse is on the run between the two")
// §S8's "single thin connecting line" is one swept tube over the whole run,
// the same way §4.2's thread is: a cylinder per leg capped off at both turns.
let cableTube = StageMath.sweep(
    along: cable.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) },
    sides: 12, radius: { _ in 0.045 }
)
check(cableTube?.positions.count == cable.count * 12,
      "the cable sweeps in one piece, a vertex per sample per side")
check(cableTube?.samples == cable.count && cableTube?.sides == 12,
      "with one ring at every corner of the run and none dropped")
check(cableTube?.indices.count == (cable.count - 1) * 12 * 6,
      "and the turns are closed by triangles, not by caps")

// UX_SPEC 6.2 R2: the one thread between two ports of the same machine
// stands further off the chassis than a ribbon, never below the ring tracks
// and never so far that it leaves the machine.
let loopA = SIMD3<Double>(-6, 3.4, -9.85), loopB = SIMD3<Double>(6, 3.4, -9.85)
check(near(StageMath.loopLift(from: loopA, to: loopB), StageMath.ribbonLift(from: loopA, to: loopB) * 2, 1e-12),
      "the loop stands off at twice the ribbon's lift")
check(StageMath.loopLift(from: loopA, to: loopA + SIMD3(0.5, 0, 0)) >= 0.6, "and never under 6 mm")
check(StageMath.loopLift(from: SIMD3(-9.85, 3.4, -9.85), to: SIMD3(9.85, 3.4, 9.85)) <= 2.2,
      "and never over 2.2 cm, even back to front")

// UX_SPEC 4.2's light thread: one continuous tube, so what can be wrong
// without looking obviously wrong is the sweep's sampling.
let threadSpine = StageMath.threadPath(samples: 48)
check(threadSpine.count == 48, "the thread is sampled 48 times")
check(threadSpine[0] == SIMD3(0, 0, 0.4), "it starts just clear of the opening")
check(near(threadSpine[47].y, -7) && near(threadSpine[47].z, 10),
      "and ends where the thread fades out")
// It leaves along the receptacle's normal and droops: z leads all the way,
// y only falls, and the fall accelerates rather than running straight.
check(zip(threadSpine, threadSpine.dropFirst()).allSatisfy { $0.z < $1.z && $0.y >= $1.y },
      "the thread runs out of the face and never climbs")
let earlyDrop = threadSpine[0].y - threadSpine[8].y
let lateDrop = threadSpine[39].y - threadSpine[47].y
check(earlyDrop < lateDrop * 0.2, "it leaves along the normal before it droops")

let tube = StageMath.sweep(along: threadSpine.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) },
                           sides: 12, radius: { StageMath.threadTaper(at: $0) })
check(tube?.positions.count == 48 * 12, "the sweep makes one vertex per sample per side")
check(tube?.normals.count == 48 * 12 && tube?.coordinates.count == 48 * 12,
      "with a normal and a texture coordinate on each")
check(tube?.indices.count == 47 * 12 * 6, "and two triangles per quad between the rings")
if let tube {
    let u = stride(from: 0, to: tube.positions.count, by: 12).map { tube.coordinates[$0].x }
    check(u.first == 0 && u.last == 1, "u runs 0 to 1 along the length")
    check(zip(u, u.dropFirst()).allSatisfy { $0 < $1 }, "and only forwards")
    check(tube.coordinates[0..<12].map(\.y) == (0..<12).map { Float($0) / 12 },
          "v runs round the ring without repeating the seam")
    // Every vertex of a ring is one radius off its own centre, and the radius
    // only ever gets smaller: 4.2's "tapering gently".
    let radii = (0..<48).map { ring -> Float in
        let centre = SIMD3(Float(threadSpine[ring].x), Float(threadSpine[ring].y),
                           Float(threadSpine[ring].z))
        return (0..<12).map { simd_distance(tube.positions[ring * 12 + $0], centre) }
            .reduce(0, +) / 12
    }
    check(zip(radii, radii.dropFirst()).allSatisfy { $0 > $1 }, "the radius only tapers")
    check(abs(radii[0] - 1) < 1e-5 && abs(radii[47] - StageMath.threadTipShare) < 1e-5,
          "from full at the receptacle to a quarter of it at the far end")
    // The ring stays square to the curve, which is what keeps the tube from
    // twisting where it bends.
    let bend = 24
    let tangent = simd_normalize(SIMD3(Float(threadSpine[bend + 1].x - threadSpine[bend - 1].x),
                                       Float(threadSpine[bend + 1].y - threadSpine[bend - 1].y),
                                       Float(threadSpine[bend + 1].z - threadSpine[bend - 1].z)))
    check((0..<12).allSatisfy { abs(simd_dot(tube.normals[bend * 12 + $0], tangent)) < 1e-4 },
          "every ring normal is square to the curve")
}
// §6.2 R2's loop is the same sweep along the ribbon's path at a constant
// radius, so the polyline a chassis's outline produces has to sweep too.
let loopPath = StageMath.ribbonPath(
    from: loopA, to: loopB, halfWidth: 9.85, halfDepth: 9.85,
    lift: StageMath.loopLift(from: loopA, to: loopB),
    rise: StageMath.ribbonRise(span: simd_length(loopB - loopA), room: 3), samples: 24
)
let loopTube = StageMath.sweep(
    along: loopPath.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) },
    sides: 12, radius: { _ in 0.09 }
)
check(loopTube?.positions.count == loopPath.count * 12, "the loop sweeps along its whole path")
check(loopTube?.samples == loopPath.count && loopTube?.sides == 12,
      "and reports the rings it made")

// The fade is peak at the receptacle, gone at the end, and never climbs.
check(StageMath.threadFade(at: 0) == 1 && StageMath.threadFade(at: 1) == 0,
      "the fade runs full to nothing")
check(StageMath.threadFade(at: 0.5) < 0.5, "most of it is gone by half way")
// Degenerate spines make no tube rather than a NaN one.
check(StageMath.sweep(along: [SIMD3(0, 0, 0)], radius: { _ in 1 }) == nil, "one point is no tube")
check(StageMath.sweep(along: [SIMD3(0, 0, 0), SIMD3(0, 0, 0)], radius: { _ in 1 }) == nil,
      "and neither is the same point twice")
check(StageMath.sweep(along: [SIMD3(0, 0, 0), SIMD3(0, 0, 1)], sides: 2, radius: { _ in 1 }) == nil,
      "a ring needs three sides")

// UX_SPEC §4.8's overlays are laid out from the rig's own projection.
let eye = StageMath.orbitPosition(target: .zero, yaw: .pi, pitch: 0, radius: 0.5)
let stage = CGSize(width: 580, height: 668)
let centre = StageMath.project(
    .zero, camera: eye, target: .zero, verticalFieldOfView: fov, viewport: stage
)
check(centre.map { near($0.x, 290, 1e-6) && near($0.y, 334, 1e-6) } == true,
      "the camera's target projects to the viewport's centre")
// 5 cm up at 0.5 m: the same number pointSize gives, above the centre.
let lifted = StageMath.project(
    SIMD3(0, 0.05, 0), camera: eye, target: .zero, verticalFieldOfView: fov, viewport: stage
)
let expectedLift = StageMath.pointSize(
    metres: 0.05, distance: 0.5, viewportPoints: stage.height, fieldOfView: fov
)
check(lifted.map { near($0.x, 290, 1e-3) && near(334 - $0.y, expectedLift, 1e-3) } == true,
      "a point above the target projects straight up by its point size")
// Seen from behind (yaw pi, camera at -z), world +x is screen-left.
let aside = StageMath.project(
    SIMD3(0.05, 0, 0), camera: eye, target: .zero, verticalFieldOfView: fov, viewport: stage
)
check(aside.map { $0.x < 290 && near($0.y, 334, 1e-6) } == true,
      "from behind the machine, +x is to the left of centre")
check(StageMath.project(
        SIMD3(0, 0, -2), camera: eye, target: .zero, verticalFieldOfView: fov, viewport: stage
      ) == nil, "a point behind the camera does not project")

if failures > 0 {
    FileHandle.standardError.write(Data("test_stage_math: \(failures) failed\n".utf8))
    exit(1)
}
print("test_stage_math: all passed")
SWIFT

xcrun swiftc -swift-version 6 -warnings-as-errors -O \
  -o "$WORK_DIR/test_stage_math" \
  "$ROOT_DIR/App/Stage/StageMath.swift" "$WORK_DIR/main.swift"

"$WORK_DIR/test_stage_math"
