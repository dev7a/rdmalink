//
//  StageLegend.swift
//
//  UX_SPEC §4.8's legend, as data: which outer-ring shapes are on this Mac
//  right now, and the panel's word for each. Pure — Foundation and Core only —
//  so script/test_presentation.sh can assert the rows without a window.
//
//  It also holds the one place a port's outer ring is decided from what the
//  hub observed, so the ring on the model and the line in the legend can only
//  ever come from the same answer.
//

import Foundation
import RDMALinkCore

extension StagePort.Configuration {
    /// UX_SPEC §4.3's outer track, read off what the hub has already observed
    /// and never off anything else.
    ///
    /// The three readiness states §S1 counts as ready do not all mean the same
    /// ring: RDMALink's own ports and the ports it has adopted are the solid
    /// accent ring, and a port that is exactly what RDMALink would have made
    /// but was not made by RDMALink is the double hairline, because it is not
    /// RDMALink's to claim.
    init(_ snapshot: PortSnapshot) {
        switch snapshot.readiness {
        case .managed, .adopted: self = .ready
        case .setUpElsewhere: self = .outside
        case .drifted: self = .drift
        // §4.3: "Provenance is a panel matter: the ring says only that the
        // port is in the bridge."
        case .returned: self = .bridge
        case .plain: self = snapshot.bridges.isEmpty ? .none : .bridge
        }
    }

    /// §4.8: the legend's line for this ring, in the order the spec lists
    /// them. Every outer-track state has one, the no-ring state included —
    /// "an empty slot" is a shape too, and the legend is how a user learns
    /// that a bare receptacle means **Standalone** rather than *unknown*.
    var legendRow: StageLegendRow {
        switch self {
        case .bridge: StageLegendRow(glyph: .segmented, label: "In a bridge")
        case .none: StageLegendRow(glyph: .emptySlot, label: "Standalone")
        case .outside: StageLegendRow(glyph: .doubleHairline, label: "Set up outside RDMALink")
        case .ready: StageLegendRow(glyph: .solidAccent, label: "Ready for RDMA")
        case .drift: StageLegendRow(glyph: .dashed, label: "Needs a look")
        }
    }
}

/// §4.8: "glyph first: the ring geometries themselves at small scale."
enum StageLegendGlyph: Hashable, Sendable {
    /// §4.3's four arcs with four gaps.
    case segmented
    /// No outer ring at all: the receptacle alone.
    case emptySlot
    /// Two thin concentric hairlines.
    case doubleHairline
    /// One unbroken ring in accent.
    case solidAccent
    /// The drift ring.
    case dashed
}

/// One line of the legend.
struct StageLegendRow: Hashable, Sendable, Identifiable {
    let glyph: StageLegendGlyph
    /// §4.8: "Labels are the panel's own words".
    let label: LocalizedStringResource

    var id: StageLegendGlyph { glyph }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.glyph == rhs.glyph }
    func hash(into hasher: inout Hasher) { hasher.combine(glyph) }
}

enum StageLegend {
    /// §4.8's order: **In a bridge** · **Standalone** · **Set up outside
    /// RDMALink** · **Ready for RDMA** · **Needs a look**.
    static let order: [StagePort.Configuration] = [.bridge, .none, .outside, .ready, .drift]

    /// "One line per outer-ring shape present on this Mac right now" — in
    /// the spec's order, never the ports', so the legend does not reshuffle
    /// as a Mac is plugged in. USB-only receptacles never take a ring (§4.5)
    /// and so never put a line here.
    static func rows(for ports: [StagePort]) -> [StageLegendRow] {
        rows(for: ports.filter(\.isThunderbolt).map(\.cfg))
    }

    static func rows(for configurations: [StagePort.Configuration]) -> [StageLegendRow] {
        let present = Set(configurations)
        return order.filter(present.contains).map(\.legendRow)
    }
}
