//
//  render_app_icon.swift
//
//  Draws the app icon and writes the PNGs of App/Assets.xcassets/AppIcon.appiconset.
//
//      swift script/render_app_icon.swift App/Assets.xcassets/AppIcon.appiconset
//      swift script/render_app_icon.swift /tmp/preview     # also writes icon_1024.png
//
//  UX_SPEC §3.3, "The app icon": "One drawing, a link seen head-on: on a
//  full-bleed graphite gradient (the stage's dark background, a little lighter
//  at the top), two closed metal plug ends face each other across the middle
//  of the icon, left and right, each about a quarter of the icon wide — a dark
//  chamfered block with a rounded back and a thin lit rim on its facing end,
//  drawn in the stage's chassis tones, with no opening in it. Between the rims
//  runs one straight beam of accent light, level, thick, brightest at its core
//  and glowing softly at its edges, carrying three small brighter marks along
//  its length like packets in flight. Nothing else: no bolt, no Thunderbolt
//  mark, no ring, no receptacle opening, no text, no Mac silhouette. The
//  artwork is a plain square; the system applies the icon's shape and finish,
//  so nothing is pre-rounded. It has to read at 16 pt as two dark blocks and
//  one blue bar, which is why the plugs are large and the beam is thick; the
//  packet marks may drop out at small sizes."
//
//  So the drawing is three ideas and no fourth one: a plug end, a plug end,
//  and the light between them. Everything below is either the shape of a plug
//  end, the shape of the beam, or the stage's own lighting applied to one of
//  the two. There is no hole anywhere in it — a plug end is closed, the rim is
//  a filled edge of light and never an opening, and the spec's "no receptacle
//  opening" is the point of the whole composition.
//
//  Each of the two subjects is *lit* rather than filled flat, because a flat
//  fill of either reads as a sticker:
//
//    · a plug end is drawn as a shell, not a silhouette — an outer octagon
//      filled with the chamfer's own steep ramp, an inner octagon inset by the
//      bevel filled with the body's gentler one, a dark contact line along the
//      base and a specular hairline along the top edge. The chamfer facets
//      come out lighter than the front face where the key lands on them and
//      darker underneath, which is what a milled corner does.
//
//    · the beam is drawn as light, not as a stripe — a shaped bloom that
//      fades over about one beam-height into the graphite above and below it,
//      a body that ramps from the accent at its two edges to a brighter core
//      on the centre line, and a lens over the middle of the span that takes
//      that core up to near-white where the run is furthest from either plug.
//
//  Every size is drawn again at its own pixel count rather than resampled from
//  the 1024, because a 16 px icon downsampled from a poster is a grey smudge,
//  and because at 16 pt the beam, the rims and the plugs' lighting have to be
//  heavier than a scaled-down poster would make them (see `Art.compactness`).
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

    // MARK: The plug's metal
    //
    // One family of greys, all of them the same aluminium under §3.4's single
    // key from the upper left, and the icon uses the whole of it rather than a
    // slice: `StagePalette.chassis` is 0.78 albedo, which under the stage's
    // dark IBL renders anywhere from 35 of 255 in shadow to a specular pick-up
    // on a turned edge (measured along the Mac Studio's rows, see
    // `StagePalette.ink`). A drawing that used only the middle of that range
    // came out as a flat cut-out, which is what these seven tones are here to
    // stop.

    /// The front face, base to top. Lifted about twenty levels off the metal's
    /// own shadow value, which is as dark as §3.3's "dark chassis tones" can go
    /// and still be a block: the background runs 30 to 47 of 255, and a base at
    /// the metal's own 35 put the bottom of the plug within one level of the
    /// graphite behind it — measured down a column at 512 px, 36 against 35,
    /// with the lower third of the plug simply gone.
    static let chassisBase = grey(0.205)
    /// The ramp's middle, placed above the block's own middle by
    /// `Art.chassisMidStop`. Anodised aluminium under a single high key does
    /// not brighten evenly from base to top: it stays dark through most of its
    /// height and then runs up quickly into the top face.
    static let chassisMid = grey(0.28)
    static let chassisTop = grey(0.45)

    /// The chamfer band, base to top. A cut corner is a facet turned away from
    /// the front face: the top ones tip toward the key and pick up much more of
    /// it than the face does, the bottom ones tip away and go darker than the
    /// graphite behind them. The same metal, a steeper ramp — which is the
    /// whole difference between a chamfer and a rounded rectangle.
    static let bevelBase = grey(0.075)
    static let bevelMid = grey(0.30)
    static let bevelTop = grey(0.66)

    /// The specular hairline along the top edge, and the contact line under the
    /// base. The first is the key caught on the turned edge of the shell; the
    /// second is the shadow the body sits in, and it is darker than the
    /// graphite because a contact shadow always is.
    static let specular = grey(0.90)
    static let contact = grey(0.075)

    // MARK: The light

    /// The accent, at §3.4's dark-mode step: the system's default blue
    /// (sRGB 0/122/255) blended 18 % toward white, exactly as
    /// `StagePalette.accent` brightens it against the dark IBL. The default
    /// blue and not `controlAccentColor`: an icon is a file, not a view, and it
    /// cannot follow the user's accent. This is the beam at its two edges, and
    /// the colour the whole bloom is made of.
    static let accent = CGColor(srgbRed: 0.18, green: 0.5723, blue: 1.0, alpha: 1)

    /// The core: the accent 42 % toward white, on the beam's centre line.
    static let accentCore = CGColor(srgbRed: 0.5244, green: 0.7519, blue: 1.0, alpha: 1)

    /// The lens: 72 % toward white. It is laid over the middle of the span
    /// only, so the beam is brightest where it is furthest from either plug —
    /// which is how a length of lit glass looks and how a flat stripe does not.
    static let accentGlare = CGColor(srgbRed: 0.7704, green: 0.8803, blue: 1.0, alpha: 1)

    /// The packets: 92 % toward white, brighter than anything else inside the
    /// beam, because §3.3 calls them the brighter marks and they have to win
    /// over the lens they cross in the middle of the run.
    static let accentSpark = CGColor(srgbRed: 0.9344, green: 0.9658, blue: 1.0, alpha: 1)

    /// The lit rim on the plug's face. Cyan-white rather than the beam's blue:
    /// it is the source and the beam is what it emits, and a source drawn in
    /// the colour of its own light reads as a piece of the beam stuck to the
    /// metal. The shift is small enough to stay the same light.
    static let rimEdge = CGColor(srgbRed: 0.80, green: 0.97, blue: 1.0, alpha: 1)

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

