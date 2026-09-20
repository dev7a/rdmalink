//
//  SituationSection.swift
//
//  The rows between the `This Mac` section and the port list: what is going on
//  right now that the user would want to know, phrased as a situation and never
//  as an alarm (UX_SPEC §S1, §7.4).
//
//  No symbol and no colour. Every one of these is a sentence about the world,
//  not a fault, and §6.1's symbol treatment belongs to refusals.
//

import SwiftUI

struct SituationSection: View {
    let situations: [Situation]

    var body: some View {
        if !situations.isEmpty {
            GroupedSection {
                ForEach(Array(situations.enumerated()), id: \.element.id) { index, situation in
                    if index > 0 { RowDivider() }
                    Text(situation.text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                }
            }
            .transition(.opacity)
        }
    }
}
