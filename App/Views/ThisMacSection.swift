//
//  ThisMacSection.swift
//
//  The hub's three read-only rows: the RDMA switch, the Thunderbolt Bridge,
//  and what is ready for RDMA (UX_SPEC §S1).
//

import SwiftUI
import RDMALinkCore

struct ThisMacSection: View {
    let rdma: RDMAStatus
    let ports: [ThunderboltPort]

    var body: some View {
        GroupedSection(header: "This Mac") {
            if let rdmaRow = ThisMacPresentation.rdmaRow(rdma) {
                ThisMacRow(text: rdmaRow)
                RowDivider()
            }
            ThisMacRow(text: ThisMacPresentation.bridgeRow(ports))
            RowDivider()
            // ML2 owns the baseline store, so nothing can be ready yet.
            ThisMacRow(text: "Ports ready for RDMA — None yet")
        }
    }
}

struct ThisMacRow: View {
    let text: LocalizedStringResource

    var body: some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
    }
}
