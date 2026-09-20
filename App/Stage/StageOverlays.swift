//
//  StageOverlays.swift
//
//  The only things allowed to float over the stage: the face selector, the
//  Fit / Reset View pair, and the narration capsule (UX_SPEC §2.3, §9.1).
//  Nothing else. No badge, no legend, no step indicator.
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
        background {
            if appearance.reduceTransparency {
                Capsule().fill(.windowBackground)
            } else {
                Capsule().fill(.regularMaterial)
            }
        }
        .overlay {
            if appearance.increaseContrast {
                Capsule().strokeBorder(.secondary, lineWidth: 1)
            }
        }
        .clipShape(.capsule)
    }
}
