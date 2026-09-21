//
//  SituationSection.swift
//
//  The rows between the `This Mac` section and the port list: what is going on
//  right now that the user would want to know, phrased as a situation and never
//  as an alarm (UX_SPEC §S1, §7.4).
//
//  No symbol and no colour. Every one of these is a sentence about the world,
//  not a fault, and §6.1's symbol treatment belongs to refusals. Two of them
//  carry buttons, and those are the way out of the situation rather than an
//  acknowledgement of it.
//

import SwiftUI

struct SituationSection: View {
    let situations: [Situation]
    @Environment(HubActionsModel.self) private var hub: HubActionsModel?

    var body: some View {
        if !situations.isEmpty {
            GroupedSection {
                ForEach(Array(situations.enumerated()), id: \.element.id) { index, situation in
                    if index > 0 { RowDivider() }
                    SituationRow(situation: situation, hub: hub)
                }
            }
            .transition(.opacity)
        }
    }
}

struct SituationRow: View {
    let situation: Situation
    let hub: HubActionsModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(situation.text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // §6.2 R31: the row still states the situation on a Mac
                // RDMALink does not recognize, but its way out — `Show Me`,
                // `Set It Up Again`, `Forget This Port` — is absent, because
                // there is no model to show and nothing is written.
                if let hub, !hub.isUnrecognized {
                    ForEach(situation.actions) { action in
                        Button(action.title) { hub.perform(action) }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                }
            }
            if let detail = situation.detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .animation(.smooth(duration: 0.18), value: situation)
    }
}
