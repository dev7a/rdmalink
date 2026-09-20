//
//  StageChassisGeometry.swift
//
//  What the stage needs on top of `RDMALinkCore.Chassis`, and nothing more.
//
//  The catalogue itself — proportions, hole positions, hole sizes, the §4.7
//  names — lives in Core, shared with the CLI and the tests. Everything here is
//  view policy: how tall the machine reads, what the camera looks at, how big
//  an invisible click target has to be. None of it is a fact about a Mac, so
//  none of it belongs in Core.
//

import CoreGraphics
import Foundation
import RDMALinkCore

extension Chassis {
    /// A notebook is the chassis that has a lid; nothing else needs a shape
    /// enum, and one would only be a second way to ask the same question.
    var isNotebook: Bool { lid != nil }

    /// Everything drawn but never ringed, lit or selected.
    var scenery: [ChassisFeature] { features.filter { !$0.kind.isReceptacle } }

    /// True where a receptacle stands on its short edge — the desktops.
    ///
    /// Read off the receptacles rather than stored, because it is per-feature
    /// in the catalogue and the camera only ever needs the machine's answer.
    var hasVerticalReceptacles: Bool { receptacles.first?.isVertical ?? true }

    /// How tall the machine reads: the body, or the standing lid on a notebook.
    var visibleHeight: Double {
        guard let lid else { return height }
        return height + lid.depth * sin(lid.openAngle * .pi / 180)
    }

    /// The point the camera looks at, in centimetres above the ground plane.
    var focus: Double {
        isNotebook ? visibleHeight * 0.40 : height * 0.48
    }
}

extension ChassisFeature {
    /// UX_SPEC §8.4: the invisible collider around a receptacle, in
    /// centimetres.
    ///
    /// The floor is what decides it. A Mac Studio's back row is 0.985 cm
    /// apart, and a proxy kept inside that gap reads 17.7 pt across at the
    /// resting distance — under §8.4's 24 × 24 pt at the pose the app opens
    /// in. So the proxy is allowed past the pitch, neighbouring proxies
    /// overlap, and ``StageScene/portID(at:)`` resolves the overlap by taking
    /// the nearest projected centre to the pointer. That makes the real target
    /// the cell around each receptacle, which is never narrower than the pitch
    /// and has no dead band in it.
    var colliderSize: CGSize { Self.colliderSize(of: kind, vertical: isVertical) }

    /// 1.6 cm is what holds §8.4's floor at the resting pose on every desktop
    /// chassis in the catalogue, in every stage the window can produce — the
    /// 58 / 42 split, the 460 pt minimum window and §8.5's 180 pt strip —
    /// without pulling the camera in off the fit distance at all. The padded
    /// opening is used wherever it is already larger.
    static let minimumCollider = 1.6

    static func colliderSize(of kind: FeatureKind, vertical: Bool) -> CGSize {
        let opening = vertical ? kind.opening.rotated : kind.opening
        return CGSize(
            width: max(opening.width + 0.55, minimumCollider),
            height: max(opening.height + 0.70, minimumCollider)
        )
    }
}
