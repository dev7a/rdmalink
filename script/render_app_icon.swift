//
//  render_app_icon.swift
//
//  Draws the app icon and writes the PNGs of App/Assets.xcassets/AppIcon.appiconset.
//
//      swift script/render_app_icon.swift App/Assets.xcassets/AppIcon.appiconset
//      swift script/render_app_icon.swift /tmp/preview     # also writes icon_1024.png
//
//  UX_SPEC §3.3, "The app icon": "on a full-bleed graphite gradient (the
//  stage's dark background, a little lighter at the top), a single Thunderbolt
//  receptacle slot centred at about a third of the icon's width, drawn as the
//  model draws it — a rounded slot with a darker interior — wearing the solid
//  accent ring of a port that is ready, with one light thread leaving it toward
//  the lower right and fading before the edge. Nothing else: no bolt, no
//  Thunderbolt mark, no text, no Mac silhouette. The artwork is a plain square;
//  the system applies the icon's shape and finish, so nothing is pre-rounded.
//  It has to read at 16 pt as a ring around a slot, which is why the slot is
//  large and alone."
//
//  So this is one drawing, in the stage's own numbers: the opening is
//  `FeatureKind.thunderbolt.opening`'s ratios, the ring is the `.ready` track
//  `StageSceneBuilder.makeReceptacle` adds around it, and the thread keeps
//  `StageMath`'s taper and fade. Every size is drawn again at its own pixel
//  count rather than resampled from the 1024, because a 16 px icon downsampled
//  from a poster is a grey smudge, and because the small sizes need a heavier
//  ring than the model's 1.5 pt track scales to (see `Art.compactness`).
//
//  CoreGraphics and ImageIO only: no AppKit, so it runs without a window
//  server, and no colour is read from the running system — the user's accent
//  colour is theirs and must not end up baked into a shipped icon.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Tones

/// The stage's own tones, resolved once and written down here rather than read
/// from the running Mac. App/Stage/StagePalette.swift resolves the first two
/// from `NSColor` in `darkAqua`; the numbers are what it gets on macOS 27.
enum Tone {
    /// `.windowBackground` in dark: the stage's graphite (30 of 255).
    static let graphite = grey(0.1176)
    /// §3.4's "very shallow radial lift", the palette's `backgroundLift` in
    /// dark — 5.5 % toward white (47 of 255). It is the top of the icon's
    /// gradient, which is where the stage's own lift sits behind the chassis.
    static let graphiteLift = grey(0.1859)

    /// §3.4: "receptacles read as holes, so the interior is the darkest thing
    /// in the scene" — `StagePalette.recess` in dark. The interior is drawn as
    /// a shallow gradient between these two rather than one flat tone, because
    /// the key light is upper-left on the model: the overhang shadows the top
    /// of the hole and the bottom of the recess catches a little of it.
    static let recessTop = grey(0.028)
    static let recessBottom = grey(0.075)

    /// The lit edge of the opening. `StagePalette.stub` (0.42 in dark) is the
    /// brightest grey the model puts near a receptacle, and the rim is that
    /// aluminium catching the key light, so it runs from a dim top edge to a
    /// bright bottom one for the same reason the interior does.
    static let rimTop = grey(0.20)
    static let rimBottom = grey(0.46)

    /// The accent, at §3.4's dark-mode step: the system's default blue
    /// (sRGB 0/122/255) blended 18 % toward white, exactly as
    /// `StagePalette.accent` brightens it against the dark IBL. The default
    /// blue and not `controlAccentColor`: an icon is a file, not a view, and
    /// it cannot follow the user's accent.
    static let accent = CGColor(srgbRed: 0.18, green: 0.5723, blue: 1.0, alpha: 1)

    /// §4.2's thread is the `.secondary` ink, which in dark is near-white.
    static let thread = grey(0.96)

    static func grey(_ value: Double) -> CGColor {
        CGColor(srgbRed: value, green: value, blue: value, alpha: 1)
    }

    static func with(_ color: CGColor, alpha: Double) -> CGColor {
        color.copy(alpha: alpha) ?? color
    }
}

/// `t` of the way from one tone to the other, in sRGB, which is where both the
/// palette and the eye are.
func interpolate(_ from: CGColor, _ to: CGColor, _ t: Double) -> CGColor {
    let a = from.components ?? [0, 0, 0, 1]
    let b = to.components ?? [0, 0, 0, 1]
    return CGColor(
        srgbRed: a[0] + (b[0] - a[0]) * t,
        green: a[1] + (b[1] - a[1]) * t,
        blue: a[2] + (b[2] - a[2]) * t,
        alpha: 1
    )
}