/// One plug end, fully resolved: the octagon-ish side view of a machined shell,
/// with a flat front face, a 45° chamfer off each of its four corners and a
/// turned back. `facing` is +1 for the plug on the left, whose face looks right
/// into the beam, and -1 for the one on the right, so the pair is one
/// description used twice and the two halves of the icon cannot drift apart.
struct Plug {
    /// The outer end, nearest the edge of the square.
    let backX: Double
    /// The flat front face: where the rim sits and the beam starts.
    let faceX: Double
    let centreY: Double
    let facing: Double
    /// Half the body's height, and half the front face's — the difference
    /// between them is the chamfer.
    let half: Double
    let faceHalf: Double
    /// The radius the back is turned to.
    let corner: Double

    var top: Double { centreY + half }
    var bottom: Double { centreY - half }
    /// One chamfer back from the face: where the cut meets the long edges.
    var shoulder: Double { faceX - facing * (half - faceHalf) }

    /// The same shell, every face moved `bevel` inward: the front of the plug,
    /// with the chamfer band left showing between this and the outline.
    ///
    /// `faceHalf` is not simply `faceHalf - bevel`. Offsetting a 45° cut inward
    /// by `bevel` moves where it meets the face by `bevel × (√2 − 1)`, and
    /// using the wrong one here puts a visible kink in the band at each of the
    /// four corners.
    func inset(by bevel: Double) -> Plug {
        Plug(
            backX: backX + facing * bevel,
            faceX: faceX - facing * bevel,
            centreY: centreY,
            facing: facing,
            half: max(half - bevel, 0.5),
            faceHalf: max(faceHalf - bevel * (2.0.squareRoot() - 1), 0.5),
            corner: max(corner - bevel, 0)
        )
    }
}

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
    /// draw the poster's proportions".
    ///
    /// §3.3 asks the icon to still read at 16 pt as two dark blocks and one
    /// blue bar. The beam at its full 12 % is under two pixels there, which is
    /// an anti-aliased smear rather than a bar, and the plugs' lighting ramp
    /// costs more levels than a seven-pixel block has to spend. So the small
    /// sizes keep the same composition, drawn with the beam thickened, its
    /// bloom pulled in, the rims widened and the plugs' lighting flattened, all
    /// faded in by size so 32 pt and 64 pt are not two different icons.
    ///
    /// It is read off the **point** size, so 16 pt @2x is the 16 pt drawing
    /// with twice the resolution rather than the 32 pt one: the two are the
    /// same number of pixels and a different icon.
    var compactness: Double { min(max((96 - points) / (96 - 16), 0), 1) }

    private func lerp(_ full: Double, _ compact: Double) -> Double {
        full + (compact - full) * compactness
    }

    // MARK: The two plug ends

    /// The gap between a plug's back and the edge of the square. The system
    /// does not show the square: it scales the artwork into the icon's shape,
    /// and that shape cuts the corners. Both plugs sit on the icon's horizontal
    /// centre line, which is the one place that shape is at its full width, so
    /// this margin is breathing room rather than clearance, and it is kept
    /// tight so the pair fills the icon. The same fraction at every size: the
    /// icon's shape is the same shape at every size, so the room to leave for
    /// it does not change either.
    var margin: Double { pixels * 0.04 }

    /// §3.3: "each about a quarter of the icon wide", taken at the generous end
    /// of "about" so the two ends are the mass of the drawing and the run
    /// between them still reads as a span. The same fraction at every size:
    /// a plug that grew sideways at the small sizes would take the width out of
    /// the beam's run, which is the one measurement here with nowhere to go.
    var plugWidth: Double { pixels * 0.28 }

    /// A third of the square at the sizes with pixels to spare, and getting on
    /// for half at the small ones. §3.3 says the plugs are large on purpose —
    /// "which is why the plugs are large and the beam is thick" — and a plug
    /// end this narrow has to buy its presence in height.
    ///
    /// This is the one part of the *composition* that moves with `compactness`,
    /// and it moves because height is the one thing that costs the drawing
    /// nothing: a taller plug takes no part of the beam's run, which is
    /// horizontal. At 16 pt it is the difference between two blocks holding a
    /// bar and one stripe with dark ends — six pixels against a three-pixel bar
    /// is not enough, eight is. It does not grow past that, because a plug much
    /// taller than this stops being a plug end and becomes a dumbbell weight.
    var plugHeight: Double { pixels * lerp(0.32, 0.46) }

    /// The 45° cut off each of the four corners, as a share of the height.
    ///
    /// Two fifths, which is a big cut: a timid chamfer renders as a rounded
    /// rectangle, and two rounded rectangles either side of a bar read as a
    /// spool rather than as two plug ends. It closes up at the small sizes,
    /// where two fifths of a seven-pixel block is the whole nose and the rim
    /// would have nothing left to sit on.
    var chamferShare: Double { lerp(0.42, 0.24) }

    /// §3.3's "rounded back": the outer end is turned, not cut. Generous enough
    /// that the bevel band curving round it reads as a body with a round back
    /// rather than as a flat card, and short of the half-height, where the back
    /// would become a capsule end and the plug would lose the straight run that
    /// says it is machined. The asymmetry — a turned back, a cut nose — is what
    /// says which way the plug points.
    var backCorner: Double { plugHeight / 2 * 0.28 }

    /// The flat front face: the body less the two chamfers.
    var faceHeight: Double { plugHeight * (1 - chamferShare) }

    /// How wide the chamfer band is drawn: the distance the front face is inset
    /// from the outline, and so the width of the lit facet along the top and
    /// the dark one along the base. Floored so the band is still a band at
    /// 16 px, and clamped below against the plug's own size so the inset shell
    /// can never turn itself inside out.
    var bevel: Double {
        let wanted = max(pixels * lerp(0.021, 0.030), 0.9)
        return min(wanted, plugWidth * 0.28, plugHeight * 0.20)
    }

    /// The specular hairline along the top edge, and the contact line under the
    /// base. Both are strokes on the outline, faded out along the height by the
    /// gradients in `draw(plug:…)`, and both are floored so they survive 16 px.
    var specularThickness: Double { max(pixels * 0.006, 0.7) }
    var contactThickness: Double { max(pixels * 0.009, 0.8) }

    /// How much of §3.4's light survives on a plug at this size.
    ///
    /// At 16 pt a plug is seven pixels tall and the full ramp costs two of
    /// them: the shaded base lands within a few levels of the graphite, and a
    /// block whose lower edge is the same tone as the background is not a block
    /// any more. So the fall closes up toward the lit tone as the sizes shrink,
    /// which is the same trade the beam makes when it thickens — the small
    /// sizes keep the subject and give up the modelling.
    var lightFalloff: Double { lerp(1.0, 0.50) }

    /// How far up the block `Tone.chassisMid` sits: past halfway, so the dark
    /// two thirds is the body and the light third is the top face turning
    /// toward the key. The chamfer band's own middle sits lower, because a
    /// facet turns through its whole range over a much shorter run.
    static let chassisMidStop = 0.70
    static let bevelMidStop = 0.52

    /// The front face — base, middle and top — and the chamfer band's three.
    /// The lit ends are the tones themselves at every size (a shell reads from
    /// the faces the key lands on); the dark ones are what close up.
    var chassisTop: CGColor { Tone.chassisTop }
    var chassisMid: CGColor { interpolate(Tone.chassisTop, Tone.chassisMid, lightFalloff) }
    var chassisBase: CGColor { interpolate(Tone.chassisTop, Tone.chassisBase, lightFalloff) }
    /// The lit facet and the specular both close up toward the front face as
    /// the sizes shrink. At 16 pt a plug is seven rows and its top row *is* the
    /// specular: left at full strength it came out at 189 of 255, a white cap
    /// on each block and very nearly as bright as the bar the two blocks exist
    /// to frame.
    var bevelTop: CGColor { interpolate(Tone.chassisTop, Tone.bevelTop, lerp(1.0, 0.55)) }
    var specular: CGColor { interpolate(Tone.chassisTop, Tone.specular, lerp(1.0, 0.30)) }
    var bevelMid: CGColor { interpolate(Tone.bevelTop, Tone.bevelMid, lightFalloff) }
    var bevelBase: CGColor { interpolate(Tone.bevelMid, Tone.bevelBase, lightFalloff) }

    /// How far down from the top edge the specular fades out, and how far up
    /// from the base the contact line does, as shares of the plug's height.
    /// Short runs, both of them: a highlight that reaches the middle of a block
    /// is a gradient, not a highlight.
    static let specularReach = 0.22
    static let contactReach = 0.28

    /// The two plug ends, in the context's coordinates, which run up. Both are
    /// centred on the icon's horizontal middle and pushed out to their own side
    /// by the margin, because what is left between their faces is the length of
    /// the beam.
    var plugs: (left: Plug, right: Plug) {
        let half = plugHeight / 2
        let faceHalf = faceHeight / 2
        func plug(backX: Double, facing: Double) -> Plug {
            Plug(
                backX: backX, faceX: backX + facing * plugWidth, centreY: pixels / 2,
                facing: facing, half: half, faceHalf: faceHalf, corner: min(backCorner, half)
            )
        }
        return (plug(backX: margin, facing: 1), plug(backX: pixels - margin, facing: -1))
    }

    // MARK: The beam

    /// §3.3's beam, level and centred on the same middle line the plugs are.
    /// The run left over between the two faces is 1 − 2 × (margin + plug),
    /// which at the fractions above is a little over a third of the square.
    var beamStartX: Double { plugs.left.faceX }
    var beamEndX: Double { plugs.right.faceX }
    var beamLength: Double { beamEndX - beamStartX }
    var beamCentreY: Double { pixels / 2 }

    /// §3.3: "thick". 12 % of the square at the sizes that have the pixels for
    /// it, opening out to a fifth at 16 pt, where three anti-aliased rows are
    /// the difference between a blue bar and a blue smear — and where the bar
    /// is the only thing carrying the icon's colour.
    var beamHeight: Double { max(pixels * lerp(0.12, 0.185), 1.0) }

    /// Where the core sits across the beam's thickness, as the middle stop of
    /// the body's gradient: §3.3's "brightest at its core" is one smooth ramp
    /// from the accent at the two edges to `Tone.accentCore` on the centre
    /// line. Banded stripes were tried first and read as a ribbon with rails
    /// down it; a ramp reads as light.
    static let beamCoreStop = 0.5

    /// How far toward `Tone.accentCore` the centre line actually goes at this
    /// size. At 16 pt the beam is three rows: the whole ramp from the accent to
    /// the core and back lands on them, and at full strength §3.3's "one blue
    /// bar" comes out as a pale one with two blue hairlines. So the core, like
    /// everything else here, gives up range as the rows run out.
    var beamCore: CGColor { interpolate(Tone.accent, Tone.accentCore, lerp(1.0, 0.55)) }

    // MARK: The bloom

    /// §3.3's "glowing softly at its edges". How far the bloom reaches past the
    /// beam's own edge: about one beam-height at the sizes that can carry it,
    /// so the beam visibly lights the graphite above and below itself instead
    /// of sitting on it. It is pulled in at the small sizes, because one
    /// beam-height at 16 pt is a third of the tile and the bloom would swallow
    /// the two blocks it is supposed to be lighting.
    var bloomReach: Double { beamHeight * lerp(0.85, 0.30) }

    /// How far past each end the bloom carries, over the plug's front face:
    /// light leaving a mouth pools on the metal around it. Cutting it off at
    /// the face instead leaves a straight vertical edge standing in the wedge
    /// of graphite above the chamfer, where the plug has already sloped away
    /// and there is nothing for the bloom to stop against — measured at 512 px,
    /// and plainly visible.
    var bloomEndReach: Double { bloomReach * 0.60 }

    /// Shapes were tried before the ramp: a blurred shadow, then a stack of
    /// fills each shorter than the last. Both draw a *silhouette* — a rounded
    /// rectangle or an oval — and at any alpha strong enough to see, the
    /// silhouette reads as an object parked behind the beam. A ramp has none,
    /// which is why the ends are faded by a mask rather than by a shape.

    /// How the bloom falls off, as (share of the reach out from the beam's
    /// edge, share of the peak alpha there). Steep at first and then long,
    /// which is the shape light falls off with, and the reason this is four
    /// stops rather than one straight line from the beam to nothing.
    static let bloomFalloff: [(reach: Double, level: Double)] = [
        (0.0, 1.0), (0.35, 0.38), (0.65, 0.12), (1.0, 0.0),
    ]
    static let bloomPeakAlpha = 0.55

    // MARK: The lens

    /// The bright middle of the span: an ellipse laid over the beam, filled
    /// with `Tone.accentGlare` fading to nothing at its top and bottom. Because
    /// it is an ellipse it is at full height in the middle of the run and
    /// narrows to nothing at the two ends, which is what makes the beam
    /// brightest where it is furthest from either plug.
    var lensLength: Double { beamLength * 0.96 }
    /// Taller than the beam, so the fade reaches nothing *before* the beam's
    /// own edge and the edges stay the accent's blue.
    var lensHeight: Double { beamHeight * 1.6 }
    /// Nearly opaque where the beam has the rows to fade it over, and all but
    /// gone at the small sizes, for the same reason `beamCore` closes up: the
    /// lens is the last thing §3.3's 16 pt blue bar can afford.
    var lensAlpha: Double { lerp(0.85, 0.15) }

    // MARK: The packets

    /// §3.3's "three small brighter marks along its length like packets in
    /// flight", as their centres along the run. Three, because two read as a
    /// dashed line and four as a pattern; placed symmetrically about the
    /// middle, because the rest of the drawing is symmetrical too.
    static let packetCentres = [0.185, 0.5, 0.815]

    /// A packet is a fifth of the run long and near half the beam thick, so it
    /// is a mark *in* the beam — longer than it is tall, which is what reads as
    /// motion — with the beam's own blue still showing above and below it.
    /// Measured along the run rather than off the square, so the three marks
    /// and the two gaps between them keep their rhythm at every size.
    ///
    /// Barely rounded: §3.3 calls them marks, and a mark with a capsule end is
    /// a bead sitting on the beam rather than a brighter piece of it.
    var packetLength: Double { beamLength * 0.22 }
    var packetHeight: Double { beamHeight * 0.46 }
    var packetCorner: Double { packetHeight * 0.16 }

    /// §3.3: "the packet marks may drop out at small sizes". Below this the run
    /// is short enough that three marks and two gaps have two or three pixels
    /// each: the marks stop being marks and turn the bar into noise, and a
    /// clean blue bar is what the 16 pt icon is for. Checked against the
    /// rendered files at 32 and 64 px.
    static let packetFloorPixels = 64.0
    var drawsPackets: Bool { pixels >= Self.packetFloorPixels }

    // MARK: The lit rims

    /// §3.3's "thin lit rim on its facing end": a filled edge of light across
    /// the plug's front face, never an opening in it. It sits just inside the
    /// face, so the beam's square end lands on the rim's outer edge and the
    /// join never shows.
    ///
    /// Thin — it is an edge, not a panel — and floored at a whole pixel,
    /// because at 16 px this is the one mark that says which end of each block
    /// the light comes out of.
    var rimThickness: Double { max(pixels * lerp(0.013, 0.030), 1.0) }

    /// A shade shorter than the face, so the chamfer's cut corners still show
    /// above and below the light and the plug keeps its machined profile.
    var rimHeight: Double { faceHeight * lerp(0.82, 0.60) }
    /// Just off square. A full capsule turns a thin tall bar into a drawn tube,
    /// which is a fourth object in a drawing that is allowed three.
    var rimCorner: Double { rimThickness * 0.4 }

    /// The rim's own glow, in three passes: it is the source, so it has to
    /// throw light both ways — back onto the plug's front face, which is what
    /// makes the metal look lit from its own mouth, and forward into the start
    /// of the beam, which is what makes the beam look emitted rather than
    /// glued on.
    var rimGlow: Double { rimThickness * lerp(2.2, 1.2) }
    var rimBloom: Double { rimThickness * lerp(6.0, 2.4) }

    /// The centre of one plug's rim: half a rim's thickness back from the face.
    func rimCentre(of plug: Plug) -> CGPoint {
        CGPoint(x: plug.faceX - plug.facing * rimThickness / 2, y: plug.centreY)
    }
}

