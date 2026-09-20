//
//  WorkingArea.swift
//
//  Band 2 of the assistant column: the only band that changes between steps
//  (UX_SPEC §2.3). In ML1 it carries S0 while the probe runs, the hub once it
//  lands, and the two refusals that block the app at launch — R24 and R25.
//

import SwiftUI
import RDMALinkCore

struct WorkingArea: View {
    let model: InventoryModel
    let stage: StageModel
    /// The USB-only receptacle that was last clicked, when one was (§4.5 →
    /// R3). Nothing else in the window changes while it is set.
    var usbTip: USBTip?
    var dismissUSBTip: () -> Void = {}
    /// R3's recovery, which is the window's to run: it owns the port list the
    /// eligible receptacles come from.
    var turnAndBreathe: () -> Void = {}

    var body: some View {
        switch model.phase {
        case .probing:
            ProbingWorkingArea(isSlow: model.isSlowProbe)
        case .ready:
            HubWorkingArea(
                model: model, stage: stage, usbTip: usbTip,
                dismissUSBTip: dismissUSBTip, turnAndBreathe: turnAndBreathe
            )
        case .noThunderboltHardware:
            NoHardwareWorkingArea(model: model)
        case .unsupportedSystem:
            UnsupportedSystemWorkingArea()
        }
    }
}

