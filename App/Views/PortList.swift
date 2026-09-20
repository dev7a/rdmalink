//
//  PortList.swift
//
//  The permanent port list: every receptacle on this Mac, in physical order,
//  grouped by face, present on every screen and scrolling on its own when it
//  cannot fit (UX_SPEC §2.3 band 3, §2.4).
//

import AppKit
import SwiftUI
import RDMALinkCore

/// §2.3 band 3's two densities. Same rows, same order, same place, less ink:
/// **full** on the hub, Choose a port and Identify; **compact** everywhere the
/// list is context rather than the subject.
enum PortListDensity: Sendable, Equatable {
    case full
    case compact
}

struct PortList: View {
    let ports: [PortSnapshot]
    /// §2.4: selecting a row lights the receptacle, hovering a receptacle
    /// highlights the row. One model carries both directions.
    let stage: StageModel
    let isProbing: Bool
    let showsTechnicalNames: Bool
    var density: PortListDensity = .full
    /// §S5: "the target port(s) marked **About to change**".
    var aboutToChange: Set<String> = []
    /// §4.5: clicking a USB-only row produces R3 in the working area, exactly
    /// as clicking the receptacle on the stage does.
    var onUSBClick: (String) -> Void = { _ in }
    /// §S4's ⌘-click and ⇧-click, when the screen showing the list has a
    /// multi-selection to extend. Absent everywhere else, which is why a
    /// modified click on the hub is an ordinary one.
    var onExtend: ((String) -> Void)?

    /// §2.4: the list is the canonical answer, so a selection made on the
    /// stage has to be somewhere the user can see. The row a click came from,
    /// so clicking a row never scrolls it out from under the pointer.
    @State private var rowInitiated: String?
    /// Which edges of the list have rows past them right now.
    @State private var fold = ScrollFold()

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
                                density: density,
                                aboutToChange: aboutToChange,
                                onUSBClick: onUSBClick,
                                onExtend: onExtend,
                                onRowSelect: { rowInitiated = $0 }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            // §2.3: the list "scrolls independently if it cannot fit; it is
            // never truncated away". At the default window a situation row
            // leaves the hub's list a little short, and macOS's overlay
            // scrollers show nothing until the list moves — so a row under
            // the fold was indistinguishable from a group that ended there.
            // The edge with more past it is faded, which is how the system's
            // own folds say "there is more"; a list that fits is untouched.
            .onScrollGeometryChange(for: ScrollFold.self) { geometry in
                ScrollFold(geometry)
            } action: { _, current in
                fold = current
            }
            .mask { ScrollFoldMask(fold: fold) }
            .animation(.smooth(duration: 0.18), value: fold)
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
    var density: PortListDensity = .full
    var aboutToChange: Set<String> = []
    var onUSBClick: (String) -> Void = { _ in }
    var onExtend: ((String) -> Void)?
    /// Told before the selection moves, so the list does not scroll a row the
    /// pointer is already on.
    var onRowSelect: (String) -> Void = { _ in }

    var body: some View {
        GroupedSection(header: header) {
            ForEach(Array(ports.enumerated()), id: \.element.id) { index, port in
                if index > 0 { RowDivider(leadingInset: 42) }
                let presentation = PortRowPresentation(snapshot: port)
                PortRow(
                    presentation: presentation,
                    showsTechnicalNames: showsTechnicalNames,
                    density: density,
                    badge: aboutToChange.contains(port.id)
                        ? "About to change"
                        : presentation.compactBadge,
                    isThunderbolt: port.port.isThunderbolt,
                    isSelected: stage.selectedID == port.id,
                    isHovered: stage.hoveredID == port.id,
                    // §4.5: a USB-only row is not selectable, and the click
                    // is not swallowed either — it produces the same R3 copy
                    // the stage's own click does.
                    select: {
                        guard port.port.isThunderbolt else { return onUSBClick(port.id) }
                        // §S4's multi-select: ⌘-click and ⇧-click add to the
                        // selection rather than replacing it, on the screen
                        // that has one to add to.
                        if let onExtend, Self.isExtendingClick() {
                            onExtend(port.id)
                            return
                        }
                        onRowSelect(port.id)
                        stage.select(port.id)
                    },
                    hover: { stage.hover($0 ? port.id : nil) }
                )
                .id(port.id)
            }
        }
    }
}

extension PortGroupSection {
    /// Whether the click that is being handled carried ⌘ or ⇧. SwiftUI's
    /// button action does not describe the click, so the modifiers are read
    /// from the event that is still current while it runs.
    static func isExtendingClick() -> Bool {
        let flags = NSEvent.modifierFlags
        return flags.contains(.command) || flags.contains(.shift)
    }
}

/// Whether the list has rows past its top or bottom edge.
struct ScrollFold: Equatable {
    var above = false
    var below = false

    init() {}

    init(_ geometry: ScrollGeometry) {
        let top = geometry.contentOffset.y + geometry.contentInsets.top
        let bottom = top + geometry.containerSize.height
        above = top > 1
        below = bottom < geometry.contentSize.height - 1
    }
}

/// Opaque over the rows, fading to nothing over the last points before an
/// edge that has more past it. Applied as a mask, so the group's own
/// background fades with its rows and nothing is drawn over them.
struct ScrollFoldMask: View {
    let fold: ScrollFold

    private static let depth: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: fold.above ? Self.depth : 0)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: fold.below ? Self.depth : 0)
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
