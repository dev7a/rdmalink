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
    /// §S1's rows, footer and Port menu all raise their actions through this
    /// one object, and §S9–§S11's surfaces are what it opens.
    @State private var actions = HubActionsModel()
    /// S4–S7, while the set-up assistant is up. `nil` is the hub.
    @State private var flow: SetUpFlow?
    /// §S3's checks re-evaluate live, so their read runs again whenever this
    /// Mac changes while the assistant is up. It is a read and nothing else.
    @State private var findings = PreflightFindings()
    /// §4.5: clicking a USB-only receptacle produces R3 inline in the working
    /// area. It is a tip, not a refusal, and nothing in the window is blocked
    /// while it is up.
    @State private var usbTip: USBTip?
    /// §9.2: the waking-ports beat runs once per launch and is never repeated.
    @State private var hasWoken = false
    /// Bumped whenever the checks have to look again. §S3's rows 2, 3 and 4
    /// are not about cables at all — a volume ejected in Finder, Wi-Fi coming
    /// up, room freed on the disk — so a read keyed on link state alone can
    /// never clear them, and S5's button would stay greyed for ever.
    @State private var preflightToken = 0
    /// True between `Check Again` and the read it asked for landing, which is
    /// what greys S5's default button for the duration (§S3's re-checking
    /// state). The quiet one-second read underneath (§7.4) never sets it: a
    /// button that flickers once a second is worse than no state at all.
    @State private var isRechecking = false
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
        .frame(minWidth: 840, minHeight: 600)
        // §S6, §S10: a write is never cut off. From the password dialog to
        // the last step, the window's dismiss functionality — its close
        // button and File › Close ⌘W — is turned off, rather than left
        // looking live and doing nothing (a `windowShouldClose` that says
        // no), and once writing starts quitting waits in `BurstGate`.
        // Checked against SwiftUI's documented contract, never by running a
        // write.
        .windowDismissBehavior(holdsTheWindow ? .disabled : .automatic)
        .navigationTitle("RDMALink")
        .navigationSubtitle(model.windowSubtitle)
        // §2.7: the View menu drives the stage and the Port menu drives the
        // hub's actions, and the menu bar is outside this view tree.
        .focusedSceneValue(\.stageModel, stage)
        .focusedSceneValue(\.hubActions, actions)
        // §2.7: ⌘R is the View menu's `Check Again`, and it re-checks exactly
        // as the toolbar button does.
        .focusedSceneValue(\.recheck, recheck)
        // §S12: the Help menu's save waits while one of this window's sheets
        // is up.
        .focusedSceneValue(\.presentsSheet, router.sheet != nil || actions.sheet != nil)
        .toolbar {
            // §2.2: two items, each with a verb-first tooltip. `Help` takes
            // the plain `questionmark` — the toolbar group already draws the
            // container the circled symbol would draw a second time.
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Check Again", systemImage: "arrow.clockwise") { recheck() }
                    .help("Check this Mac's ports and settings again")
                Button("Help", systemImage: "questionmark") {
                    router.sheet = .whatThisAllMeans
                }
                .help("Learn what RDMALink changes and why")
            }
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .whatThisAllMeans:
                WhatThisAllMeansSheet()
            }
        }
        // §S8 and §S11 both take the working area, and the one asked for last
        // is the one shown; the other is put away rather than left waiting
        // underneath to reappear on `Done`.
        .onChange(of: router.showsOtherMac) { _, shows in
            if shows { actions.closeChangeLog() }
        }
        .onChange(of: actions.showsChangeLog) { _, shows in
            if shows { router.showsOtherMac = false }
        }
        .task { await model.start() }
        // §2.8: `Restore…` is offered whenever a note exists, including a note
        // for a port that is not on this Mac any more, so the notes folder is
        // read once rather than inferred from the ports.
        .task {
            actions.attach(stage: stage)
            await actions.refreshNotes()
        }
        // §2.4: the inventory is mirrored onto the stage every time it changes,
        // and nothing else writes the stage's port list.
        .onChange(
            of: StageInput(
                hardware: model.hardware, ports: model.ports,
                mode: PortRowMode(step: flow?.step)),
            initial: true
        ) { previous, input in
            stage.apply(input)
            actions.ports = input.ports
            actions.hardware = input.hardware
            actions.footer = HubPresentation.footer(
                hardware: input.hardware, ports: input.ports)
            updateUSBTip(previous: previous.ports, current: input.ports)
        }
        // §S1's footer, the Port menu's ⌘N, a row's `Set Up…` and `Set It Up
        // Again` all write the same request; this is where it becomes the
        // assistant.
        .onChange(of: actions.pendingSetUp) { _, request in
            guard let request else { return }
            actions.pendingSetUp = nil
            startSetUp(request)
        }
        // §2.6, §2.7: the hub's actions and the menus leave the run alone
        // while it is up, so they are told how far it has got.
        .onChange(of: flow?.presence, initial: true) { _, presence in
            actions.assistant = presence
            router.isAssistantUp = presence != nil
        }
        // The router outlives the window; a window that goes takes its
        // assistant with it.
        .onDisappear { router.isAssistantUp = false }
        // §S4b: the Port menu's ⌘I on the picker is the picker's Identify.
        .onChange(of: actions.pendingIdentify) { _, requested in
            guard requested else { return }
            actions.pendingIdentify = false
            flow?.beginIdentify()
        }
        // Every live read reaches the assistant, which re-derives every
        // screen from it — that is what makes a check flip in the same beat
        // as the cable (§S3, §S4).
        .onChange(of: StageInput(hardware: model.hardware, ports: model.ports)) { _, _ in
            updateFlow()
        }
        .onChange(of: findings) { _, _ in updateFlow() }
        .task(id: preflightReadKey) { await readPreflight() }
        // §7.4's "quiet one-second state diff", pointed at the checks: the
        // ones that are not about cables have nothing else that could ever
        // re-run them.
        .task(id: flow != nil) {
            guard flow != nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                preflightToken += 1
            }
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
                case .settings: openSettings()
                }
            } open: { route in
                openForReview(route)
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
        StageView(
            model: stage,
            onUSBOnlyClick: { port in
                // §4.5: clicking a USB-only receptacle produces the USB copy
                // inline, never a disabled-button dead end.
                raiseUSBTip(port.id)
            },
            onExtendClick: extendSelection,
            onDoubleClick: doubleClickSetUp
        )
    }

    /// §S1: "double-clicking a configurable one opens Review for it". Only
    /// on the hub — inside a run the choice is the picker's — and only for a
    /// port set-up can take, the same question the row's `Set Up…` asks
    /// (`PortRowPresentation.offersSetUp`), so a ready, hand-configured or
    /// near-match port is not sent to a review that would refuse it or have
    /// nothing to press. The double-click names its port, so the run opens
    /// on Review, step 1 of 2, with no picker in it (§S4).
    private var doubleClickSetUp: ((StagePort) -> Void)? {
        guard flow == nil else { return nil }
        return { port in
            guard port.isThunderbolt,
                  actions.canPerform(.setUpPort(portID: port.id)),
                  let snapshot = actions.snapshot(id: port.id),
                  PortRowPresentation.offersSetUp(snapshot)
            else { return }
            actions.perform(.setUpPort(portID: port.id))
        }
    }

    /// §S4's ⌘/⇧-click on the model, which only means anything on Choose a
    /// port. `nil` everywhere else, so the stage takes the ordinary path.
    private var extendSelection: ((StagePort) -> Void)? {
        guard let flow, flow.step == .choose, flow.identify == nil else { return nil }
        return { flow.extendSelection($0.id) }
    }

    private var column: some View {
        AssistantColumn(
            model: model,
            stage: stage,
            router: router,
            actions: actions,
            flow: flow,
            showsTechnicalNames: showsTechnicalNames,
            usbTip: usbTip,
            onUSBClick: raiseUSBTip,
            dismissUSBTip: { usbTip = nil },
            turnAndBreathe: turnToTheThunderboltPorts,
            recheck: recheck,
            preview: { preview, portID in
                stage.preview(preview.map(StagePreview.init), for: portID)
            },
            showOtherMac: showOtherMac
        )
        // §S1's rows and situation rows raise their own actions, wherever the
        // list is drawn.
        .environment(actions)
        // §2.6: Adopt, Restore and Restore All Ports are three of the four
        // sheets the app draws; S13 is the fourth. The system draws the rest:
        // the authorization dialog, and the diagnostics save panel and alert.
        .sheet(item: $actions.sheet) { sheet in
            switch sheet {
            case .adopt(let portID):
                AdoptSheet(portID: portID, hub: actions, model: model)
            case .restore(let subject):
                RestoreSheet(subject: subject, hub: actions, model: model)
            }
        }
    }

    // MARK: - The review hook's routes

    /// Opens one of the app's own routes on the live inventory, for
    /// App/SnapshotHook.swift. Every branch is a read: the assistant routes
    /// stop at the screen they name, and the two sheets read this Mac exactly
    /// as they do when a person opens them.
    private func openForReview(_ route: SnapshotHook.Route) {
        let thunderbolt = model.ports.first { $0.port.isThunderbolt }
        switch route {
        case .hub:
            break
        case .choose, .review, .reviewFromPicker, .ready:
            // §S4: "An unrecognized Mac never reaches this screen: R31 offers
            // no set-up." The hook stops at the hub, as a person would.
            guard !actions.isUnrecognized else { return }
            switch route {
            case .choose:
                // The picker as the footer opens it, pre-selection and all.
                startSetUp(.choose(suggested: nil))
            case .review:
                // As a control that names its port opens it: two steps, and
                // `Cancel` leading. The first port set-up can take, so the
                // picture is of a plan rather than of R27's card.
                let port = model.ports.first(where: PortRowPresentation.offersSetUp) ?? thunderbolt
                guard let port else { return }
                startSetUp(.port(port.id))
            case .reviewFromPicker:
                // As it opens from the picker's `Continue`: three steps, and
                // `Back` leading.
                startSetUp(.choose(suggested: nil))
                flow?.route(to: .review, openedOn: .choose)
            case .ready:
                // S7 for the port `review` names, in the run it opened —
                // drawn from that port as it is, with nothing written.
                let port = model.ports.first(where: PortRowPresentation.offersSetUp) ?? thunderbolt
                guard let port else { return }
                startSetUp(.port(port.id))
                flow?.route(to: .ready, openedOn: .review)
            default:
                break
            }
        case .restoreSheet:
            // A note if there is one; otherwise §7.5's form, which is the one
            // a Mac with no notes can actually show.
            if actions.hasRestorableNote {
                actions.perform(actions.restoreAction)
            } else if let standalone = model.ports.first(where: \.isOutOfEveryBridge) {
                actions.perform(.returnToBridge(portID: standalone.id))
            } else {
                actions.perform(.restoreAll)
            }
        case .adoptSheet:
            guard let port = model.ports.first(where: {
                actions.canPerform(.adopt(portID: $0.id))
            }) else { return }
            actions.perform(.adopt(portID: port.id))
        case .changelog:
            actions.perform(.changeLog)
        case .otherMac:
            router.showsOtherMac = true
        }
    }

    /// S7's `What to Do on the Other Mac`. §S8 is reached from S7, whose work
    /// is finished, so the assistant closes exactly as `Done` closes it and
    /// the screen takes the working area it leaves. The Help menu reaches the
    /// same screen without an assistant to close.
    private func showOtherMac() {
        if let flow, flow.step == .ready { flow.goForward() }
        router.showsOtherMac = true
    }

    // MARK: - The set-up assistant (S4–S7)

    /// Builds the flow, hands it the reading it already has, and opens it on
    /// the screen the request calls for (§S4 "When this screen appears").
    private func startSetUp(_ request: SetUpRequest) {
        // Nothing re-enters a run (§2.7): a second request while one is up
        // would drop the first — mid-burst, its answer unseen. The menus and
        // the hub's door already refuse it; this is the last guard.
        guard flow == nil else { return }
        // Reached from the hub alone, where this Mac is known and — on an
        // unrecognized one — every way in is absent (§S4, R31).
        guard let hardware = model.hardware, hardware.isRecognized else { return }
        let flow = SetUpFlow(
            planner: Self.planner(hardware: hardware),
            runner: Self.runner(hardware: hardware),
            finish: {
                self.flow = nil
                self.stage.clearAllProgress()
                Task { await actions.refreshNotes() }
                Task { await model.refresh() }
            })
        self.flow = flow
        updateFlow()
        flow.open(request)
    }

    /// §S6, §S10: from the moment macOS's password dialog is asked for until
    /// the last step lands — S6's run, or a Restore sheet's checklist. Not
    /// from the first reported step: the burst writes the instant the
    /// password is accepted, before any report reaches the main actor.
    /// Quitting asks `BurstGate`, which opens with the credential.
    private var holdsTheWindow: Bool {
        let phase = flow?.apply?.phase
        return phase == .authorizing || phase == .running
            || actions.run?.holdsTheWindow == true
    }

    /// The whole assistant re-derives itself from this.
    private func updateFlow() {
        flow?.update(
            ports: model.ports,
            hardware: model.hardware,
            switchState: model.switchState,
            findings: findings)
    }

    /// What the checks have to look at, and what has to be looked at again
    /// when it changes. The read is skipped entirely while the assistant is
    /// down.
    private var preflightReadKey: PreflightReadKey {
        PreflightReadKey(
            isAssistantUp: flow != nil,
            ports: model.ports.map { "\($0.port.bsdName):\($0.port.link)" },
            token: preflightToken)
    }

    /// `Check Again` in the toolbar and the View menu (⌘R), and the Checked
    /// group's own button: re-run the full probe **and** the checks' reads,
    /// and say so on screen while it happens.
    private func recheck() {
        if flow != nil {
            isRechecking = true
            findings.isRechecking = true
        }
        preflightToken += 1
        Task { await model.refresh() }
    }

    /// `ObservedWorld.read` off the main actor: IOKit, `ifconfig`, `/sbin/mount`
    /// and an unauthorized `SCPreferences`. It takes no credential and writes
    /// nothing, which is why the checks can run it on every change.
    private func readPreflight() async {
        guard flow != nil else {
            isRechecking = false
            return
        }
        let snapshots = model.ports
        let ports = snapshots.map { OperationPort($0.port) }
        guard !ports.isEmpty, let hardware = model.hardware else { return }
        // R14 is measured against the folder the notes really go to.
        let notesDirectory = NotesLocation.store.directory
        let read = await Task.detached(priority: .userInitiated) { () -> PreflightFindings? in
            guard let world = try? ObservedWorld.read(
                ports: ports, hardware: hardware, notesDirectory: notesDirectory)
            else {
                return nil
            }
            var findings = PreflightFindings(world: world)
            // Review hook only; see App/SnapshotHook.swift. A fixture stands
            // in for this Mac's ports, and the world just read is this Mac's,
            // so the half of the checks that is about the receptacles — row 1,
            // R1 and R2 — is taken from the fixture's ports instead.
            if SnapshotHook.fixture != nil {
                let staged = PreflightFindings(ports: snapshots)
                findings.portsWithAMac = staged.portsWithAMac
                findings.portsInALoop = staged.portsInALoop
                findings.portsLoopedBack = staged.portsLoopedBack
            }
            return findings
        }.value
        guard !Task.isCancelled else { return }
        isRechecking = false
        guard let read else {
            findings.isRechecking = false
            return
        }
        findings = read
    }

    /// S5's plan. `SetUpPorts.preview` writes nothing and takes no credential.
    private static func planner(hardware: HardwareModel) -> SetUpFlow.Planner {
        let notesDirectory = NotesLocation.store.directory
        return { ports in
            // Off the main actor, because the read spawns `ifconfig` and
            // `/sbin/mount` — but wired to the calling task's cancellation, so
            // a `Back` pressed mid-read is not answered afterwards by a
            // refusal about a screen nobody is on any more.
            let task = Task.detached(priority: .userInitiated) {
                let world = try ObservedWorld.read(
                    ports: ports, hardware: hardware, notesDirectory: notesDirectory)
                return SetUpPorts(ports: ports).preview(world: world)
            }
            let plan = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            return plan
        }
    }

    /// S6's burst — **the app's one write path**. The credential is taken here
    /// and nowhere else in the set-up flow, and every write follows it without
    /// pausing, because it lasts about thirty seconds.
    private static func runner(hardware: HardwareModel) -> ApplyRun.Runner {
        { plan in
            AsyncThrowingStream { continuation in
                let task = Task.detached(priority: .userInitiated) {
                    do {
                        let result = try OperationHost.burstSynchronously { session in
                            try SetUpPorts(ports: plan.ports.map(\.port), reviewed: plan)
                                .perform(
                                    session: session,
                                    environment: NotesLocation.environment(hardware: hardware),
                                    progress: { step, state in
                                        continuation.yield(.step(step, state))
                                    })
                        }
                        continuation.yield(.finished(result))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
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
        stage.attention(ids: Set(eligible.map(\.id)))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            stage.attention(ids: [])
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
        stage.attention(ids: [])
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

/// What the checks' read depends on. While the assistant is down nothing is
/// read at all.
struct PreflightReadKey: Equatable {
    var isAssistantUp: Bool
    var ports: [String]
    /// Everything that is not a cable moving: `Check Again`, and the quiet
    /// one-second tick underneath.
    var token: Int
}
