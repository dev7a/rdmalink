//
//  PortRow.swift
//
//  One receptacle. A real button on every screen, so the list is a complete
//  path to everything the 3D stage offers (UX_SPEC §8.1, §8.3).
//

import SwiftUI

struct PortRow: View {
    let presentation: PortRowPresentation
    let showsTechnicalNames: Bool

    var body: some View {
        Button {
            // ML1: selecting a row lights the matching receptacle on the stage.
        } label: {
            HStack(alignment: .top, spacing: 10) {
                PortRowSymbol(
                    name: presentation.symbol,
                    isTertiary: presentation.usesTertiarySymbol
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.positionName)
                    PortRowDetail(
                        state: presentation.state,
                        membership: presentation.membership,
                        technicalName: showsTechnicalNames ? presentation.technicalName : nil
                    )
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }
}

struct PortRowSymbol: View {
    let name: String
    let isTertiary: Bool

    var body: some View {
        Image(systemName: name)
            .symbolRenderingMode(.hierarchical)
            .imageScale(.medium)
            .foregroundStyle(isTertiary ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
            .frame(width: 20, alignment: .center)
            .accessibilityHidden(true)
    }
}

/// `<link state> · <bridge membership>`, with the BSD name appended in
/// `.caption` tertiary when `Show technical names` is on (§1.3 rule 6, §4.7).
struct PortRowDetail: View {
    let state: LocalizedStringResource
    let membership: LocalizedStringResource?
    let technicalName: String?

    var body: some View {
        detail
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var detail: Text {
        let line = membership.map { membership in
            Text("\(String(localized: state)) · \(String(localized: membership))")
        } ?? Text(state)
        guard let technicalName else { return line }
        let suffix = Text(technicalName).font(.caption).foregroundStyle(.tertiary)
        return Text("\(line) \(suffix)")
    }
}
