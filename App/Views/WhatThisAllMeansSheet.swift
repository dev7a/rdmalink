//
//  WhatThisAllMeansSheet.swift
//
//  S13 — the one explainer, reached from the hub's link row, from the toolbar's
//  Help button and from the Help menu. Reading material: no 3D, no live state,
//  nothing about this particular Mac (UX_SPEC §S13).
//

import SwiftUI

struct WhatThisAllMeansSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// The tallest the reading region grows (§S13, §2.6). A window at §2.1's
    /// 600 pt minimum loses 52 pt to the unified toolbar the sheet hangs
    /// beneath, and `Done` with its margin below the scroll takes 48 more:
    /// 500 pt is what is left, and 480 keeps a little of it spare. The sheet
    /// measures 528 pt this way; before it scrolled it measured 738, taller
    /// than §2.1's default 720 pt window, never mind the minimum.
    private static let readingHeight: CGFloat = 480

    /// Which edges of the reading have more past them. The same fold as the
    /// column's working area and port list, so every region in the app that
    /// scrolls reads the same way — an edge fades rather than slicing a line
    /// of text against the button row.
    @State private var fold = ScrollFold()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                reading
                    .padding([.horizontal, .top], 24)
                    .padding(.bottom, 18)
            }
            .frame(maxHeight: Self.readingHeight)
            .onScrollGeometryChange(for: ScrollFold.self) { geometry in
                ScrollFold(geometry)
            } action: { _, current in
                fold = current
            }
            .mask { ScrollFoldMask(fold: fold) }
            .animation(.smooth(duration: 0.18), value: fold)
            // §2.6: the button row does not scroll.
            HStack {
                Spacer(minLength: 0)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(width: 560)
        // §2.6: Escape is the way out. `Done` is the only button and it is
        // Return's; Escape closes the sheet the way it closes any SwiftUI
        // sheet on macOS. Nothing here takes it: an `.onExitCommand` only
        // fires while something in the sheet has focus, and with Keyboard
        // navigation off (the default) nothing here can.
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What this all means")
                .font(.title2.weight(.semibold))
            TwoMacsIllustration()
            VStack(alignment: .leading, spacing: 16) {
                ExplainerSection(
                    title: "RDMA over Thunderbolt",
                    detail: "RDMA lets two Macs move data between them without troubling either one's processor very much. Over a Thunderbolt 5 cable that's quick enough to feel like a local disk. Tools like exo and MLX clusters use it."
                )
                ExplainerSection(
                    title: "Why take the port out of Thunderbolt Bridge?",
                    detail: "The bridge joins your Thunderbolt ports into one ordinary network, which is lovely for file sharing and wrong for this. RDMA wants a cable that belongs to it alone, so RDMALink gives the port its own service and leaves the bridge otherwise untouched. A port has to be out of every bridge, even one that isn't switched on."
                )
                ExplainerSection(
                    title: "Why only one cable between two Macs?",
                    detail: "The bridge works like a hub: whatever arrives on one Thunderbolt port is sent out of all the others. So a second Thunderbolt connection between the same two Macs — or a ring of Macs — with those ports still in the bridge gives traffic a way to go round and round for ever, eating processor time and dragging the network down. Apple says so in its technote on RDMA over Thunderbolt. One cable, no loop."
                )
                // §S13: the one link on the sheet — the claim above is Apple's
                // (TN3205), so the sheet points at it rather than asking to
                // be believed.
                Link(
                    "Apple's technote on RDMA over Thunderbolt",
                    destination: URL(string: "https://developer.apple.com/documentation/technotes/tn3205-low-latency-communication-with-rdma-over-thunderbolt")!
                )
                .font(.caption)
                ExplainerSection(
                    title: "That fe80:: address",
                    detail: "It's a link-local IPv6 address. It only means anything down that one cable, which is exactly the point — the port is now its own small private network. That's also why IPv4 can be off entirely."
                )
            }
            Text("You don't need to know any of this to use RDMALink.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ExplainerSection: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
