//
//  WizardWorkingArea.swift
//
//  Band 2 while the set-up assistant is up (UX_SPEC §2.3, §2.5). It replaces
//  **only** the working area: the stage stays put and re-poses, the port list
//  stays put and re-densifies, and the footer stays put and re-labels, which
//  is what makes eight screens feel like one place.
//
//  Drop it in beside the hub's `WorkingArea` and put `WizardFooter` in band 4.
//

import SwiftUI
import RDMALinkCore

struct WizardWorkingArea: View {
    let flow: SetUpFlow
    let model: InventoryModel
    /// §2.4: the stage and the list are one selection, so the assistant writes
    /// the same model the port list does.
    let stage: StageModel
    /// §S5's hover-to-preview. `StageModel` has no preview channel yet, so the
    /// window supplies one and this view calls it with the hovered change and
    /// the port it is about. **Owed from the stage owner:** the four previews.
    var preview: (ReviewPreview?, String) -> Void = { _, _ in }
    /// §6.2 R3's recovery, which only the window can run: it owns the port
    /// list the eligible receptacles come from.
    var turnAndBreathe: () -> Void = {}
    /// `Check Again` and ⌘R: re-run the full probe **and** the checks' own
    /// reads, so a check that is not about a cable can clear (§S3, §6.2 R4,
    /// R5, R14).
    var recheck: () -> Void = {}
    /// S7's `What to Do on the Other Mac`, which closes the assistant and
    /// opens §S8's screen in its place — the window's to do, since it owns
    /// both. Absent by default rather than present and inert.
    var showOtherMac: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // §2.3 band 1: a label, never a progress bar. The step's own
            // headline lives in the screen below it, so nothing is said twice.
            Text(flow.stepCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            screen
                .id(flow.step)
                .transition(push)
                // §S5: "OS password dialog up (the working area dims 20 % and
                // says nothing over it)".
                .opacity(flow.isAuthorizing ? 0.8 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.25), value: flow.step)
        .animation(.smooth(duration: 0.2), value: flow.identify == nil)
        .animation(.smooth(duration: 0.18), value: flow.isAuthorizing)
        .onChange(of: flow.attentionPortIDs, initial: true) { _, ids in
            stage.attention(ids: ids)
            // §S3: "the camera turns to the face it is on if it isn't already
            // visible". `turnTo` is silent when the face is already in front.
            if let face = model.ports.first(where: { ids.contains($0.id) })?.port.face {
                stage.turnTo(face)
            }
        }
        .onChange(of: flow.loopedPortIDs, initial: true) { _, ids in
            // §6.2 R2: "a single light thread is drawn between them" — the
            // one time a thread connects two ports of the same machine.
            stage.loopedBack(ids)
        }
        // §S4 "After this screen the choice is frozen": from S5 on, the stage
        // holds the chosen receptacles and takes no click, on the model or in
        // the list, until the user is choosing again. The whole selection
        // goes across: the list dims by it, and the stage lights the first.
        .onChange(of: flow.frozenSelection, initial: true) { _, frozen in
            if let frozen {
                stage.freezeSelection(on: frozen)
            } else {
                stage.thawSelection()
            }
        }
        .onChange(of: flow.selection) { _, selection in
            guard !flow.isSelectionFrozen else { return }
            stage.select(orderedFirst(of: selection))
        }
        .onChange(of: stage.selectedID) { _, id in
            guard flow.step == .choose, flow.identify == nil, let id else { return }
            // §S4's multi-select: the stage lights one receptacle at a time, so
            // mirroring a multi-selection back into the flow would evict every
            // port but the first. A receptacle the flow already holds is the
            // stage catching up, not a new click.
            guard !flow.selection.contains(id) else { return }
            flow.select(id)
            // §2.4: the stage and the list are one selection. A click the flow
            // declined — a USB-only receptacle, a port that routes to Adopt —
            // must not leave a ring on the model that the list does not show.
            if flow.route(for: id) != nil {
                stage.select(orderedFirst(of: flow.selection))
            }
        }
        // §4.4: the ribbon stays up for the whole of the review and the apply,
        // so what "leave the Thunderbolt Bridge" means is on screen while it
        // is being described and while it happens.
        .onChange(of: flow.step, initial: true) { _, step in
            stage.ribbons = step == .review || step == .apply ? .all : .automatic
            if step < .apply { stage.clearAllProgress() }
        }
        // §S4b: the stage's whole part in Identify — every eligible receptacle
        // shimmers, the one that moved takes a steady ring, and the cable
        // going back in blooms it.
        .onChange(of: flow.identify == nil) { _, isOff in
            if isOff { stage.stopIdentify() } else { stage.startIdentify() }
        }
        .onChange(of: flow.identify?.outcome) { _, outcome in
            switch outcome {
            case .watching?: stage.startIdentify()
            case .unplugged(let port)?, .usbOnly(let port)?: stage.identify(answer: port.id)
            case .replugged(let port)?: stage.identify(replug: port.id)
            case .ambiguous?, .timedOut?, nil: break
            }
        }
        // §S6: "the selected receptacle's segmented ring closes its gaps one
        // by one as each real step completes". One call per row that has
        // landed — never a timer, so a stall looks like a stall (§3.5).
        .onChange(of: flow.apply?.rows.map(\.state)) { _, _ in
            guard let apply = flow.apply else { return }
            for entry in apply.ringProgress {
                guard let id = portID(bsdName: entry.bsdName) else { continue }
                stage.progress(step: entry.step, of: entry.total, for: id)
            }
        }
        // §S4b: the one timer the spec allows has to be able to expire. The
        // observations arrive only when a cable moves, so on a Mac where
        // nothing moves nothing would ever advance the clock.
        .task(id: flow.identify == nil) {
            guard flow.identify != nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                flow.identify?.tick()
            }
        }
        .onDisappear {
            stage.attention(ids: [])
            stage.loopedBack([])
            stage.stopIdentify()
            stage.clearAllProgress()
            stage.clearPreview()
            stage.thawSelection()
            stage.ribbons = .automatic
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch flow.step {
        case .choose:
            WizardChoosePort(flow: flow, model: model, perform: perform)
        case .review:
            WizardReview(flow: flow, model: model, preview: preview,
                         clearPreview: stage.clearPreview, perform: perform)
        case .apply:
            WizardApply(flow: flow, model: model, perform: perform)
        case .ready:
            WizardReady(
                flow: flow, model: model, perform: perform, showOtherMac: showOtherMac)
        }
    }

    /// §2.5's push: a leading-edge slide, 0.25 s, `.smooth`. Under Reduce
    /// Motion it is a cross-fade, and nothing that carries meaning is lost —
    /// every screen says in words what it would otherwise have shown by moving.
    private var push: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let entering: Edge = flow.isMovingForward ? .trailing : .leading
        let leaving: Edge = flow.isMovingForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: entering).combined(with: .opacity),
            removal: .move(edge: leaving).combined(with: .opacity))
    }

    private func orderedFirst(of selection: Set<String>) -> String? {
        model.ports.first { selection.contains($0.id) }?.id
    }

    /// The operations speak in interface names; the stage and the list speak
    /// in receptacle ids. This is the one place the two are matched up.
    private func portID(bsdName: String) -> String? {
        model.ports.first { $0.port.bsdName == bsdName }?.id
    }

    /// The one place a wizard button turns into something happening.
    private func perform(_ action: WizardAction) {
        switch action {
        case .continue: flow.goForward()
        case .back, .cancel: flow.goBack()
        case .done: flow.goBack()
        case .checkAgain: recheck()
        case .turnTheMacAround: turnAndBreathe()
        case .openNetworkSettings: WizardSettingsPane.open(WizardSettingsPane.network)
        case .openUsersAndGroups: WizardSettingsPane.open(WizardSettingsPane.usersAndGroups)
        case .showMeTheProfile: WizardSettingsPane.open(WizardSettingsPane.profiles)
        case .quitSystemSettings: WizardSystemSettingsApp.quit()
        case .showTheNotesFolder: WizardFinder.showNotesFolder()
        case .showInFinder:
            guard let volume = flow.findings.mountedThunderboltVolumes?.first else { return }
            WizardFinder.showVolume(named: volume)
        case .tryAgain: flow.tryAgain()
        case .takeAnotherLook, .pickADifferentPort: flow.goBack()
        case .identifyAPort: flow.beginIdentify()
        case .identifyAgain: flow.identify?.restart()
        case .useThisPort: flow.useIdentifiedPort()
        case .pickFromTheList: flow.dismissIdentify()
        // Handled by `CopyDetailsButton`, which needs the payload and not an
        // intent (§6.1 rule 8).
        case .copyDetails, .copyDetailsForIT: break
        }
    }
}

/// The headline-and-body pair every wizard screen opens with (§2.3 band 2):
/// `.title2` semibold over `.body` secondary.
struct WizardHeadline: View {
    let headline: LocalizedStringResource
    var message: LocalizedStringResource?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline)
                .font(.title2.weight(.semibold))
            if let message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
