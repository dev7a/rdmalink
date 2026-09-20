//
//  PortList.swift
//
//  The permanent port list: every receptacle on this Mac, in physical order,
//  grouped by face, present on every screen and scrolling on its own when it
//  cannot fit (UX_SPEC §2.3 band 3, §2.4).
//

import SwiftUI
import RDMALinkCore

struct PortList: View {
    let ports: [ThunderboltPort]
    let isProbing: Bool
    let showsTechnicalNames: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isProbing {
                    PortListSkeleton()
                } else {
                    ForEach(PortGrouping.groups(for: ports)) { group in
                        PortGroupSection(
                            header: group.header,
                            ports: group.ports,
                            showsTechnicalNames: showsTechnicalNames
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

struct PortGroupSection: View {
    let header: LocalizedStringResource
    let ports: [ThunderboltPort]
    let showsTechnicalNames: Bool

    var body: some View {
        GroupedSection(header: header) {
            ForEach(Array(ports.enumerated()), id: \.element.id) { index, port in
                if index > 0 { RowDivider(leadingInset: 42) }
                PortRow(
                    presentation: PortRowPresentation(port: port),
                    showsTechnicalNames: showsTechnicalNames
                )
            }
        }
    }
}

/// Three generic rows while the receptacle count is still unknown (§S0).
struct PortListSkeleton: View {
    var body: some View {
        GroupedSection(header: "Thunderbolt ports") {
            ForEach(0..<3) { index in
                if index > 0 { RowDivider(leadingInset: 42) }
                SkeletonRow()
            }
        }
    }
}

struct SkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PortRowSymbol(name: "circle.dotted", isTertiary: true)
            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(.quaternary).frame(width: 130, height: 10)
                Capsule().fill(.quaternary).frame(width: 190, height: 9)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .accessibilityHidden(true)
    }
}
