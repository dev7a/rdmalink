//
//  StageOverlays.swift
//
//  The only things allowed to float over the stage: the face selector, the
//  Fit / Reset View pair, the narration capsule (UX_SPEC §2.3, §9.1), §S5's
//  bookmark glyph, and §4.8's two aids — the legend and the receptacle
//  callout. Nothing else. No badge, no step indicator, and no text on the
//  model itself (§4.7): both aids are SwiftUI over the render surface.
//

import RDMALinkCore
import SwiftUI

/// UX_SPEC §2.3: a segmented control inside a `Capsule` of `.regularMaterial`,
/// Maps-style. `Back / Front` on desktops, `Left / Right` on notebooks.
struct StageFaceSelector: View {
    let faces: [PortFace]
    let current: PortFace
    let appearance: StageAppearance
    /// §S1 and §7.4: the face a port changed state on while it was out of
    /// sight. Its segment takes a small accent dot; nothing moves.
    var unseenChange: PortFace?
    let turnTo: (PortFace) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(faces, id: \.self) { face in
                Button {
                    turnTo(face)
                } label: {
                    Text(Self.title(for: face))
                        .font(.callout)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .frame(minWidth: 58)
                        .background {
                            if face == current {
                                Capsule().fill(.quaternary)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if face == unseenChange {
                                Circle()
                                    .fill(.tint)
                                    .frame(width: 5, height: 5)
                                    .padding(.trailing, 6)
                                    .padding(.top, 2)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(face == current ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .stageCapsule(appearance)
        .animation(
            appearance.reduceMotion ? nil : .smooth(duration: 0.18), value: unseenChange
        )
    }

    /// §2.3 names the segments `Back`, `Front`, `Left`, `Right`. The port list
    /// headers say "Left side" — a header has room for it and a segment does
    /// not, and the spec writes both.
    private static func title(for face: PortFace) -> LocalizedStringResource {
        switch face {
        case .back: "Back"
        case .front: "Front"
        case .left: "Left"
        case .right: "Right"
        }
    }
}

/// §2.3: two small borderless buttons, bottom-trailing.
///
/// Their ⌘0 / ⇧⌘0 shortcuts live on the View menu (§2.7), not here, so the
/// menu stays the one place a shortcut is declared.
struct StageViewControls: View {
    let fit: () -> Void
    let reset: () -> Void
    /// §3.6 and §8.6 name *both* floating capsules, so this one takes the
    /// same treatment the face selector and the narration do.
    let appearance: StageAppearance

    var body: some View {
        // §2.3: "two small borderless buttons". Borderless buttons carry no
        // edge of their own, so without real space between them `Fit` and
        // `Reset View` read as one four-word label.
        HStack(spacing: 14) {
            Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right", action: fit)
            Button("Reset View", action: reset)
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .stageCapsule(appearance)
    }
}

/// §9.1: the app narrates its own camera moves in words first.
struct StageNarration: View {
    let line: LocalizedStringResource?
    let appearance: StageAppearance

    var body: some View {
        Group {
            if let line {
                Text(line)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .stageCapsule(appearance)
                    .transition(.opacity)
            }
        }
        .animation(
            appearance.reduceMotion ? nil : .smooth(duration: 0.18), value: line != nil
        )
        // The panel and VoiceOver get the same words from `StageModel`; this
        // capsule must not announce them a second time.
        .accessibilityHidden(true)
    }
}

extension View {
    /// §3.6: both floating capsules become opaque under Reduce Transparency
    /// and gain a hairline under Increase Contrast.
    func stageCapsule(_ appearance: StageAppearance) -> some View {
        stageSurface(appearance, shape: .capsule)
    }

    /// The same treatment on any shape: §4.8's callout is a small rounded
    /// rectangle and takes exactly what the capsules take.
    func stageSurface(_ appearance: StageAppearance, shape: some InsettableShape) -> some View {
        background {
            if appearance.reduceTransparency {
                shape.fill(.windowBackground)
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .overlay {
            if appearance.increaseContrast {
                shape.strokeBorder(.secondary, lineWidth: 1)
            }
        }
        .clipShape(shape)
    }
}

// MARK: - §4.8: the legend

/// UX_SPEC §4.8: "A `.caption` `.secondary` list in the stage's top-leading
/// corner, one line per outer-ring shape present on this Mac right now, glyph
/// first: the ring geometries themselves at small scale. … Nothing about the
/// inner track, nothing about selection, no title."
///
/// The rows are `StageLegend.rows(for:)`; this only draws them. It is hidden
/// from VoiceOver like the narration capsule: its words are the panel's own,
/// read there in full, and the ring shapes it explains are a sighted aid.
struct StageLegendView: View {
    let rows: [StageLegendRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows) { row in
                HStack(spacing: 7) {
                    StageLegendGlyphView(glyph: row.glyph)
                    Text(row.label)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One ring geometry at small scale, around the slot it would ring: the
/// same spans `StageMath.spans(for:)` gives the model, walked round a
/// rounded rectangle, so the legend's segmented ring has the model's four
/// gaps and its dashed ring the model's dashes.
struct StageLegendGlyphView: View {
    let glyph: StageLegendGlyph

    /// A receptacle standing on its short edge, as on a desktop's back.
    private static let slot = CGSize(width: 5, height: 9)
    private static let ring = CGSize(width: 11, height: 15)
    private static let outerRing = CGSize(width: 14, height: 18)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(.secondary.opacity(0.35))
                .frame(width: Self.slot.width, height: Self.slot.height)
            switch glyph {
            case .emptySlot:
                EmptyView()
            case .segmented:
                ring(.segmented, size: Self.ring, lineWidth: 1, style: .secondary)
            case .dashed:
                ring(.dashed, size: Self.ring, lineWidth: 1, style: .secondary)
            case .doubleHairline:
                ring(.solid, size: Self.ring, lineWidth: 0.7, style: .secondary)
                ring(.solid, size: Self.outerRing, lineWidth: 0.7, style: .secondary)
            case .solidAccent:
                ring(.solid, size: Self.ring, lineWidth: 1.5, style: .tint)
            }
        }
        .frame(width: Self.outerRing.width + 2, height: Self.outerRing.height + 2)
    }

    private func ring(
        _ pattern: StageMath.RingPattern, size: CGSize, lineWidth: CGFloat,
        style: some ShapeStyle
    ) -> some View {
        ZStack {
            ForEach(Array(StageMath.spans(for: pattern).enumerated()), id: \.offset) { _, span in
                RoundedRectangle(cornerRadius: size.width * 0.36)
                    .trim(from: span.start, to: span.end)
                    .stroke(style, lineWidth: lineWidth)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - §4.8: the receptacle callout

/// UX_SPEC §4.8: "a small callout beside it with the row's title and detail
/// line, verbatim … and, when technical names are on, the row's technical
/// line too." The words are `StageCalloutText`'s, built from the row's own
/// presentation; this draws them in the row's own styles (§3.2, §1.3 rule 6).
///
/// It sits over the render surface and must never take the pointer: a
/// callout that swallowed the hover would end the hover that raised it.
/// Hidden from VoiceOver, because the list already says every word of it and
/// the receptacle element carries the same label (§8.2).
struct StageCalloutView: View {
    let text: StageCalloutText
    let appearance: StageAppearance

    /// The widest a callout grows before its detail line wraps — an address
    /// wraps at a colon group rather than being cut short (§8.5).
    static let maximumWidth: CGFloat = 280

    var body: some View {
        CappedWidth(Self.maximumWidth) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: text.title)
                    .font(.callout)
                Text(verbatim: text.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let technical = text.technical {
                    Text(verbatim: technical)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .stageSurface(appearance, shape: .rect(cornerRadius: 8))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Lays its one child out at the child's own width, up to a cap, wrapping
/// past it. A flexible `.frame(maxWidth:)` fills the cap whatever the text
/// needs; `.fixedSize()` never wraps at all. This proposes the cap and takes
/// what the child answers with.
struct CappedWidth: Layout {
    let cap: CGFloat

    init(_ cap: CGFloat) { self.cap = cap }

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = min(proposal.width ?? cap, cap)
        return child.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard let child = subviews.first else { return }
        child.place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}

/// UX_SPEC §S5: hovering **Save how to undo this** fades "a small bookmark
/// glyph in at the stage's trailing edge".
///
/// It is the one mark in the scene that is not on the machine, because the undo
/// note is not on the machine either — and it carries no text, like everything
/// else on the stage (§4.7). The review screen's own row is what says the
/// words, and the port list is the complete path to all of it (§8.1), so this
/// is hidden from VoiceOver rather than described twice.
struct StageBookmarkGlyph: View {
    let isShowing: Bool
    let appearance: StageAppearance

    var body: some View {
        Image(systemName: "bookmark")
            .font(.title3)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .opacity(isShowing ? 1 : 0)
            .animation(
                appearance.reduceMotion ? nil : .smooth(duration: 0.18), value: isShowing
            )
            // It sits over the render surface, and a transparent glyph that
            // swallowed a click would take a receptacle away from the pointer.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
