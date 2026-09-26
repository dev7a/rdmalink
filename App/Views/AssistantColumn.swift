//
//  AssistantColumn.swift
//
//  The right-hand column, in fixed bands, top to bottom — working area, the
//  permanent port list, footer (UX_SPEC §2.3). The step label has no band of
//  its own: it rides on the first line of the screen's headline (§2.3 band 1),
//  so every headline starts at the same height, the hub's included.
//

import SwiftUI

struct AssistantColumn: View {
    let model: InventoryModel
    /// §2.4: the list is the write half of the two-way mapping, so it needs the
    /// same selection the stage draws from.
    let stage: StageModel
    let router: HubRouter
    /// §S1's footer and §S11's change log, which takes the working area's
    /// place rather than opening a sheet.
    let actions: HubActionsModel
    /// S4–S7. While it is up it owns bands 2 and 4; bands 1 and 3 do not move,
    /// which is what makes four screens feel like one place (§2.5).
    let flow: SetUpFlow?
    let showsTechnicalNames: Bool
    /// The USB-only receptacle that raised R3, from either side of the
    /// mapping (§4.5).
    var usbTip: USBTip?
    var onUSBClick: (String) -> Void
    var dismissUSBTip: () -> Void
    var turnAndBreathe: () -> Void
    /// `Check Again` and ⌘R, which re-run the checks' own reads as well as
    /// the probe.
    var recheck: () -> Void = {}
    /// §S5's hover-to-preview, which only the window can wire: the stage is
    /// its own.
    var preview: (ReviewPreview?, String) -> Void = { _, _ in }
    /// S7's `What to Do on the Other Mac`, which closes the assistant and
    /// opens §S8 in its place.
    var showOtherMac: () -> Void = {}

    /// §2.3 band 3: **full** on the hub, Choose a port and Identify; compact
    /// on the RDMA screen, review, apply, done, other Mac and the change log.
    /// Asked in the column's own order — the assistant, then §S8 and §S11,
    /// then the hub — because a run started from either screen leaves it
    /// set underneath, to come back to on `Done`, and the picker is full
    /// whatever waits under it.
    private var density: PortListDensity {
        if let flow {
            if flow.identify != nil { return .full }
            return flow.step == .choose ? .full : .compact
        }
        return actions.showsChangeLog || router.showsOtherMac ? .compact : .full
    }

    /// §2.3 band 3 and §S4: on the picker "every row is a selection target;
    /// non-selectable rows are dimmed with an explanatory subtitle". Every
    /// other screen — the hub, Identify's frozen list, the compact list
    /// beside a review — shows the row as status, with §S1's own subtitle
    /// and buttons. The stage asks ``PortRowMode/init(step:)`` the same
    /// question, because §4.8's callout quotes this row verbatim.
    private var mode: PortRowMode {
        PortRowMode(step: flow?.step)
    }

    /// §S5: "Port list compact, with the target port(s) marked **About to
    /// change**." S6 keeps the badge: the change is under way, and the row
    /// reads **Ready** once S7 has the re-read to say so.
    private var aboutToChange: Set<String> {
        guard let flow, flow.step == .review || flow.step == .apply else { return [] }
        return flow.selection
    }

    /// §2.3 band 3's floor: the list "is never truncated away". Band 2 is
    /// offered what is left above this and no more — a face header and three
    /// compact rows, enough to keep every receptacle a scroll away rather
    /// than a step away.
    ///
    /// The list yields first, and all of it: `layoutPriority(1)` below means
    /// the stack reserves this floor for the list and gives band 2 the rest.
    /// Measured on S5 at §2.1's default 1000 × 720 window, on a six-port Mac
    /// Studio: band 2 wants 801.5 pt, the list is squeezed to exactly this
    /// 120, and band 2 still gets only 453 — so S5's fourth change row and
    /// its footnote are below the fold by about 280 pt and the last two
    /// disclosures by 348.5. **There is no split that fits them at 720 pt**;
    /// the window would have to be about 1070 pt tall, and shrinking §3.2's
    /// type or §S5's spacing to close the gap is not on offer. Band 2 scrolls,
    /// which is what §2.3 band 2 is for.
    private static let portListFloor: CGFloat = 120

