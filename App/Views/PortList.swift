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
    let ports: [PortSnapshot]
    /// §2.4: selecting a row lights the receptacle, hovering a receptacle
    /// highlights the row. One model carries both directions.
    let stage: StageModel
    let isProbing: Bool
    let showsTechnicalNames: Bool
    /// §4.5: clicking a USB-only row produces R3 in the working area, exactly
    /// as clicking the receptacle on the stage does.
    var onUSBClick: (String) -> Void = { _ in }

    /// §2.4: the list is the canonical answer, so a selection made on the
    /// stage has to be somewhere the user can see. The row a click came from,
    /// so clicking a row never scrolls it out from under the pointer.
    @State private var rowInitiated: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if isProbing {
                        PortListSkeleton()
                    } else {
                        ForEach(PortGrouping.groups(for: ports)) { group in
                            PortGroupSection(
                                header: group.header,
                                ports: group.ports,
                                stage: stage,
                                showsTechnicalNames: showsTechnicalNames,
                                onUSBClick: onUSBClick,
                                onRowSelect: { rowInitiated = $0 }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: stage.selectedID) { _, id in
                let cameFromARow = rowInitiated == id
                rowInitiated = nil
                guard !cameFromARow, let id else { return }
                withAnimation(.smooth(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}

struct PortGroupSection: View {
    let header: LocalizedStringResource
    let ports: [PortSnapshot]
    let stage: StageModel
    let showsTechnicalNames: Bool
    var onUSBClick: (String) -> Void = { _ in }
    /// Told before the selection moves, so the list does not scroll a row the
    /// pointer is already on.
    var onRowSelect: (String) -> Void = { _ in }

    var body: some View {
        GroupedSection(header: header) {
            ForEach(Array(ports.enumerated()), id: \.element.id) { index, port in
                if index > 0 { RowDivider(leadingInset: 42) }
                PortRow(
                    presentation: PortRowPresentation(snapshot: port),
                    showsTechnicalNames: showsTechnicalNames,
                    isThunderbolt: port.port.isThunderbolt,
                    isSelected: stage.selectedID == port.id,
                    isHovered: stage.hoveredID == port.id,
                    // §4.5: a USB-only row is not selectable, and the click
                    // is not swallowed either — it produces the same R3 copy
                    // the stage's own click does.
                    select: {
                        if port.port.isThunderbolt {
                            onRowSelect(port.id)
                            stage.select(port.id)
                        } else {
                            onUSBClick(port.id)
                        }
                    },
                    hover: { stage.hover($0 ? port.id : nil) }
                )
                .id(port.id)
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
            PortRowSymbol(name: "circle.dotted", style: .tertiary)
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(.quaternary).frame(width: 130, height: 10)
                Capsule().fill(.quaternary).frame(width: 190, height: 9)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .accessibilityHidden(true)
    }
}
