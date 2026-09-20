//
//  WorkingArea.swift
//
//  Band 2 of the assistant column: the only band that changes between steps
//  (UX_SPEC §2.3). In ML0 it carries S0 while the probe runs, the hub once it
//  lands, and refusal R24 when this Mac reports no Thunderbolt hardware.
//

import SwiftUI
import RDMALinkCore

struct WorkingArea: View {
    let phase: InventoryModel.Phase
    let isSlowProbe: Bool
    let rdma: RDMAStatus
    let ports: [ThunderboltPort]

    var body: some View {
        switch phase {
        case .probing:
            ProbingWorkingArea(isSlow: isSlowProbe)
        case .ready:
            HubWorkingArea(rdma: rdma, ports: ports)
        case .noThunderboltHardware:
            NoHardwareWorkingArea()
        }
    }
}

/// S0 — Getting to know this Mac.
struct ProbingWorkingArea: View {
    let isSlow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Getting to know this Mac")
                    .font(.title2.weight(.semibold))
            }
            Text(
                isSlow
                    ? "Still looking. Some Thunderbolt information takes a few seconds to arrive."
                    : "Checking the Thunderbolt ports, the network, and whether RDMA is turned on."
            )
            .font(.body)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// S1 — Overview, first run.
struct HubWorkingArea: View {
    let rdma: RDMAStatus
    let ports: [ThunderboltPort]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Let's set up a Thunderbolt link")
                    .font(.title2.weight(.semibold))
                Text("RDMALink prepares one Thunderbolt port on this Mac so it can carry RDMA straight to another Mac. You'll do the same on the other Mac afterwards.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ThisMacSection(rdma: rdma, ports: ports)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// R24 — I can't see the Thunderbolt hardware. `Check Again` in the toolbar is
/// the recovery; the refusal's own button row lands with ML1.
struct NoHardwareWorkingArea: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("I can't see this Mac's Thunderbolt hardware")
                    .font(.title2.weight(.semibold))
            }
            Text("macOS isn't reporting any Thunderbolt controllers, which RDMALink needs before it will touch anything. A restart often sorts this out.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
