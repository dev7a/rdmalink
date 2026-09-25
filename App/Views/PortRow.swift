//
//  PortRow.swift
//
//  One receptacle. A real button on every screen, so the list is a complete
//  path to everything the 3D stage offers (UX_SPEC §8.1, §8.3), with §S1's
//  trailing buttons beside it — real buttons of their own, not decorations
//  inside the row's.
//
//  The row never reorders and never resizes. Only the symbol, the detail line
//  and the trailing control change, and they cross-fade in 180 ms (§2.3, §7.4).
//

import SwiftUI

struct PortRow: View {
    let presentation: PortRowPresentation
    let showsTechnicalNames: Bool
    /// §2.3 band 3. **Full** carries the detail line and the trailing buttons;
    /// **compact** is "symbol, title, and a short trailing badge only" — which
    /// is also why an action button has no business in it: §2.6 raises Adopt,
    /// Restore and Return to Bridge from the hub, never over a running
    /// assistant.
    var density: PortListDensity = .full
    /// The compact badge for this row, when it has one.
    var badge: LocalizedStringResource?
    /// §4.5: a USB-only row never takes a selection, and is drawn at 45 %.
    var isThunderbolt = true
    var isSelected = false
    var isHovered = false
    /// §S4, both ways round. On the picker: a row that cannot be chosen,
    /// "dimmed with an explanatory subtitle". After the picker: a row that is
    /// not the chosen one while the choice is frozen — "the list and the model
    /// are status there, not a picker". Either way it is drawn at the same
    /// 45 % as a USB-only row.
    var isDimmed = false
    var select: () -> Void = {}
    var hover: (Bool) -> Void = { _ in }
    /// The hub's actions, when this row is in the hub. The list is also drawn
    /// by screens that offer none, so it is read as an optional rather than
    /// demanded from the environment.
    @Environment(HubActionsModel.self) private var actions: HubActionsModel?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: select) {
                HStack(alignment: .top, spacing: 10) {
                    PortRowSymbol(name: presentation.symbol, style: presentation.symbolStyle)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(presentation.positionName)
                        if density == .full {
                            PortRowDetailLine(
                                detail: presentation.detail,
                                technicalSuffix: showsTechnicalNames
                                    ? presentation.technicalSuffix : nil
                            )
                        }
                    }
                    Spacer(minLength: 0)
                    if density == .compact, let badge {
                        Text(badge)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(isThunderbolt && !isDimmed ? 1 : 0.45)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(presentation.accessibilityLabel))
            .accessibilityValue(Text(verbatim: presentation.accessibilityValue ?? ""))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            // §6.2 R31: on a Mac RDMALink does not recognize no row carries a
            // button — absent, not disabled — because every one of them writes.
            if density == .full, let actions, !actions.isUnrecognized {
                PortRowActions(actions: presentation.actions, hub: actions)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .background(highlight, in: .rect(cornerRadius: 6))
        .onHover(perform: hover)
        .animation(.smooth(duration: 0.18), value: presentation)
        .animation(.smooth(duration: 0.18), value: density)
        .animation(.smooth(duration: 0.15), value: isSelected)
        .animation(.smooth(duration: 0.15), value: isHovered)
        .animation(.smooth(duration: 0.18), value: isDimmed)
    }

    /// §2.4 and §4.6: the row highlights for the same two reasons the
    /// receptacle does, and selection replaces hover on both.
    private var highlight: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.tint.opacity(0.18)) }
        if isHovered { return AnyShapeStyle(.quaternary) }
        return AnyShapeStyle(.clear)
    }
}

/// §S1's trailing buttons: `Adopt…` · `Restore…` · `Return to Bridge…` ·
/// `Stop Managing…` · `Set It Up Again`, borderless so the row stays a row,
/// and in the accent so they read as buttons (§2.3 band 3).
struct PortRowActions: View {
    let actions: [HubAction]
    let hub: HubActionsModel

    var body: some View {
        if !actions.isEmpty {
            HStack(spacing: 8) {
                ForEach(actions) { action in
                    Button(action.title) { hub.perform(action) }
                        .inlineAction()
                }
            }
            .transition(.opacity)
        }
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
        var text = Text(detail.state)
        for phrase in [detail.link, detail.membership].compactMap({ $0 }) {
            text = Text("\(text) · \(Text(phrase))")
        }
        if let address = detail.address {
            text = Text("\(text) · \(Text(verbatim: address).font(.body.monospaced()))")
        }
        return text
    }

    private var line: Text {
        guard let technicalSuffix else { return stateAndDetail }
        let suffix = Text(verbatim: technicalSuffix).font(.caption).foregroundStyle(.tertiary)
        return Text("\(stateAndDetail)  \(suffix)")
    }
}