// MARK: - Drawing

/// A rounded rectangle centred on `centre`, with the radius clamped the way
/// `CGPath` clamps it, so a capsule stays a capsule.
func roundedPath(centre: CGPoint, width: Double, height: Double, corner: Double) -> CGPath {
    let rect = CGRect(
        x: centre.x - width / 2, y: centre.y - height / 2, width: width, height: height
    )
    let radius = min(corner, min(width, height) / 2)
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// One plug shell as a closed outline: flat front face, 45° chamfer off each of
/// its four corners, turned back. Nothing is cut into it anywhere.
func outline(_ plug: Plug) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: plug.faceX, y: plug.centreY + plug.faceHalf))
    path.addLine(to: CGPoint(x: plug.shoulder, y: plug.top))
    path.addArc(
        tangent1End: CGPoint(x: plug.backX, y: plug.top),
        tangent2End: CGPoint(x: plug.backX, y: plug.bottom),
        radius: CGFloat(plug.corner)
    )
    path.addArc(
        tangent1End: CGPoint(x: plug.backX, y: plug.bottom),
        tangent2End: CGPoint(x: plug.shoulder, y: plug.bottom),
        radius: CGFloat(plug.corner)
    )
    path.addLine(to: CGPoint(x: plug.shoulder, y: plug.bottom))
    path.addLine(to: CGPoint(x: plug.faceX, y: plug.centreY - plug.faceHalf))
    path.closeSubpath()
    return path
}

