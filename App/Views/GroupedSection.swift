//
//  GroupedSection.swift
//
//  The grouped inset section the assistant column is built from: a footnote
//  header over a rounded surface of rows (UX_SPEC §2.3, §3.1, §3.2).
//

import SwiftUI

struct GroupedSection<Content: View>: View {
    private let header: LocalizedStringResource?
    private let content: Content

    /// Situation rows have no header of their own (§S1), so the header is
    /// optional rather than an empty string.
    init(header: LocalizedStringResource? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let header {
                Text(header)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: .rect(cornerRadius: 8))
        }
    }
}

/// The hairline between two rows of a `GroupedSection`, inset past the symbol
/// column so it reads as one group rather than a stack of boxes.
struct RowDivider: View {
    var leadingInset: CGFloat = 12

    var body: some View {
        Divider().padding(.leading, leadingInset)
    }
}

extension View {
    /// §2.3 band 3: a small action beside a row's words — borderless, small,
    /// and in the accent color. A borderless button draws its title in gray
    /// in a key window, the same gray as the subtitle beside it, and
    /// clickable text that looks like a label is never found. Port rows,
    /// situation rows, the checks, the change log, Ready and `Show Me` all
    /// take it from here.
    func inlineAction() -> some View {
        modifier(InlineAction())
    }
}

/// The accent is set explicitly, and an explicit foreground style also
/// overrides the dimming a borderless button gets when it is disabled — so a
/// row's set-up button with two Macs connected (§S1) drew exactly like one
/// that works. A disabled inline action is drawn in `.tertiary` instead, the
/// way a disabled control's title is (§2.3 band 3, §3.1). The environment is
/// read where the modifier sits, so a `.disabled` applied after
/// `inlineAction()` reaches it.
private struct InlineAction: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
    }
}
