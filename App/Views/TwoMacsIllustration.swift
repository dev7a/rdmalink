//
//  TwoMacsIllustration.swift
//
//  The one drawing in S13: two Macs and one cable, flat and two-dimensional.
//
//  Deliberately *not* the 3D model. The sheet is reading material, and mixing
//  the live model in would imply the drawings are about this particular Mac
//  (UX_SPEC §S13). So: two generic boxes, two receptacles, one cable, no
//  proportions borrowed from any machine, no logo and no trade dress (§3.4).
//

import SwiftUI

struct TwoMacsIllustration: View {
    var body: some View {
        Canvas { context, size in
            let chassisWidth = size.width * 0.26
            let chassisHeight = size.height * 0.66
            let midY = size.height / 2
            let left = CGRect(
                x: size.width * 0.04, y: midY - chassisHeight / 2,
                width: chassisWidth, height: chassisHeight
            )
            let right = CGRect(
                x: size.width * 0.70, y: midY - chassisHeight / 2,
                width: chassisWidth, height: chassisHeight
            )
            draw(chassis: left, in: &context)
            draw(chassis: right, in: &context)

            let start = CGPoint(x: left.maxX, y: midY)
            let end = CGPoint(x: right.minX, y: midY)
            var cable = Path()
            cable.move(to: start)
            cable.addCurve(
                to: end,
                control1: CGPoint(x: start.x + (end.x - start.x) * 0.35, y: midY + size.height * 0.16),
                control2: CGPoint(x: start.x + (end.x - start.x) * 0.65, y: midY + size.height * 0.16)
            )
            context.stroke(cable, with: .style(.tint), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            context.fill(receptacle(at: start), with: .style(.tint))
            context.fill(receptacle(at: end), with: .style(.tint))
        }
        .frame(height: 104)
        .accessibilityHidden(true)
    }

    private func draw(chassis rect: CGRect, in context: inout GraphicsContext) {
        let shape = Path(roundedRect: rect, cornerRadius: rect.height * 0.22)
        context.fill(shape, with: .style(.quaternary))
        context.stroke(shape, with: .style(.tertiary), lineWidth: 1.5)
    }

    private func receptacle(at point: CGPoint) -> Path {
        Path(roundedRect: CGRect(x: point.x - 5, y: point.y - 3, width: 10, height: 6), cornerRadius: 3)
    }
}
