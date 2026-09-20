//
//  ReviewPreview.swift
//
//  S5's hover-to-preview, and the symbols its four rows carry (UX_SPEC §S5).
//
//  The review's copy — headline, body, the four rows, the chips, the warnings,
//  the technical names and the default button's title — belongs to Core's
//  `SetUpPortsPlan`, which holds the spec's table verbatim. Nothing is
//  re-worded here; this is what the *screen* adds on top of it.
//

import Foundation

/// The four changes, in the order §S5 lists them. The plan's rows arrive in
/// that order, so a row's position is its meaning.
enum ReviewChange: Int, Sendable, Equatable, CaseIterable {
    case undoNote
    case leaveBridge
    case service
    case addresses

    init?(rowIndex: Int) {
        self.init(rawValue: rowIndex)
    }

    /// §3.3 has no entry for three of these four meanings — its table maps the
    /// states the hub already had. These stay inside SF Symbols and are always
    /// paired with text, as §3.3 requires, and are **owed a line in that
    /// table** from the spec owner.
    var symbol: String {
        switch self {
        case .undoNote: "arrow.uturn.backward"
        case .leaveBridge: "link"
        case .service: "plus.circle"
        case .addresses: "network"
        }
    }
}

/// What a hovered change row previews on the model, silently and reversibly:
/// a bookmark glyph, the ribbon fading away, an accent node, a hairline ring.
///
/// `StageModel` has no preview channel yet, so `WizardWorkingArea` hands these
/// to a closure the window supplies. **Owed from the stage owner:** the four
/// previews §S5 describes.
enum ReviewPreview: Sendable, Equatable {
    case note
    case leaveBridge
    case service
    case addresses

    init(_ change: ReviewChange) {
        switch change {
        case .undoNote: self = .note
        case .leaveBridge: self = .leaveBridge
        case .service: self = .service
        case .addresses: self = .addresses
        }
    }
}

extension StagePreview {
    /// S5's four rows, as the stage draws them.
    init(_ preview: ReviewPreview) {
        switch preview {
        case .note: self = .note
        case .leaveBridge: self = .leaveBridge
        case .service: self = .service
        case .addresses: self = .addresses
        }
    }
}
