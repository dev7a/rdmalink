//
//  ThisMacBadge.swift
//
//  The toolbar's identity anchor: a quiet capsule, not a button, saying which
//  machine you are editing (UX_SPEC §2.2).
//

import SwiftUI

struct ThisMacBadge: View {
    var body: some View {
        Text("This Mac")
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: .capsule)
            .help("RDMALink only ever changes the Mac it's running on.")
    }
}
