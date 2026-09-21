//
//  TwoMacsIllustration.swift
//
//  The one drawing in S13: two Macs, the bridge they keep, and the one cable
//  that has been taken out of it — flat and two-dimensional.
//
//  Deliberately *not* the 3D model. The sheet is reading material, and mixing
//  the live model in would imply the drawings are about this particular Mac
//  (UX_SPEC §S13). So: two plain rounded slabs, no proportions borrowed from
//  any machine, no logo and no trade dress (§3.4).
//
//  §S13 sets out the whole picture, and this file draws exactly that and
//  nothing more: four receptacles along each facing edge; the three still in
//  the bridge tied together by a soft translucent ribbon labelled
//  "Thunderbolt Bridge"; the fourth standing apart, ringed in the accent; one
//  accent cable with a gentle sag between the two ringed receptacles, with
//  "fe80::" above its middle. Those are the only words on it. Everything else
//  is hairline strokes and control-background fills, so the drawing sits in
//  the sheet at the weight of the prose instead of shouting over it.
//

import SwiftUI

struct TwoMacsIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // §S13 makes the travelling dot optional and says the picture is
        // complete without it, so Reduce Motion gets the still drawing
        // outright rather than an animation frozen at some arbitrary frame.
        Group {
            if reduceMotion {
                drawing(travel: nil)
            } else {
                TimelineView(.animation) { timeline in
                    drawing(travel: Geometry.travel(at: timeline.date))
                }
            }
        }
        .frame(height: Geometry.height)
        // The four sections beside it say all of this in words. A screen
        // reader reading the picture too would only say it twice.
        .accessibilityHidden(true)
    }

    /// The drawing itself. `travel` is how far along the cable the dot has
    /// got, or nil when there is no dot.
    private func drawing(travel: CGFloat?) -> some View {
        Canvas { context, size in
            let slabs = Geometry.slabs(in: size)
            let cable = Geometry.cable(from: slabs.left, to: slabs.right)

            for slab in [slabs.left, slabs.right] {
                draw(chassis: slab, in: &context)
                draw(bridgeRibbon: slab, in: &context)
            }

            // The cable goes down before the receptacles do, so its two ends
            // disappear under them and read as seated rather than glued on.
            context.stroke(
                cable.path,
                with: .style(.tint),
                style: StrokeStyle(lineWidth: Geometry.cableWidth, lineCap: .round)
            )

            for slab in [slabs.left, slabs.right] {
                draw(receptacles: slab, in: &context)
            }

            draw(address: cable, in: &context)

            if let travel {
                let dot = cable.point(at: travel)
                let box = CGRect(
                    x: dot.x - Geometry.dotRadius, y: dot.y - Geometry.dotRadius,
                    width: Geometry.dotRadius * 2, height: Geometry.dotRadius * 2
                )
                context.fill(Path(ellipseIn: box), with: .style(.tint))
            }
        }
    }

    // MARK: - The parts

    private func draw(chassis slab: Slab, in context: inout GraphicsContext) {
        let shape = Path(roundedRect: slab.rect, cornerRadius: Geometry.slabCorner)
        context.fill(shape, with: .color(Color(nsColor: .controlBackgroundColor)))
        context.stroke(shape, with: .style(.tertiary), lineWidth: Geometry.hairline)
    }

    /// The ribbon ties the three receptacles that stay in the bridge, and only
    /// those three — the whole point of the drawing is that the fourth is not
    /// under it (§S13).
    private func draw(bridgeRibbon slab: Slab, in context: inout GraphicsContext) {
        let ribbon = Path(
            roundedRect: CGRect(
                x: slab.edgeX - Geometry.ribbonWidth / 2,
                y: Geometry.firstBridgePortY - Geometry.ribbonPadding,
                width: Geometry.ribbonWidth,
                height: Geometry.lastBridgePortY - Geometry.firstBridgePortY
                    + Geometry.ribbonPadding * 2
            ),
            cornerRadius: Geometry.ribbonCorner
        )
        context.fill(ribbon, with: .style(.quaternary))
        context.stroke(ribbon, with: .style(.quaternary), lineWidth: Geometry.hairline)

        // Inside the slab, on the ribbon's centre line: the label belongs to
        // this Mac's own bridge, so it sits on the Mac, not out in the gap
        // where the cable's label lives.
        context.draw(
            Text("Thunderbolt Bridge")
                .font(.caption)
                .foregroundStyle(.secondary),
            at: CGPoint(
                x: slab.rect.midX - slab.facing * Geometry.ribbonWidth / 4,
                y: (Geometry.firstBridgePortY + Geometry.lastBridgePortY) / 2
            )
        )
    }

    private func draw(receptacles slab: Slab, in context: inout GraphicsContext) {
        for y in Geometry.bridgePortY + [Geometry.linkPortY] {
            let port = Path(
                roundedRect: CGRect(
                    x: slab.edgeX - Geometry.portSize.width / 2,
                    y: y - Geometry.portSize.height / 2,
                    width: Geometry.portSize.width,
                    height: Geometry.portSize.height
                ),
                cornerRadius: Geometry.portCorner
            )
            context.fill(port, with: .color(Color(nsColor: .controlBackgroundColor)))
            context.stroke(port, with: .style(.secondary), lineWidth: Geometry.portHairline)
        }

        // The ring marks the one that has left the bridge, in the same accent
        // as the cable because they are the same idea (§S13).
        let ring = Path(
            roundedRect: CGRect(
                x: slab.edgeX - Geometry.ringSize.width / 2,
                y: Geometry.linkPortY - Geometry.ringSize.height / 2,
                width: Geometry.ringSize.width,
                height: Geometry.ringSize.height
            ),
            cornerRadius: Geometry.ringCorner
        )
        context.stroke(ring, with: .style(.tint), lineWidth: Geometry.ringWidth)
    }

    /// The address rides above the middle of the cable, where it is plainly
    /// about the cable and not about either Mac (§S13).
    private func draw(address cable: Cable, in context: inout GraphicsContext) {
        let middle = cable.point(at: 0.5)
        context.draw(
            Text(verbatim: "fe80::")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary),
            at: CGPoint(x: middle.x, y: middle.y - Geometry.addressLift)
        )
    }
}