// MARK: - Geometry

/// Where everything sits, for one pixel size. Fractions of the canvas, so the
/// drawing is the same drawing at every size — except where `compactness` says
/// otherwise.
struct Art {
    /// The canvas, in pixels.
    let pixels: Double
    /// How big the icon is *shown*, in points. Not the same thing: 16 pt on a
    /// Retina screen is a 32 px file, and it is still a 16 pt icon.
    let points: Double

    /// 0 from 96 pt up, 1 at 16 pt: how far this size is into "too small to
    /// draw the model's proportions".
    ///
    /// §3.3 asks the icon to still read at 16 pt as a ring around a slot. The
    /// model's ready track is 0.09 cm on a 0.95 cm opening, which at 16 pt is
    /// a fifth of a point of ring around a slot two points tall — a blue-grey
    /// pill. So the small sizes keep the same drawing with the slot opened out
    /// and the ring thickened, faded in by size so 32 pt and 64 pt are not two
    /// different icons.
    ///
    /// It is read off the **point** size, so 16 pt @2x is the 16 pt drawing
    /// with twice the resolution rather than the 32 pt one: the two are the
    /// same number of pixels and a different icon.
    var compactness: Double { min(max((96 - points) / (96 - 16), 0), 1) }

    private func lerp(_ full: Double, _ compact: Double) -> Double {
        full + (compact - full) * compactness
    }

    /// §3.3: "centred at about a third of the icon's width". A shade over a
    /// third, because the system does not show the square: it scales the
    /// artwork into the icon's shape with a margin all round, and a slot at
    /// exactly 0.33 comes out small inside that.
    var slotWidth: Double { pixels * lerp(0.36, 0.42) }

    /// `FeatureKind.thunderbolt.opening`: 0.95 × 0.35 cm with a 0.17 cm corner
    /// — a slot a hair short of a stadium. The icon keeps the catalogue's two
    /// ratios exactly, so it is the hole the model cuts and not a lozenge.
    var slotHeight: Double { slotWidth * (0.35 / 0.95) }
    var slotCorner: Double { slotWidth * (0.17 / 0.95) }

    /// `StageSceneBuilder.makeReceptacle` adds the `.ready` ring at
    /// `grow: 0.50, thickness: 0.09` around that opening, with the corner
    /// radius grown by half the growth. Both extents grow by the same
    /// centimetre, which is what makes the ring a stadium around a slot.
    var ringGrow: Double { slotWidth * lerp(0.50 / 0.95, 0.80) }
    var ringWidth: Double { slotWidth + ringGrow }
    var ringHeight: Double { slotHeight + ringGrow }
    var ringCorner: Double { slotCorner + ringGrow / 2 }

    /// The ready track's thickness, with a floor of one and a half pixels:
    /// below that an anti-aliased ring is a smear with no hole in it.
    var ringThickness: Double { max(slotWidth * lerp(0.09 / 0.95, 0.21), 1.5) }

    /// The opening's own lit edge. A hairline on the model (the shell's
    /// chamfer), so it is a hairline here, floored so it survives at 16 px.
    var rimThickness: Double { max(slotHeight * 0.085, 0.7) }

    /// §4.3's bloom behind a ready receptacle is the ring's shape grown by
    /// 1.6 cm; here it is that spread as two shadow passes, a tight halo that
    /// makes the ring glow and a wide one that lifts the graphite behind it.
    /// The small sizes take less of both: a bloom 0.85 slot-widths wide is
    /// a fifth of a 16 px tile, and a halo that size stops being light around
    /// the ring and becomes a blue tile with a hole in it.
    var glowBlur: Double { slotWidth * lerp(0.22, 0.12) }
    var bloomBlur: Double { slotWidth * lerp(0.85, 0.30) }

    /// §4.2's light thread, in multiples of the slot's width from the slot's
    /// centre, with the icon's own length: the model's curve is ten
    /// centimetres of cable leaving a one-centimetre port, which on a square
    /// would run three canvases past the corner. What is kept is its shape —
    /// it leaves the mouth flat, sags, and is gone before the edge.
    ///
    /// The first point is *inside* the slot, so the tube has no visible start
    /// cap: the thread reads as light coming out of the hole.
    var threadSpine: [CGPoint] {
        [
            CGPoint(x: 0.36, y: 0.00),
            CGPoint(x: 0.92, y: 0.05),
            CGPoint(x: 1.18, y: 0.55),
            CGPoint(x: 1.20, y: 1.05),
        ].map { CGPoint(x: $0.x * slotWidth, y: $0.y * slotWidth) }
    }

