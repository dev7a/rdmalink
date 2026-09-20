//
//  GroupedSection.swift
//
//  The grouped inset section the assistant column is built from: a footnote
//  header over a rounded surface of rows (UX_SPEC §2.3, §3.1, §3.2).
//

import SwiftUI

struct GroupedSection<Content: View>: View {
    private let header: LocalizedStringResource
    private let content: Content

    init(header: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(header)
                .font(.footnote)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: .rect(cornerRadius: 8))
        }
    }
}

/// The hairline between two rows of a `GroupedSection`, inset past the symbol
/// column so it reads as one group rather than a stack of boxes.
struct RowDivider: View {
    var leadingInset: CGFloat = 12

    var body: some View {
        Divider().padding(.leading, leadingInset)
    }
}
