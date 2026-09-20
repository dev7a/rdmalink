//
//  AssistantColumn.swift
//
//  The right-hand column: four fixed bands, top to bottom — header row,
//  working area, the permanent port list, footer (UX_SPEC §2.3).
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
    /// S3–S7. While it is up it owns bands 2 and 4; bands 1 and 3 do not move,
    /// which is what makes five screens feel like one place (§2.5).
    let flow: SetUpFlow?
    let showsTechnicalNames: Bool
    /// The USB-only receptacle that raised R3, from either side of the
    /// mapping (§4.5).
    var usbTip: USBTip?
    var onUSBClick: (String) -> Void
    var dismissUSBTip: () -> Void
    var turnAndBreathe: () -> Void
    /// `Check Again` and ⌘R, which re-run S3's own reads as well as the probe.
    var recheck: () -> Void = {}
    /// §S5's hover-to-preview, which only the window can wire: the stage is
    /// its own.
    var preview: (ReviewPreview?, String) -> Void = { _, _ in }
    /// S7's `What to Do on the Other Mac`.
    var showOtherMac: (() -> Void)?

    /// §2.3 band 3: **full** on the hub, Choose a port and Identify; compact
    /// on the RDMA screen, preflight, review, apply, done and the change log.
    private var density: PortListDensity {
        if actions.showsChangeLog { return .compact }
        guard let flow else { return .full }
        if flow.identify != nil { return .full }
        return flow.step == .choose ? .full : .compact
    }

    /// §S5: "Port list compact, with the target port(s) marked **About to
    /// change**."
    private var aboutToChange: Set<String> {
        guard let flow, flow.step == .review else { return [] }
        return flow.selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Absent on the hub by design (§2.3 band 1); the wizard steps in
            // ML2 pass a title and a `Step n of 5` caption.
            AssistantHeaderRow(title: nil, stepCaption: nil)
            // §S11: "The working area is replaced by a scrolling list… The
            // port list stays in place beside it."
            if let flow {
                WizardWorkingArea(
                    flow: flow, model: model, stage: stage, preview: preview,
                    turnAndBreathe: turnAndBreathe, recheck: recheck,
                    showOtherMac: showOtherMac
                )
                .padding(.bottom, 12)
            } else if actions.showsChangeLog {
                ChangeLogView(hub: actions, stage: stage, model: model)
                    .padding(.bottom, 12)
            } else {
                WorkingArea(
                    model: model, stage: stage, usbTip: usbTip,
                    dismissUSBTip: dismissUSBTip, turnAndBreathe: turnAndBreathe
                )
                .padding(.bottom, 12)
            }
            PortList(
                ports: model.ports,
                stage: stage,
                isProbing: model.phase == .probing,
                showsTechnicalNames: showsTechnicalNames,
                density: density,
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if let flow {
                WizardFooter(flow: flow)
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
}

/// Band 1. A label, never a progress bar.
struct AssistantHeaderRow: View {
    let title: LocalizedStringResource?
    let stepCaption: LocalizedStringResource?

    var body: some View {
        if let title {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 12)
                if let stepCaption {
                    Text(stepCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)
        }
    }
}