/// S0 — Getting to know this Mac.
struct ProbingWorkingArea: View {
    let isSlow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Getting to know this Mac")
                    .font(.title2.weight(.semibold))
            }
            Text(
                isSlow
                    ? "Still looking. Some Thunderbolt information takes a few seconds to arrive."
                    : "Checking the Thunderbolt ports, the network, and whether RDMA is turned on."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// S1 — Overview. Also R23's read-only mode, which changes the headline and
/// the body and nothing else: the model, the port list and the change log all
/// still work, so the app stays a useful map.
struct HubWorkingArea: View {
    let model: InventoryModel
    let stage: StageModel
    var usbTip: USBTip?
    var dismissUSBTip: () -> Void = {}
    var turnAndBreathe: () -> Void = {}
    /// R22, revealed by the RDMA row's `Tell Me More`.
    @State private var showsNoDevicesDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let copy = model.hubCopy
            VStack(alignment: .leading, spacing: 8) {
                Text(copy.headline)
                    .font(.title2.weight(.semibold))
                Text(copy.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ThisMacSection(rows: model.thisMacRows) { action in
                switch action {
                case .turnItOn:
                    NSWorkspace.shared.open(RDMAStatus.developerToolsSettingsURL)
                case .tellMeMore:
                    showsNoDevicesDetail = true
                }
            }
            if showsNoDevicesDetail, model.switchState == .onWithoutDevices {
                NoRDMADevicesRefusal(model: model)
            }
            SituationSection(situations: model.situations)
            StageChangeNotice(face: stage.unseenChange, showMe: stage.showUnseenChange)
            if let usbTip {
                if usbTip.isResolved {
                    // §6.1 rule 9: a self-clearing refusal cross-fades to a
                    // single line and the flow carries on by itself.
                    Text("Got it — that's a Thunderbolt port. Carry on.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                } else if let message = USBPortTip.body(
                    hardware: model.hardware, ports: model.ports
                ) {
                    USBPortTipCard(
                        message: message, model: model,
                        turnAndBreathe: turnAndBreathe, dismiss: dismissUSBTip
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.18), value: showsNoDevicesDetail)
        .animation(.smooth(duration: 0.18), value: usbTip)
        .animation(.smooth(duration: 0.18), value: stage.unseenChange)
    }
}

/// §S1 and §7.4: "if a port on a face you are not looking at changes state …
/// the working area offers a single inline line — **"Something changed on the
/// back."** *[Show Me]* — which is the only camera move the app ever makes
/// unasked, and it is asked."
///
/// The spec writes the back's sentence. The other three reuse it with the face
/// words §8.2's camera announcements already use, which is the only place in
/// the app those faces are named mid-sentence.
struct StageChangeNotice: View {
    let face: PortFace?
    let showMe: () -> Void

    var body: some View {
        if let face {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Self.line(for: face))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Show Me", action: showMe)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                Spacer(minLength: 0)
            }
            .transition(.opacity)
        }
    }

    private static func line(for face: PortFace) -> LocalizedStringResource {
        switch face {
        case .back: "Something changed on the back."
        case .front: "Something changed on the front."
        case .left: "Something changed on the left side."
        case .right: "Something changed on the right side."
        }
    }
}

/// R3 — a cable is in, or the pointer went to, a USB-only port.
///
/// A tip, not a block: nothing in the window is unavailable while it is up, and
/// its default button is the recovery §6.2 names — the camera arcs to the back
/// face, which is where the Thunderbolt receptacles are.
struct USBPortTipCard: View {
    let message: LocalizedStringResource
    let model: InventoryModel
    /// §6.2 R3: "the camera arcs to the back face **and breathes the eligible
    /// receptacles once**". The card stays up afterwards — it dismisses itself
    /// when the cable lands in a Thunderbolt port, not when the camera moves.
    let turnAndBreathe: () -> Void
    let dismiss: () -> Void

    var body: some View {
        RefusalCard(
            symbol: "cable.connector.horizontal",
            tint: .secondary,
            headline: USBPortTip.headline,
            message: message
        ) {
            Button("Turn the Mac Around", action: turnAndBreathe)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            Button("Check Again") { Task { await model.refresh() } }
        }
        .padding(.top, 2)
    }
}

/// R22 — RDMA is on, but no RDMA devices appeared. Not a block.
///
/// The spec's button row is `Continue` · `Check Again` · `Copy Details`.
/// ML1 has nothing to continue *to* — there is no set-up flow yet — and a
/// `Continue` that goes nowhere would be worse than none, so the two real
/// actions are offered and `Continue` arrives with the flow in ML2.
struct NoRDMADevicesRefusal: View {
    let model: InventoryModel

    var body: some View {
        RefusalCard(
            symbol: "exclamationmark.circle",
            tint: .attention,
            headline: "RDMA is on, but no RDMA devices turned up",
            message: "That usually means this Mac, or this version of macOS, doesn't actually offer RDMA over Thunderbolt. Setting up a port is still harmless and still undoable — it just won't have anything to carry yet."
        ) {
            Button("Check Again") { Task { await model.refresh() } }
            CopyDetailsButton {
                model.diagnosticsText(failingStep: "looking for RDMA devices")
            }
        }
        .padding(.top, 2)
    }
}

/// R24 — I can't see the Thunderbolt hardware. No partial mode: without
/// hardware truth the app does nothing at all.
struct NoHardwareWorkingArea: View {
    let model: InventoryModel

    var body: some View {
        RefusalCard(
            symbol: "exclamationmark.circle",
            tint: .attention,
            headline: "I can't see this Mac's Thunderbolt hardware",
            message: "macOS isn't reporting any Thunderbolt controllers, which RDMALink needs before it will touch anything. A restart often sorts this out.",
            extraMessage: model.noHardwareAttempts >= 3
                ? "Three tries, same result. Restarting usually clears this up."
                : nil
        ) {
            Button("Check Again") { Task { await model.refresh() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            CopyDetailsButton { model.diagnosticsText() }
            QuitButton()
        }
    }
}

/// R25 — RDMALink needs a newer macOS. No recovery is offered and no read-only
/// mode either, because the detection itself isn't trustworthy on older systems.
struct UnsupportedSystemWorkingArea: View {
    var body: some View {
        RefusalCard(
            symbol: "exclamationmark.circle",
            tint: .secondary,
            headline: "RDMALink needs macOS 27",
            message: "RDMA over Thunderbolt arrived in macOS 27, and the way RDMALink edits the network is only safe there. On this version it won't make changes."
        ) {
            QuitButton()
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}