    /// The thread's radius where it leaves the receptacle. `StageMesh`'s
    /// 0.09 cm on a 0.95 cm opening is a tube half as tall as the slot; it
    /// reads that way on a lit metal face seen at a slant, and head-on at
    /// icon scale it reads as a worm, so the icon draws a thinner one and
    /// keeps the taper and the fade, which are what make it light.
    var threadRadius: Double { slotHeight * 0.16 }

    /// How much of the thread is drawn at this size. At 16 px it is two grey
    /// pixels inside the mouth, which reads as dirt in the hole rather than
    /// as light, and §3.3 asks only that the small sizes read as a ring around
    /// a slot — so it leaves on the same `compactness` that opens the slot
    /// out, and the ring it leaves behind is the whole subject.
    var threadPresence: Double { 1 - compactness }

    /// `StageMath.threadTipShare`: what is left of the radius at the far end.
    static let threadTipShare = 0.25
    /// `StageMesh.threadPeakOpacity`, a step up: the model's 0.35 is ink over
    /// lit aluminium, and this is ink over 30-of-255 graphite.
    static let threadPeakOpacity = 0.5

    /// `StageMath.threadTaper(at:)`, straight, so the silhouette has no kink.
    static func threadTaper(at u: Double) -> Double {
        1 - (1 - threadTipShare) * min(max(u, 0), 1)
    }

    /// `StageMath.threadFade(at:)`, squared, so most of the fall happens over
    /// the second half and the thread reads as light leaving rather than as a
    /// rod dimmed evenly.
    static func threadFade(at u: Double) -> Double {
        let left = 1 - min(max(u, 0), 1)
        return left * left
    }

    var centre: CGPoint { CGPoint(x: pixels / 2, y: pixels / 2) }
}

// MARK: - Drawing

