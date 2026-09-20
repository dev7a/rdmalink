//
//  StagePlaceholder.swift
//
//  The left 58 % of the window until the RealityKit stage lands. A plain
//  window-background surface with the archetype's Mac symbol, so the split,
//  the minimum widths and the balance of the layout are real from ML0.
//

import SwiftUI
import RDMALinkCore

struct StagePlaceholder: View {
    let archetype: Archetype?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 92, weight: .ultraLight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(verbatim: "3D stage lands in ML1")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }

    private var symbolName: String {
        switch archetype {
        case .studioFour, .studioSix: "macstudio"
        case .mini: "macmini"
        case .notebook: "macbook"
        case .unknown, nil: "desktopcomputer"
        }
    }
}
