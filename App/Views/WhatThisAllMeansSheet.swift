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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What this all means")
                .font(.title2.weight(.semibold))
            TwoMacsIllustration()
            VStack(alignment: .leading, spacing: 16) {
                ExplainerSection(
                    title: "RDMA over Thunderbolt",
                    detail: "RDMA lets two Macs move data between them without troubling either one's processor very much. Over a Thunderbolt 5 cable that's quick enough to feel like a local disk. Tools like RotorFS, exo and MLX clusters use it."
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
                    detail: "It's a link-local IPv6 address. It only means anything down that one cable, which is exactly what we want — the port is now its own small private network. That's also why IPv4 can be off entirely."
                )
            }
            Text("You don't need to know any of this to use RDMALink.")
                .font(.body)
                .foregroundStyle(.secondary)
            HStack {
                Spacer(minLength: 0)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, alignment: .leading)
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
