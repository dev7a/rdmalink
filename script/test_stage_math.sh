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
