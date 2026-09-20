//
//  RootView.swift
//
//  The one window: unified toolbar, stage on the left, assistant column on
//  the right (UX_SPEC §2.1–§2.3), reflowing to a single column below 900 pt
//  of width (§8.5).
//

import SwiftUI
import RDMALinkCore

struct RootView: View {
    @Bindable var router: HubRouter
    @Environment(\.openSettings) private var openSettings
    @State private var model = InventoryModel()
    /// §2.4: the stage and the port list read and write the same selection, so
    /// there is one of these and the window owns it.
    @State private var stage = StageModel()
    /// §4.5: clicking a USB-only receptacle produces R3 inline in the working
    /// area. It is a tip, not a refusal, and nothing in the window is blocked
    /// while it is up.
    @State private var usbTip: USBTip?
    /// §9.2: the waking-ports beat runs once per launch and is never repeated.
    @State private var hasWoken = false
    @AppStorage(AppSettings.showTechnicalNames) private var showsTechnicalNames = false

    /// §2.3's split, and §8.5's reflow.
    private static let stageMinimumWidth: CGFloat = 460
    private static let columnMinimumWidth: CGFloat = 380
    private static let singleColumnThreshold: CGFloat = 900
    private static let stageStripHeight: CGFloat = 180

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width < Self.singleColumnThreshold {
                singleColumn
            } else {
                splitColumns(availableWidth: proxy.size.width)
            }
        }
        .frame(minWidth: 840, minHeight: 560)
        .navigationTitle("RDMALink")
        .navigationSubtitle(model.windowSubtitle)
        // §2.7: the View menu drives the stage, and the menu bar is outside
        // this view tree.
        .focusedSceneValue(\.stageModel, stage)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ThisMacBadge()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Check Again", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Re-runs the full probe.")
                Button("Help", systemImage: "questionmark.circle") {
                    router.sheet = .whatThisAllMeans
                }
            }
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .whatThisAllMeans:
                WhatThisAllMeansSheet()
            case .otherMac:
                // §S8 step 4 names *this Mac's* address on the link, which is
                // an address RDMALink put there. A port somebody else set up
                // is not RDMALink's to hand out (§7.3), and `ready` now agrees.
                OtherMacSheet(address: model.ports.ready.compactMap(\.linkLocalAddress).first)
            }
        }
        .task { await model.start() }
        // §2.4: the inventory is mirrored onto the stage every time it changes,
        // and nothing else writes the stage's port list.
        .onChange(
            of: StageInput(hardware: model.hardware, ports: model.ports), initial: true
        ) { previous, input in
            stage.apply(input)
            updateUSBTip(previous: previous.ports, current: input.ports)
        }
        .onChange(of: model.phase, initial: true) { _, phase in
            guard !hasWoken, phase != .probing else { return }
            hasWoken = true
            stage.wake()
        }
        .task {
            // Review hook only; see App/SnapshotHook.swift. Nothing runs unless
            // RDMALINK_SNAPSHOT is set in the environment.
            await SnapshotHook.run {
                model.phase != .probing
            } turnTo: { face in
                stage.turnTo(face)
            } present: { surface in
                switch surface {
                case .whatThisAllMeans: router.sheet = .whatThisAllMeans
                case .otherMac: router.sheet = .otherMac
                case .settings: openSettings()
                }
            }
        }
    }

    private func splitColumns(availableWidth: CGFloat) -> some View {
        HubSplit(
            availableWidth: availableWidth,
            stageMinimum: Self.stageMinimumWidth,
            columnMinimum: Self.columnMinimumWidth
        ) {
            stageView
        } column: {
            column
        }
    }

    /// §8.5: the same content, the same copy, the same order — the stage
    /// collapses to a strip and the column takes the rest.
    private var singleColumn: some View {
        VStack(spacing: 0) {
            stageView.frame(height: Self.stageStripHeight)
            Divider()
            column.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The one call site for the stage.
    private var stageView: some View {
        StageView(model: stage) { port in
            // §4.5: clicking a USB-only receptacle produces the USB copy
            // inline, never a disabled-button dead end.
            raiseUSBTip(port.id)
        }
    }

    private var column: some View {
        AssistantColumn(
            model: model,
            stage: stage,
            router: router,
            showsTechnicalNames: showsTechnicalNames,
            usbTip: usbTip,
            onUSBClick: raiseUSBTip,
            dismissUSBTip: { usbTip = nil },
            turnAndBreathe: turnToTheThunderboltPorts
        )
    }

    // MARK: - R3, and the recovery §6.2 gives it

    /// §4.5: "Clicking one produces the USB copy inline (R3), never a
    /// disabled-button dead end." Where this Mac's shape has no body in §6.2 —
    /// neither a four-port back nor a Mac mini — there is no copy to produce,
    /// so the click is refused at source and the `.operationNotAllowed` cursor
    /// is the whole answer, rather than setting a flag that draws nothing.
    private func raiseUSBTip(_ id: String) {
        guard USBPortTip.body(hardware: model.hardware, ports: model.ports) != nil else {
            return
        }
        usbTip = USBTip(portID: id)
    }

    /// §6.2 R3's recovery: "the camera arcs to the back face and breathes the
    /// eligible receptacles once".
    private func turnToTheThunderboltPorts() {
        stage.turnTo(.back)
        let eligible = model.ports.filter { $0.port.isThunderbolt && $0.port.face == .back }
        stage.setAttention(Set(eligible.map(\.id)))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            stage.setAttention([])
        }
    }

    /// The other half of R3's recovery: "when the cable reappears in a
    /// Thunderbolt port the tip dismisses itself".
    private func updateUSBTip(previous: [PortSnapshot], current: [PortSnapshot]) {
        guard let tip = usbTip else { return }
        // The receptacle the tip is about stopped being reported at all.
        guard current.contains(where: { $0.id == tip.portID }) else {
            usbTip = nil
            return
        }
        guard !tip.isResolved else { return }
        let before = Dictionary(
            previous.map { ($0.id, $0.port.link) }, uniquingKeysWith: { first, _ in first }
        )
        let arrived = current.contains { snapshot in
            snapshot.port.isThunderbolt && snapshot.port.link != .empty
                && (before[snapshot.id] ?? .empty) == .empty
        }
        guard arrived else { return }
        usbTip?.isResolved = true
        stage.setAttention([])
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1800))
            if usbTip?.isResolved == true { usbTip = nil }
        }
    }
}

/// §4.5 → §6.2 R3. `isResolved` is the beat between the cable landing in a
/// Thunderbolt port and the tip taking itself away, which §6.1 rule 9 makes a
/// cross-fade to one line rather than a card that simply vanishes.
struct USBTip: Equatable {
    var portID: String
    var isResolved = false
}