/// Fills `path` with a vertical ramp between `bottom` and `top`.
func fill(
    _ path: CGPath, in context: CGContext, space: CGColorSpace,
    colors: [CGColor], locations: [CGFloat], from bottom: Double, to top: Double
) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: space, colors: colors as CFArray, locations: locations
    ) {
        context.drawLinearGradient(
            gradient, start: CGPoint(x: 0, y: bottom), end: CGPoint(x: 0, y: top), options: []
        )
    }
    context.restoreGState()
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

    let plugs = art.plugs

    // --- the two plug ends -------------------------------------------------
    for plug in [plugs.left, plugs.right] {
        draw(plug: plug, in: context, art: art, space: space)
    }

    // --- the beam ----------------------------------------------------------
    // Over the plugs, so the bloom lands on the metal around each mouth the way
    // light leaving a lit port does on the model, and under the rims, which
    // cover the beam's two square ends.
    draw(bloom: art, in: context, space: space)
    draw(beam: art, in: context, space: space)

    // --- the two lit rims --------------------------------------------------
    for plug in [plugs.left, plugs.right] {
        draw(rim: plug, in: context, art: art)
    }

    return context.makeImage()
}

/// §3.3's plug end, drawn as a lit shell rather than a filled silhouette: the
/// chamfer band, the front face inside it, a contact line under the base and a
/// specular hairline along the top edge.
func draw(plug: Plug, in context: CGContext, art: Art, space: CGColorSpace) {
    let shell = outline(plug)
    let front = outline(plug.inset(by: art.bevel))

    // The chamfer band. Its own steep ramp, over the whole height, so the two
    // top facets come out well above the front face and the two bottom ones
    // below the graphite: the band is only ever seen between `shell` and
    // `front`, which is exactly where a milled corner is.
    fill(
        shell, in: context, space: space,
        colors: [art.bevelBase, art.bevelMid, art.bevelTop],
        locations: [0, CGFloat(Art.bevelMidStop), 1],
        from: plug.bottom, to: plug.top
    )

    // The front face, on top of the band and inside it.
    fill(
        front, in: context, space: space,
        colors: [art.chassisBase, art.chassisMid, art.chassisTop],
        locations: [0, CGFloat(Art.chassisMidStop), 1],
        from: plug.bottom, to: plug.top
    )

    // The contact line: the outline stroked, then faded out by the time it is
    // `contactReach` up the block, so only the base carries it.
    stroke(
        shell, in: context, space: space, width: art.contactThickness,
        colors: [Tone.contact, Tone.with(Tone.contact, alpha: 0)],
        locations: [0, 1],
        from: plug.bottom - art.contactThickness,
        to: plug.bottom + art.plugHeight * Art.contactReach
    )

    // The specular: the same outline, thinner and brighter, faded out
    // `specularReach` down from the top edge. Clipped to the shell so the
    // stroke's outer half never spills onto the graphite as a halo.
    context.saveGState()
    context.addPath(shell)
    context.clip()
    stroke(
        shell, in: context, space: space, width: art.specularThickness * 2,
        colors: [Tone.with(art.specular, alpha: 0), art.specular],
        locations: [0, 1],
        from: plug.top - art.plugHeight * Art.specularReach,
        to: plug.top
    )
    context.restoreGState()
}

