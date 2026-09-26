//
//  ThisMacSection.swift
//
//  The hub's three read-only rows: the RDMA switch, the Thunderbolt Bridge,
//  and what is ready for RDMA (UX_SPEC §S1).
//

import SwiftUI

struct ThisMacSection: View {
    let rows: [ThisMacRowModel]
    let perform: (ThisMacRowAction) -> Void

    var body: some View {
        GroupedSection(header: "This Mac") {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { RowDivider() }
                ThisMacRow(row: row, perform: perform)
            }
        }
    }
}

struct ThisMacRow: View {
    let row: ThisMacRowModel
    let perform: (ThisMacRowAction) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            // §2.3 band 3: `Turn It On…` and `Tell Me More` are inline
            // actions beside the row's words, drawn as every other one in the
            // column is — S7's `Turn It On…` included — in the accent.
            if let action = row.action {
                Button(title(for: action)) { perform(action) }
                    .inlineAction()
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .animation(.smooth(duration: 0.18), value: row)
    }

    private func title(for action: ThisMacRowAction) -> LocalizedStringResource {
        switch action {
        case .turnItOn: "Turn It On…"
        case .tellMeMore: "Tell Me More"
        }
    }
}
