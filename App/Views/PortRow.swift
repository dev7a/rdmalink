//
//  PortRow.swift
//
//  One receptacle. A real button on every screen, so the list is a complete
//  path to everything the 3D stage offers (UX_SPEC §8.1, §8.3).
//
//  The row never reorders and never resizes. Only the symbol, the detail line
//  and the trailing control change, and they cross-fade in 180 ms (§2.3, §7.4).
//

import SwiftUI

struct PortRow: View {
    let presentation: PortRowPresentation
    let showsTechnicalNames: Bool
    /// §4.5: a USB-only row never takes a selection, and is drawn at 45 %.
    var isThunderbolt = true
    var isSelected = false
    var isHovered = false
    var select: () -> Void = {}
    var hover: (Bool) -> Void = { _ in }

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 10) {
                PortRowSymbol(name: presentation.symbol, style: presentation.symbolStyle)
                VStack(alignment: .leading, spacing: 1) {
                    Text(presentation.positionName)
                    PortRowDetailLine(
                        detail: presentation.detail,
                        technicalSuffix: showsTechnicalNames ? presentation.technicalSuffix : nil
                    )
                }
                Spacer(minLength: 0)
            }
            .opacity(isThunderbolt ? 1 : 0.45)
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .contentShape(.rect)
            .background(highlight, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover(perform: hover)
        .accessibilityLabel(Text(presentation.accessibilityLabel))
        .accessibilityValue(Text(verbatim: presentation.accessibilityValue ?? ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .animation(.smooth(duration: 0.18), value: presentation)
        .animation(.smooth(duration: 0.15), value: isSelected)
        .animation(.smooth(duration: 0.15), value: isHovered)
    }

    /// §2.4 and §4.6: the row highlights for the same two reasons the
    /// receptacle does, and selection replaces hover on both.
    private var highlight: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.tint.opacity(0.18)) }
        if isHovered { return AnyShapeStyle(.quaternary) }
        return AnyShapeStyle(.clear)
    }
}

struct PortRowSymbol: View {
    let name: String
    var style: PortSymbolStyle = .secondary

    var body: some View {
        Image(systemName: name)
            .symbolRenderingMode(.hierarchical)
            .imageScale(.medium)
            .foregroundStyle(shapeStyle)
            .frame(width: 20, alignment: .center)
            .accessibilityHidden(true)
    }

    private var shapeStyle: AnyShapeStyle {
        switch style {
        case .secondary: AnyShapeStyle(.secondary)
        case .tertiary: AnyShapeStyle(.tertiary)
        case .accent: AnyShapeStyle(.tint)
        case .attention: AnyShapeStyle(.orange)
        }
    }
}

/// `<state> · <bridge membership>` or `<state> · <fe80 address>`, with the
/// technical names appended in `.caption` tertiary when the toggle is on
/// (§1.3 rule 6, §3.2, §4.7).
struct PortRowDetailLine: View {
    let detail: PortRowDetail
    let technicalSuffix: String?

    var body: some View {
        line
            .font(.callout)
            .foregroundStyle(.secondary)
            // §8.5: the address wraps at a colon group and is never truncated
            // with an ellipsis. A half-shown address is worse than a wrapped one.
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    /// The middle dots are part of §S1's copy, so the pieces are interpolated
    /// into one `Text` rather than glued together: interpolation keeps each
    /// run's own font — the address is `.body.monospaced()` (§3.2) and the
    /// technical suffix is `.caption` tertiary (§1.3 rule 6).
    private var stateAndDetail: Text {
        if let membership = detail.membership {
            Text("\(Text(detail.state)) · \(Text(membership))")
        } else if let address = detail.address {
            Text("\(Text(detail.state)) · \(Text(verbatim: address).font(.body.monospaced()))")
        } else {
            Text(detail.state)
        }
    }

    private var line: Text {
        guard let technicalSuffix else { return stateAndDetail }
        let suffix = Text(verbatim: technicalSuffix).font(.caption).foregroundStyle(.tertiary)
        return Text("\(stateAndDetail)  \(suffix)")
    }
}