/// Strokes `path` and fills the stroke with a vertical ramp — a stroke colour
/// cannot vary along an outline, and an edge that is the same brightness top
/// and bottom does not read as a lit shell at all.
func stroke(
    _ path: CGPath, in context: CGContext, space: CGColorSpace, width: Double,
    colors: [CGColor], locations: [CGFloat], from bottom: Double, to top: Double
) {
    context.saveGState()
    context.addPath(path)
    context.setLineWidth(CGFloat(width))
    context.setLineJoin(.round)
    context.replacePathWithStrokedPath()
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: space, colors: colors as CFArray, locations: locations
    ) {
        context.drawLinearGradient(
            gradient, start: CGPoint(x: 0, y: bottom), end: CGPoint(x: 0, y: top),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
    context.restoreGState()
}

/// §3.3's "glowing softly at its edges": `Art.bloomSteps` fills of the accent at
/// a low alpha, each shorter than the last, so the light fades over about one
/// beam-height into the graphite above and below the beam and pools on the
/// metal at each mouth. Drawn outermost first; the beam itself covers the lot.
func draw(bloom art: Art, in context: CGContext, space: CGColorSpace) {
    let reach = art.bloomReach
    let half = art.beamHeight / 2 + reach
    let total = 2 * half
    guard reach > 0, total > 0 else { return }

    // The falloff, laid out from the bottom of the band up: out-to-in below the
    // beam, then in-to-out above it. The two innermost stops are both the peak,
    // so the strip the beam itself covers is held flat between them.
    var colors: [CGColor] = []
    var locations: [CGFloat] = []
    for stop in Art.bloomFalloff.reversed() {
        colors.append(Tone.with(Tone.accent, alpha: stop.level * Art.bloomPeakAlpha))
        locations.append(CGFloat(reach * (1 - stop.reach) / total))
    }
    for stop in Art.bloomFalloff {
        colors.append(Tone.with(Tone.accent, alpha: stop.level * Art.bloomPeakAlpha))
        locations.append(CGFloat(1 - reach * (1 - stop.reach) / total))
    }

    let band = CGRect(
        x: art.beamStartX - art.bloomEndReach, y: art.beamCentreY - half,
        width: art.beamLength + 2 * art.bloomEndReach, height: total
    )

    // The vertical ramp is what the bloom *is*; the mask is only there to take
    // its two ends to nothing over the run they spend on the metal, so the band
    // has no edge of its own anywhere.
    context.saveGState()
    if let mask = endFade(share: art.bloomEndReach / band.width) {
        context.clip(to: band, mask: mask)
    } else {
        context.clip(to: band)
    }
    if let gradient = CGGradient(
        colorsSpace: space, colors: colors as CFArray, locations: locations
    ) {
        context.drawLinearGradient(
            gradient, start: CGPoint(x: 0, y: band.minY), end: CGPoint(x: 0, y: band.maxY),
            options: []
        )
    }
    context.restoreGState()
}

/// A one-row grey image that is opaque across its middle and eases to nothing
/// over `share` of its width at each end — the horizontal half of the bloom's
/// falloff, as a mask, because CoreGraphics will multiply a gradient by a mask
/// but not by another gradient.
///
/// Eased rather than straight: a linear fade leaves a visible crease where it
/// meets the flat middle, which is the same kind of edge the mask is here to
/// remove.
func endFade(share: Double, samples: Int = 512) -> CGImage? {
    guard share > 0 else { return nil }
    var row = [UInt8](repeating: 255, count: samples)
    for index in 0..<samples {
        let u = (Double(index) + 0.5) / Double(samples)
        let t = min(min(u, 1 - u) / share, 1)
        row[index] = UInt8((t * t * (3 - 2 * t) * 255).rounded())
    }
    // Device grey with no alpha: what `CGContext.clip(to:mask:)` documents it
    // will take, and the samples are read as coverage rather than colour.
    guard
        let context = CGContext(
            data: nil, width: samples, height: 1, bitsPerComponent: 8, bytesPerRow: samples,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
    else { return nil }
    context.data?.copyMemory(from: row, byteCount: samples)
    return context.makeImage()
}

/// §3.3's beam: one level bar from face to face, ramping from the accent at its
/// two edges to a brighter core on the centre line, with a lens over the middle
/// of the span taking that core up to near-white, and the three packet marks on
/// top of both.
func draw(beam art: Art, in context: CGContext, space: CGColorSpace) {
    let body = CGRect(
        x: art.beamStartX, y: art.beamCentreY - art.beamHeight / 2,
        width: art.beamLength, height: art.beamHeight
    )
    fill(
        CGPath(rect: body, transform: nil), in: context, space: space,
        colors: [Tone.accent, art.beamCore, Tone.accent],
        locations: [0, CGFloat(Art.beamCoreStop), 1],
        from: body.minY, to: body.maxY
    )

    // The lens: an ellipse inside the beam, brightest on the centre line and
    // gone by the beam's own edges, so the run is brightest in the middle where
    // it is furthest from either plug. Clipped by the beam as well as by itself.
    context.saveGState()
    context.clip(to: body)
    let lens = CGRect(
        x: art.beamStartX + (art.beamLength - art.lensLength) / 2,
        y: art.beamCentreY - art.lensHeight / 2,
        width: art.lensLength, height: art.lensHeight
    )
    context.addPath(CGPath(ellipseIn: lens, transform: nil))
    context.clip()
    if let glare = CGGradient(
        colorsSpace: space,
        colors: [
            Tone.with(Tone.accentGlare, alpha: 0),
            Tone.with(Tone.accentGlare, alpha: 0),
            Tone.with(Tone.accentGlare, alpha: art.lensAlpha),
            Tone.with(Tone.accentGlare, alpha: 0),
            Tone.with(Tone.accentGlare, alpha: 0),
        ] as CFArray,
        locations: [0, 0.25, 0.5, 0.75, 1]
    ) {
        context.drawLinearGradient(
            glare, start: CGPoint(x: 0, y: lens.minY), end: CGPoint(x: 0, y: lens.maxY),
            options: []
        )
    }
    context.restoreGState()

    guard art.drawsPackets else { return }
    context.setFillColor(Tone.accentSpark)
    for u in Art.packetCentres {
        let path = roundedPath(
            centre: CGPoint(x: art.beamStartX + art.beamLength * u, y: art.beamCentreY),
            width: art.packetLength, height: art.packetHeight, corner: art.packetCorner
        )
        context.addPath(path)
        context.fillPath()
    }
}

/// §3.3's lit rim: a thin cyan-white edge across the plug's front face, glowing
/// back onto the metal and forward into the start of the beam, so the beam
/// leaves the plug rather than being stuck to it. An edge of light, never an
/// opening — nothing in this icon is a hole.
func draw(rim plug: Plug, in context: CGContext, art: Art) {
    let bar = roundedPath(
        centre: art.rimCentre(of: plug), width: art.rimThickness, height: art.rimHeight,
        corner: art.rimCorner
    )
    for (blur, alpha) in [(art.rimBloom, 0.45), (art.rimGlow, 0.80), (art.rimGlow / 2, 0.85)] {
        context.saveGState()
        context.setShadow(
            offset: .zero, blur: CGFloat(blur), color: Tone.with(Tone.rimEdge, alpha: alpha)
        )
        context.setFillColor(Tone.rimEdge)
        context.addPath(bar)
        context.fillPath()
        context.restoreGState()
    }

    context.setFillColor(Tone.rimEdge)
    context.addPath(bar)
    context.fillPath()
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