/// A rounded rectangle centred on `centre`, with the radius clamped the way
/// `CGPath` clamps it, so a stadium stays a stadium.
func slotPath(centre: CGPoint, width: Double, height: Double, corner: Double) -> CGPath {
    let rect = CGRect(
        x: centre.x - width / 2, y: centre.y - height / 2, width: width, height: height
    )
    let radius = min(corner, min(width, height) / 2)
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Samples a cubic Bézier, the same four-point form `StageMath.threadPath`
/// uses.
func bezier(_ points: [CGPoint], samples: Int) -> [CGPoint] {
    (0..<samples).map { step in
        let t = Double(step) / Double(samples - 1)
        let i = 1 - t
        let x = i * i * i * points[0].x + 3 * i * i * t * points[1].x
            + 3 * i * t * t * points[2].x + t * t * t * points[3].x
        let y = i * i * i * points[0].y + 3 * i * i * t * points[1].y
            + 3 * i * t * t * points[2].y + t * t * t * points[3].y
        return CGPoint(x: x, y: y)
    }
}

/// The tapering tube of §4.2, as **one** closed outline: up one side of the
/// curve and back down the other. One shape and one gradient, because the spec
/// asks for "one continuous tube … never a chain of visible segments", and a
/// stack of short quads at stepped opacities has a seam at every joint.
func tubeOutline(spine: [CGPoint], radius: (Double) -> Double) -> CGPath {
    var left: [CGPoint] = []
    var right: [CGPoint] = []
    var head = (centre: CGPoint.zero, radius: 0.0, from: 0.0, to: 0.0)
    for (index, point) in spine.enumerated() {
        // The tangent at an interior point is the chord across it, so the
        // offset is square to the curve and not to one of its two legs.
        let previous = spine[max(index - 1, 0)]
        let next = spine[min(index + 1, spine.count - 1)]
        var tangent = CGVector(dx: next.x - previous.x, dy: next.y - previous.y)
        let length = (tangent.dx * tangent.dx + tangent.dy * tangent.dy).squareRoot()
        guard length > 1e-9 else { continue }
        tangent = CGVector(dx: tangent.dx / length, dy: tangent.dy / length)
        let r = radius(Double(index) / Double(spine.count - 1))
        let normal = CGVector(dx: -tangent.dy * r, dy: tangent.dx * r)
        left.append(CGPoint(x: point.x + normal.dx, y: point.y + normal.dy))
        right.append(CGPoint(x: point.x - normal.dx, y: point.y - normal.dy))
        if left.count == 1 {
            head = (
                point, r, atan2(-normal.dy, -normal.dx), atan2(normal.dy, normal.dx)
            )
        }
    }

    let path = CGMutablePath()
    guard let first = left.first else { return path }
    path.move(to: first)
    for point in left.dropFirst() { path.addLine(to: point) }
    for point in right.reversed() { path.addLine(to: point) }
    // The head is a half-round, not the flat cut a straight close would
    // leave: the thread's first millimetre is inside the dark slot, and a
    // blunt end there reads as something *in* the hole rather than as light
    // coming out of it. Clockwise, which is the half turn that goes round
    // the back of the head rather than across the tube.
    path.addArc(
        center: head.centre, radius: CGFloat(head.radius),
        startAngle: CGFloat(head.from), endAngle: CGFloat(head.to), clockwise: true
    )
    path.closeSubpath()
    return path
}

/// One icon, drawn at its own pixel size for the point size it is shown at.
func render(points: Int, scale: Int) -> CGImage? {
    let pixels = points * scale
    let art = Art(pixels: Double(pixels), points: Double(points))
    let size = Double(pixels)

    // No alpha: §3.3's "the artwork is a plain square", and a full-bleed
    // gradient has nothing to be transparent. The system rounds it.
    guard
        let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
            bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
    else { return nil }
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // --- the graphite ------------------------------------------------------
    // A row at a time rather than a `CGGradient`, because CoreGraphics dithers
    // a gradient and the noise is what a PNG cannot compress: measured at
    // 1024 px, the dithered ramp is 156 KB and the exact rows are 16 KB, for a
    // ramp that only ever crosses seventeen levels of grey between 30 and 47
    // and so has nothing to dither away.
    for row in 0..<pixels {
        let t = pixels > 1 ? Double(row) / Double(pixels - 1) : 0
        context.setFillColor(interpolate(Tone.graphite, Tone.graphiteLift, t))
        context.fill(CGRect(x: 0, y: Double(row), width: size, height: 1))
    }

    let centre = art.centre
    let slot = slotPath(
        centre: centre, width: art.slotWidth, height: art.slotHeight, corner: art.slotCorner
    )
    let ring = slotPath(
        centre: centre, width: art.ringWidth, height: art.ringHeight, corner: art.ringCorner
    )

    // --- the ring's bloom and glow, behind everything it lights ------------
    // Two shadow passes and then the ring itself: the wide one is §4.3's
    // bloom, the tight one is the halo a lit ring has. Both are painted by
    // stroking the ring, so the stroke drawn last covers the two beneath it.
    for (blur, alpha) in [(art.bloomBlur, 0.30), (art.glowBlur, 0.60)] {
        context.saveGState()
        context.setShadow(
            offset: .zero, blur: CGFloat(blur), color: Tone.with(Tone.accent, alpha: alpha)
        )
        context.setStrokeColor(Tone.accent)
        context.setLineWidth(CGFloat(art.ringThickness))
        context.addPath(ring)
        context.strokePath()
        context.restoreGState()
    }

    // --- the ready ring ----------------------------------------------------
    context.setStrokeColor(Tone.accent)
    context.setLineWidth(CGFloat(art.ringThickness))
    context.addPath(ring)
    context.strokePath()

    // --- the thread --------------------------------------------------------
    // Over the ring, because on the model the thread leaves the face 0.4 cm in
    // front of every ring track: the light passes over the ring on its way out.
    drawThread(in: context, art: art, space: space)

    // --- the slot ----------------------------------------------------------
    // §3.4: "a true inset slot with a darker interior, so an unlit port reads
    // as a hole and not a sticker."
    //
    // Painted *after* the thread, which is why the thread's spine starts
    // inside the opening: the interior covers its head, so the light comes out
    // from under the slot's own edge with no cap and no seam. A tapering tube
    // whose thick end is drawn on top of the hole is a tadpole in the port.
    context.saveGState()
    context.addPath(slot)
    context.clip()
    if let interior = CGGradient(
        colorsSpace: space, colors: [Tone.recessBottom, Tone.recessTop] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            interior,
            start: CGPoint(x: 0, y: centre.y - art.slotHeight / 2),
            end: CGPoint(x: 0, y: centre.y + art.slotHeight / 2),
            options: []
        )
    }
    context.restoreGState()

    // The lit edge, drawn as a stroked path filled with its own gradient: a
    // stroke colour cannot vary along the outline, and a rim that is the same
    // brightness top and bottom does not read as an edge at all.
    context.saveGState()
    context.addPath(slot)
    context.setLineWidth(CGFloat(art.rimThickness))
    context.replacePathWithStrokedPath()
    context.clip()
    if let rim = CGGradient(
        colorsSpace: space, colors: [Tone.rimBottom, Tone.rimTop] as CFArray, locations: [0, 1]
    ) {
        context.drawLinearGradient(
            rim,
            start: CGPoint(x: 0, y: centre.y - art.slotHeight / 2 - art.rimThickness),
            end: CGPoint(x: 0, y: centre.y + art.slotHeight / 2 + art.rimThickness),
            options: []
        )
    }
    context.restoreGState()

    return context.makeImage()
}

