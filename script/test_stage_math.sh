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
