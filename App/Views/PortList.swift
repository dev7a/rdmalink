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
    /// Where each face's header and first row sit in the visible list, by
    /// group, so the fold can tell when a header is standing over nothing.
    @State private var groupEdges: [String: GroupEdges] = [:]

    /// The gap between one face's rows and the next face's header.
    private static let groupSpacing: CGFloat = 10

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Self.groupSpacing) {
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
                                onRowSelect: { rowInitiated = $0 },
                                onHeaderTop: { groupEdges[group.id, default: GroupEdges()].headerTop = $0 },
                                onFirstRowTop: { groupEdges[group.id, default: GroupEdges()].firstRowTop = $0 }
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
            .mask { ScrollFoldMask(fold: fold, hiddenBelow: hiddenBelow) }
            .animation(.smooth(duration: 0.18), value: fold)
            .animation(.smooth(duration: 0.18), value: hiddenBelow)
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

    /// How much of the list's bottom edge is hidden outright, under the fade.
    ///
    /// Usually nothing: the fade runs to the edge. But a face header whose
    /// rows are all past the fold can be left half-showing through the fade
    /// over a first row that is too deep in it to read — a ghost of `Front`,
    /// and then the edge — which reads as a face with no ports rather than
    /// as more list. When the edge cuts between a header and its first row
    /// like that, the fade runs as usual over the row above, and the header
    /// and everything past it is hidden outright. The cost is a blank strip
    /// under the fade where the header was, and macOS's overlay scrollers
    /// show nothing at rest to say the list goes on — so the strip is
    /// bounded: never deeper than the fade itself, and a header that starts
    /// above the fade is left alone whatever its first row does, because
    /// §2.3 band 3 says the list "is never truncated away" and a legible
    /// header over a faded row is a stronger "there is more" than a blank
    /// strip. Nothing about the rows themselves changes: same order, same
    /// density, same place.
    private var hiddenBelow: CGFloat {
        guard fold.below else { return 0 }
        let depth = ScrollFoldMask.depth
        // A header whose top is inside the fade — past its start, but not so
        // deep that nothing of it would show — over a first row that begins
        // too deep in the fade to read.
        let fadeStarts = fold.containerHeight - depth
        let headerShows = fold.containerHeight - depth / 4
        let rowReads = fold.containerHeight - depth * 3 / 4
        let faces = Set(PortGrouping.groups(for: ports).map(\.id))
        let stranded = groupEdges.compactMap { id, edges -> CGFloat? in
            guard faces.contains(id),
                  let headerTop = edges.headerTop, let firstRowTop = edges.firstRowTop,
                  headerTop > fadeStarts, headerTop < headerShows, firstRowTop > rowReads
            else { return nil }
            return headerTop
        }
        guard let headerTop = stranded.min() else { return 0 }
        return fold.containerHeight - headerTop
    }
}

/// Where one face's header and first row sit in the list's visible frame.
/// Either is `nil` until its view has reported.
struct GroupEdges: Equatable {
    var headerTop: CGFloat?
    var firstRowTop: CGFloat?
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
    /// Where the header's top edge and the first row's top edge are in the
    /// enclosing scroll view's frame, as they move — the list's fold reads
    /// them to keep a header from being stranded at its edge.
    var onHeaderTop: (CGFloat) -> Void = { _ in }
    var onFirstRowTop: (CGFloat) -> Void = { _ in }

    var body: some View {
        GroupedSection(header: header) {
            ForEach(Array(ports.enumerated()), id: \.element.id) { index, port in
                if index > 0 { RowDivider(leadingInset: 42) }
                if index == 0 {
                    row(port)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .scrollView).minY
                        } action: { onFirstRowTop($0) }
                } else {
                    row(port)
                }
            }
        }
        // The section's top edge is the header's.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .scrollView).minY
        } action: { onHeaderTop($0) }
    }

    private func row(_ port: PortSnapshot) -> some View {
        let presentation = PortRowPresentation(snapshot: port)
        return PortRow(
            presentation: presentation,
            showsTechnicalNames: showsTechnicalNames,
            density: density,
            badge: aboutToChange.contains(port.id)
                ? "About to change"
                : presentation.compactBadge,
            isThunderbolt: port.port.isThunderbolt,
            isSelected: stage.selectedID == port.id,
            isHovered: stage.hoveredID == port.id,
            // §4.5: a USB-only row is not selectable, and the click is not
            // swallowed either — it produces the same R3 copy the stage's
            // own click does.
            select: {
                guard port.port.isThunderbolt else { return onUSBClick(port.id) }
                // §S4's multi-select: ⌘-click and ⇧-click add to the
                // selection rather than replacing it, on the screen that has
                // one to add to.
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

extension PortGroupSection {
    /// Whether the click that is being handled carried ⌘ or ⇧. SwiftUI's
    /// button action does not describe the click, so the modifiers are read
    /// from the event that is still current while it runs.
    static func isExtendingClick() -> Bool {
        let flags = NSEvent.modifierFlags
        return flags.contains(.command) || flags.contains(.shift)
    }
}

/// Whether a scroll view has content past its top or bottom edge, and how
/// tall the part it shows is. Shared by the port list and the assistant's
/// working area (§2.3 bands 2 and 3), so the two scrolling regions fold the
/// same way.
struct ScrollFold: Equatable {
    var above = false
    var below = false
    /// The height of the visible part, in the scroll view's own frame.
    var containerHeight: CGFloat = 0

    init() {}

    init(_ geometry: ScrollGeometry) {
        let top = geometry.contentOffset.y + geometry.contentInsets.top
        let bottom = top + geometry.containerSize.height
        above = top > 1
        below = bottom < geometry.contentSize.height - 1
        containerHeight = geometry.containerSize.height
    }
}

/// Opaque over the content, fading to nothing over the last points before an
/// edge that has more past it. Applied as a mask, so a group's own background
/// fades with its rows and nothing is drawn over them. An edge with nothing
/// past it is left alone, so content that fits is untouched.
struct ScrollFoldMask: View {
    let fold: ScrollFold
    /// How much of the bottom edge is hidden outright, with the fade ending
    /// above it. Nothing unless the list has a header to cover, and never
    /// more than `depth`.
    var hiddenBelow: CGFloat = 0

    static let depth: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: fold.above ? Self.depth : 0)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: fold.below ? Self.depth : 0)
            Color.clear
                .frame(height: fold.below ? hiddenBelow : 0)
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
