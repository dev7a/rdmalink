//
//  RefusalCard.swift
//
//  The one shape every refusal takes (UX_SPEC §6.1): inline in the working
//  area, a hierarchical symbol in `.secondary` or `.orange`, a headline that
//  names the situation, one short paragraph of why, and a button row whose
//  primary is always a real action. Never a filled red badge, never a
//  full-bleed alarm, and never a "Continue Anyway".
//

import AppKit
import SwiftUI

/// §3.1: `attention` is `.orange` and lives in the panel only. `stop` (`.red`)
/// is used nowhere in this app.
enum RefusalTint {
    case secondary
    case attention
}

struct RefusalCard<Buttons: View>: View {
    let symbol: String
    var tint: RefusalTint = .secondary
    let headline: LocalizedStringResource
    /// §6.1 rule 7: a refusal that follows a partial write states the
    /// rollback first, before explaining anything else — under the headline,
    /// which still leads the screen (§2.3 band 1), and ahead of the paragraph.
    var lead: LocalizedStringResource?
    let message: LocalizedStringResource
    /// A second paragraph some refusals grow into — R24 after three tries.
    var extraMessage: LocalizedStringResource?
    /// Leading in the working area. Inside a sheet the card's buttons sit
    /// bottom-trailing like every other sheet's button row (§2.6).
    var buttonRowAlignment: Alignment = .leading
    /// §6.1 rule 3: a card under a screen's own headline — the picker's R3,
    /// R16 and R26, the hub's R3 tip and R22, a refusal under the Adopt
    /// sheet's headline — steps its headline down to `.headline`, so no
    /// screen has two headlines of equal weight. A card that replaces the
    /// screen keeps `.title2` and, in the assistant, the step label on it.
    var isNested = false
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isNested {
                headlineRow
            } else {
                HeadlineRow { headlineRow }
            }
            if let lead {
                Text(lead)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let extraMessage {
                Text(extraMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) { buttons }
                .frame(maxWidth: .infinity, alignment: buttonRowAlignment)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headlineRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .imageScale(.medium)
                .foregroundStyle(symbolStyle)
                .accessibilityHidden(true)
            Text(headline)
                .font(isNested ? .headline : .title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var symbolStyle: AnyShapeStyle {
        switch tint {
        case .secondary: AnyShapeStyle(.secondary)
        case .attention: AnyShapeStyle(.orange)
        }
    }
}

/// `Copy Details` → `Copied`. Present on every failure refusal, and its payload
/// always carries the technical names regardless of the "Show technical names"
/// toggle (§6.1 rule 8).
struct CopyDetailsButton: View {
    let details: () -> String

    var body: some View {
        CopyButton(title: "Copy Details", payload: details)
    }
}

/// §9.14: "The button swaps to a checkmark and the word for two seconds, then
/// quietly goes back. No toast, no banner, no sound."
///
/// It stays *clickable* while it reads `Copied`: "Copied" is a state the
/// button passes through, not the end of it, and a user who pasted into the
/// wrong window has to be able to copy again.
struct CopyButton: View {
    let title: LocalizedStringResource
    let payload: () -> String
    @State private var hasCopied = false
    @State private var revert: Task<Void, Never>?

    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(payload(), forType: .string)
            hasCopied = true
            revert?.cancel()
            revert = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                hasCopied = false
            }
        } label: {
            if hasCopied {
                Label("Copied", systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .animation(.smooth(duration: 0.15), value: hasCopied)
        .onDisappear { revert?.cancel() }
    }
}

/// The app's one way out, so every `Quit` ends the session the same way.
/// §S1's hub footer carries it in every hub state, and so do the refusals that
/// leave nothing else to do (§6.2 R24, R25).
struct QuitButton: View {
    var body: some View {
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }
}