// MARK: - Geometry

/// One of the two slabs, and which way it faces.
private struct Slab {
    let rect: CGRect
    /// +1 when the receptacles are on the slab's right edge, -1 on its left.
    let facing: CGFloat

    /// The facing edge: where the receptacles sit and the cable begins.
    var edgeX: CGFloat { facing > 0 ? rect.maxX : rect.minX }
}

/// The cable, kept as its four control points so that the stroke and the dot
/// travelling along it are guaranteed to follow the same curve.
private struct Cable {
    let start: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint

    var path: Path {
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)
        return path
    }

    /// The point at parameter `t` of the cubic. Not arc length — over a sag
    /// this shallow the difference is invisible, and the easing below is what
    /// the eye reads as the dot's speed anyway.
    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let (a, b, c, d) = (u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t)
        return CGPoint(
            x: a * start.x + b * control1.x + c * control2.x + d * end.x,
            y: a * start.y + b * control1.y + c * control2.y + d * end.y
        )
    }
}

/// Every measurement in the drawing, in points. The canvas takes the sheet's
/// full content width and this height, and the two slabs are pinned to its
/// two edges, so only the gap the cable crosses changes with the width.
private enum Geometry {
    static let height: CGFloat = 160
    /// Half a hairline, so the outermost strokes are not clipped away.
    static let edgeInset: CGFloat = 0.5

    static let slabWidth: CGFloat = 148
    static let slabHeight: CGFloat = 138
    static let slabTop: CGFloat = 11
    static let slabCorner: CGFloat = 16

    static let portSize = CGSize(width: 13, height: 6)
    static let portCorner: CGFloat = 3

    /// The three receptacles still in the bridge, evenly spaced down the edge.
    static let bridgePortCount = 3
    static let firstBridgePortY: CGFloat = 44
    static let bridgePortSpacing: CGFloat = 22
    static let lastBridgePortY =
        firstBridgePortY + bridgePortSpacing * CGFloat(bridgePortCount - 1)
    static var bridgePortY: [CGFloat] {
        (0 ..< bridgePortCount).map { firstBridgePortY + CGFloat($0) * bridgePortSpacing }
    }
    /// The fourth, standing well clear of the other three — the gap is what
    /// says it is no longer one of them.
    static let linkPortY: CGFloat = 122

    static let ribbonWidth: CGFloat = 24
    /// How far the ribbon reaches past the first and last receptacle it ties.
    static let ribbonPadding: CGFloat = 12
    static let ribbonCorner: CGFloat = 12

    static let ringSize = CGSize(width: 26, height: 18)
    static let ringCorner: CGFloat = 8
    static let ringWidth: CGFloat = 1.5

    static let cableWidth: CGFloat = 2.5
    /// How far the control points hang below the two receptacles. The curve
    /// itself dips three quarters of this, which is the gentle sag §S13 asks
    /// for: enough for a cable's weight, not enough to look slack.
    static let cableSag: CGFloat = 26
    /// Where the control points sit along the span, as a fraction of it.
    /// Kept in near the ends: a hanging cable is steepest where it leaves the
    /// port and flattest in the middle, and pushing them out would flatten the
    /// whole middle into a tray.
    static let cableShoulder: CGFloat = 0.3
    /// Clearance between "fe80::" and the cable it belongs to.
    static let addressLift: CGFloat = 14

    static let dotRadius: CGFloat = 3.5
    static let hairline: CGFloat = 1
    static let portHairline: CGFloat = 0.75

    /// One trip along the cable, in seconds.
    static let trip: TimeInterval = 4
    /// How much of each end of the cable the dot leaves alone. It eases to a
    /// stop at the turn, and a dot resting *inside* a receptacle would read as
    /// a lit port — a thing this drawing does not mean and the app says with
    /// the accent ring instead.
    static let travelMargin: CGFloat = 0.07

    static func slabs(in size: CGSize) -> (left: Slab, right: Slab) {
        (
            Slab(
                rect: CGRect(x: edgeInset, y: slabTop, width: slabWidth, height: slabHeight),
                facing: 1
            ),
            Slab(
                rect: CGRect(
                    x: size.width - edgeInset - slabWidth,
                    y: slabTop, width: slabWidth, height: slabHeight
                ),
                facing: -1
            )
        )
    }

    static func cable(from left: Slab, to right: Slab) -> Cable {
        let start = CGPoint(x: left.edgeX, y: linkPortY)
        let end = CGPoint(x: right.edgeX, y: linkPortY)
        let shoulder = (end.x - start.x) * cableShoulder
        return Cable(
            start: start,
            control1: CGPoint(x: start.x + shoulder, y: linkPortY + cableSag),
            control2: CGPoint(x: end.x - shoulder, y: linkPortY + cableSag),
            end: end
        )
    }

    /// How far along the cable the dot has got, taken from the wall clock so
    /// the drawing itself stays stateless. A cosine rather than a sawtooth:
    /// the dot eases to a stop just short of one receptacle and comes back,
    /// so it never jumps from one end to the other. One trip is half a cycle.
    static func travel(at date: Date) -> CGFloat {
        let cycle = trip * 2
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycle) / cycle
        let swing = CGFloat((1 - cos(2 * .pi * phase)) / 2)
        return travelMargin + swing * (1 - travelMargin * 2)
    }
}