/// §4.2's thread: one outline, filled with one gradient whose stops are the
/// model's own fade sampled along the curve.
func drawThread(in context: CGContext, art: Art, space: CGColorSpace) {
    let samples = 96
    let centre = art.centre
    // The spine is in the slot's frame, with `y` running down the icon toward
    // the lower right; the context's `y` runs up.
    let spine = bezier(art.threadSpine, samples: samples).map {
        CGPoint(x: centre.x + $0.x, y: centre.y - $0.y)
    }
    let outline = tubeOutline(spine: spine) { art.threadRadius * Art.threadTaper(at: $0) }

    // The fade runs along the curve, and a `CGGradient` runs along a line, so
    // the line is the chord from the first sample to the last and each stop is
    // placed where its sample projects onto it. The curve turns by about 45°
    // end to end, so the projection stays monotonic and the error stays
    // inside the width of the tube.
    guard let start = spine.first, let end = spine.last else { return }
    let chord = CGVector(dx: end.x - start.x, dy: end.y - start.y)
    let chordLength = (chord.dx * chord.dx + chord.dy * chord.dy).squareRoot()
    guard chordLength > 1e-9 else { return }

    var colors: [CGColor] = []
    var locations: [CGFloat] = []
    let stops = 32
    for step in 0...stops {
        let u = Double(step) / Double(stops)
        let index = min(Int((Double(samples - 1) * u).rounded()), samples - 1)
        let point = spine[index]
        let projection =
            ((point.x - start.x) * chord.dx + (point.y - start.y) * chord.dy)
            / (chordLength * chordLength)
        let location = CGFloat(min(max(projection, 0), 1))
        colors.append(
            Tone.with(
                Tone.thread,
                alpha: Art.threadPeakOpacity * Art.threadFade(at: u) * art.threadPresence
            )
        )
        // A `CGGradient`'s locations have to be non-decreasing.
        locations.append(max(location, locations.last ?? 0))
    }

    guard
        let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)
    else { return }
    context.saveGState()
    context.addPath(outline)
    context.clip()
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
    context.restoreGState()
}

// MARK: - Writing

func write(_ image: CGImage, to url: URL) throws {
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        )
    else { throw Failure("could not write \(url.lastPathComponent)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw Failure("could not encode \(url.lastPathComponent)")
    }
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// The ten entries macOS wants, as (point size, scale). Every one is drawn at
/// its own pixel count and for its own point size, so nothing here is ever a
/// resample of a bigger file. The pairs that agree on both — 128 pt @2x and
/// 256 pt @1x, say, which are both 256 px of the full drawing — are drawn once
/// and written twice.
let catalogue: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

func filename(points: Int, scale: Int) -> String {
    "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(
        Data("usage: swift script/render_app_icon.swift <out-dir>\n".utf8)
    )
    exit(2)
}
let outDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)

/// Drawn once per distinct (pixels, points) pair.
struct Drawing: Hashable {
    var pixels: Int
    var points: Int
}

var images: [Drawing: CGImage] = [:]
var poster: CGImage?
for (points, scale) in catalogue {
    let drawing = Drawing(pixels: points * scale, points: min(points, 96))
    if images[drawing] == nil {
        guard let image = render(points: points, scale: scale) else {
            throw Failure("could not draw the icon at \(drawing.pixels) px")
        }
        images[drawing] = image
    }
    let image = images[drawing]!
    if drawing.pixels == 1024 { poster = image }
    try write(image, to: outDirectory.appendingPathComponent(filename(points: points, scale: scale)))
}

// The 1024 for looking at, next to the catalogue rather than inside it: a file
// in an `.appiconset` that `Contents.json` does not name is an unassigned
// child, and `actool` warns about it on every build.
if outDirectory.pathExtension != "appiconset", let poster {
    try write(poster, to: outDirectory.appendingPathComponent("icon_1024.png"))
}

// The catalogue's index, written here so the whole `.appiconset` has one
// source: a hand-edited `Contents.json` and a generated set of PNGs drift.
let entries = catalogue.map { points, scale in
    """
        {
          "filename" : "\(filename(points: points, scale: scale))",
          "idiom" : "mac",
          "scale" : "\(scale)x",
          "size" : "\(points)x\(points)"
        }
    """
}
let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contents.write(
    to: outDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8
)

print("render_app_icon: wrote \(catalogue.count) PNGs and Contents.json to \(outDirectory.path)")
