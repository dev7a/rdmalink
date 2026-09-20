//
//  ThisMacBadge.swift
//
//  The toolbar's identity anchor: a quiet capsule, not a button, saying which
//  machine you are editing (UX_SPEC §2.2).
//

import SwiftUI

struct ThisMacBadge: View {
    /// §3.6 and §8.6: "both floating capsules and the `This Mac` badge become
    /// opaque" under Reduce Transparency. A translucent identity anchor over
    /// the title bar is exactly what the setting exists to remove.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Text("This Mac")
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                if reduceTransparency {
                    Capsule().fill(.windowBackground)
                } else {
                    Capsule().fill(.thinMaterial)
                }
            }
            .clipShape(.capsule)
            .help("RDMALink only ever changes the Mac it's running on.")
    }
}