    /// What band 2 measures at its natural height, so the scroll view around
    /// it is exactly as tall as its content while the content fits and no
    /// taller — on the hub the column lays out as if there were no scroll
    /// view at all.
    @State private var workingAreaHeight: CGFloat?
    /// Which edges of band 2 have content past them, once it scrolls.
    @State private var workingAreaFold = ScrollFold()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // §S8 and §S11 each take the working area's place — "The port
            // list stays in place beside it." — and neither interrupts the
            // assistant: neither can be asked for while it is up (§2.7). A
            // run started from the change log returns to it when it ends.
            if flow == nil, !router.showsOtherMac, actions.showsChangeLog {
                // §S11's list scrolls on its own, under its headline and body;
                // its buttons are band 4's (`ChangeLogFooter`).
                ChangeLogView(hub: actions, stage: stage, model: model)
                    .padding(.bottom, 12)
            } else {
                // Band 2 is the one band that changes between steps, and the
                // one that can outgrow the window: §S5 lists four changes and
                // two disclosures over a six-port list. When it cannot fit
                // it scrolls — the list keeps its floor and scrolls on its
                // own (§2.3 band 3), and the footer stays put (§2.3 band 4,
                // §2.5) — so `Back` and the primary button are never below
                // the window's edge.
                ScrollView(.vertical) {
                    workingArea
                        .padding(.bottom, 12)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            workingAreaHeight = height
                        }
                }
                .scrollBounceBehavior(.basedOnSize)
                // The same fold as the port list's: the edge with more past
                // it fades over its last points instead of slicing a row
                // against the list's first header, and a working area that
                // fits is untouched. Two regions that scroll should read the
                // same way.
                .onScrollGeometryChange(for: ScrollFold.self) { geometry in
                    ScrollFold(geometry)
                } action: { _, current in
                    workingAreaFold = current
                }
                .mask { ScrollFoldMask(fold: workingAreaFold) }
                .animation(.smooth(duration: 0.18), value: workingAreaFold)
                .frame(maxHeight: workingAreaHeight ?? .infinity)
                // Laid out before the list, which is offered what is left
                // above its floor.
                .layoutPriority(1)
            }
            PortList(
                ports: model.ports,
                stage: stage,
                isProbing: model.phase == .probing,
                showsTechnicalNames: showsTechnicalNames,
                density: density,
                mode: mode,
                aboutToChange: aboutToChange,
                onUSBClick: onUSBClick,
                // §S4's multi-select belongs to Choose a port and nowhere
                // else: there is nothing to extend on a screen that is only
                // showing the list as context.
                onExtend: flow.flatMap { flow in
                    flow.step == .choose && flow.identify == nil
                        ? { flow.extendSelection($0) } : nil
                }
            )
            .frame(
                maxWidth: .infinity, minHeight: Self.portListFloor, maxHeight: .infinity,
                alignment: .top
            )
            // §2.3 band 4: every button a screen owns. §S8 and §S11 bring
            // their own, and the hub's footer and link row step aside until
            // their `Done`, so the window has one button row and one default.
            if let flow {
                WizardFooter(flow: flow, perform: performer(for: flow).callAsFunction)
                    .padding(.top, 12)
            } else if let origin = router.otherMac {
                OtherMacFooter(model: model, origin: origin) { router.otherMac = nil }
                    .padding(.top, 12)
            } else if actions.showsChangeLog {
                ChangeLogFooter(hub: actions)
                    .padding(.top, 12)
            } else if model.phase == .ready {
                HubActionsFooter(footer: actions.footer, hub: actions, router: router)
                    .padding(.top, 12)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.windowBackground)
    }

    /// Band 2, by precedence: the assistant, then §S8, then the hub.
    @ViewBuilder
    private var workingArea: some View {
        if let flow {
            WizardWorkingArea(
                flow: flow, model: model, stage: stage, preview: preview,
                perform: performer(for: flow).callAsFunction
            )
        } else if let origin = router.otherMac {
            OtherMacScreen(model: model, stage: stage, origin: origin)
        } else {
            WorkingArea(
                model: model, stage: stage, usbTip: usbTip,
                dismissUSBTip: dismissUSBTip, turnAndBreathe: turnAndBreathe
            )
        }
    }

    /// What the assistant's buttons do, one answer for band 2's cards and
    /// band 4's footer.
    private func performer(for flow: SetUpFlow) -> WizardPerformer {
        WizardPerformer(
            flow: flow, recheck: recheck, turnAndBreathe: turnAndBreathe,
            showOtherMac: showOtherMac)
    }
}
