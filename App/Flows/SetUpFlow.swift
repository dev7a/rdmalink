//
//  SetUpFlow.swift
//
//  The set-up assistant's state machine: S4 → S7, the selection, the Identify
//  modal state, the four checks, the apply run, and the footer (UX_SPEC §2.3,
//  §2.5, §S3–§S7).
//
//  It replaces **only the working area**. The stage stays put and re-poses,
//  the port list stays put and re-densifies, the footer stays put and
//  re-labels — which is what makes the app feel like one place rather than
//  eight screens (§2.5).
//
//  Nothing here writes. The two closures it is built with are a *read* that
//  produces the review plan and the *burst* that Core performs; neither is
//  reachable from this file's own code, and there is no path from here to
//  configd or to the administrator prompt.
//

import Foundation
import Observation
import RDMALinkCore

/// What the footer's trailing button is, at this moment.
///
/// `nil` is a real value: on a refusal the primary is **removed**, not
/// disabled, because a disabled button is still an invitation to hunt for the
/// modifier key (§1.3 rule 5, §6.1 rule 6).
struct WizardPrimary: Sendable, Equatable {
    var title: LocalizedStringResource
    var isEnabled: Bool
}

@MainActor
@Observable
final class SetUpFlow {
    /// Reads the world and works out what would change. Pure from the app's
    /// side: `SetUpPorts.preview(world:)` writes nothing.
    typealias Planner = @Sendable ([OperationPort]) async throws -> SetUpPortsPlan

    private(set) var step: WizardStep = .choose
    /// The screen this run opened on, which is what the step label counts
    /// from (§2.3 band 1): three steps from the picker, two from a port that
    /// was already chosen.
    private(set) var openedOn: WizardStep = .choose
    /// Which way the working area pushes: a leading-edge slide forward, the
    /// reverse going back (§2.5).
    private(set) var isMovingForward = true

    /// The receptacles chosen at S4, by BSD name. Physical order is imposed
    /// when the selection is read, never stored, so a live re-read cannot
    /// reorder it.
    private(set) var selection: Set<String> = []

    /// §S4's pre-selection: the choice was made for the user, so S5 says why
    /// in words rather than assuming it — "the reason is stated there". It
    /// is the reason for *that* pick, captured when the pick was made: the
    /// picker's own line is re-derived from the ports, and a second Mac
    /// arriving while S5 is up would turn it into the two-candidates
    /// sentence on a screen where nothing can be chosen (§S4 "After this
    /// screen the choice is frozen"). Cleared the moment they choose.
    private(set) var reviewPreSelectionLine: LocalizedStringResource?

    /// Whether the selection on screen is one the app made.
    var pickedForTheUser: Bool { reviewPreSelectionLine != nil }

    /// S4b is a modal *state* within S4, not a step and not a sheet.
    private(set) var identify: IdentifySession?

    /// S5's plan, once the read behind it has landed.
    private(set) var reviewPlan: SetUpPortsPlan?

    /// S6's run, made when the review is accepted. It exists from the moment
    /// the password is asked for: while macOS has the dialog up the review is
    /// still the screen showing, dimmed (§S5).
    private(set) var apply: ApplyRun?

    /// The inline refusal the current step is showing, if any.
    private(set) var refusal: WizardRefusal?

    /// §S4: something moved while the user was choosing and the selection
    /// survived it.
    private(set) var liveChangeLine: LocalizedStringResource?

    /// R27: a click that routed rather than selected.
    private(set) var routingLine: LocalizedStringResource?

    // MARK: - What it reads

    private(set) var ports: [PortSnapshot] = []
    private(set) var hardware: HardwareModel?
    private(set) var switchState: RDMASwitchState = .unobserved
    private(set) var findings = PreflightFindings()

    /// What the world looked like when the review was asked for, so R17 can
    /// tell that what the user read isn't true any more.
    private var reviewTopology: [String: LinkState] = [:]

    private let planner: Planner
    private let makeRunner: ApplyRun.Runner
    private let finish: @MainActor () -> Void
    private var planning: Task<Void, Never>?

    /// - Parameters:
    ///   - planner: produces S5's plan. A read, never a write.
    ///   - runner: produces S6's events. There is no default: a default would
    ///     be a write path living in the view layer.
    ///   - finish: leaves the assistant — `Back` from S4 and `Done` from S7.
    init(
        planner: @escaping Planner,
        runner: @escaping ApplyRun.Runner,
        finish: @escaping @MainActor () -> Void
    ) {
        self.planner = planner
        self.makeRunner = runner
        self.finish = finish
    }

    // MARK: - Derived screens

    /// §S3's four checks, as S5's Checked group draws them.
    var checks: PreflightReport { PreflightReport(findings) }

    var choose: ChoosePortReport {
        ChoosePortReport(ports: ports, hardware: hardware, selection: selection)
    }

    var ready: ReadyReport {
        ReadyReport(ports: selectedPorts, switchState: switchState)
    }

    /// §2.3 band 1: the one progress label, counting this run's screens.
    var stepCaption: LocalizedStringResource { step.caption(openedOn: openedOn) }

    /// §S5: a refusal replaces the sections. R17 and the permission refusals
    /// are the flow's own; R13 is the checks'; the rest are Core's, whole-Mac
    /// first and then the first port in the way — except R1, R2 and R4, which
    /// are the Checked group's business: they expand it and disable the
    /// default button rather than replacing anything, because they clear by
    /// themselves (§S3, §S5).
    var reviewRefusal: WizardRefusal? {
        if let refusal { return refusal }
        if let replacement = checks.replacement { return replacement }
        guard let plan = reviewPlan else { return nil }
        return plan.refusals.first { !Self.isACheck($0.code) }.map(WizardRefusal.init)
    }

    /// The three refusals §S3's rows answer for. Everything else replaces S5.
    private static func isACheck(_ code: RefusalCode) -> Bool {
        switch code {
        case .twoMacsConnected, .loopedBackIntoThisMac, .volumeMounted: true
        default: false
        }
    }

    /// The chosen receptacles in physical order, which is the order S5's
    /// sections and S6's writes run in.
    var selectedPorts: [PortSnapshot] {
        ports.filter { selection.contains($0.id) }
    }

    /// The selection as Core's operations take it.
    var selectedOperationPorts: [OperationPort] {
        selectedPorts.map { OperationPort($0.port) }
    }

    /// The receptacles a check or a refusal names, for the attention ring.
    var attentionPortIDs: Set<String> {
        let named = Set(reviewRefusal?.subjects ?? [])
        return step == .review ? named.union(checks.attentionPortIDs) : named
    }

    /// §6.2 R2's pair, for the thread the stage draws between them. Only the
    /// checks name it, and they are on S5: the same two receptacles are ringed
    /// there.
    var loopedPortIDs: [String] {
        step == .review ? checks.loopedPortIDs : []
    }

    /// §S4 "After this screen the choice is frozen": on S5, S6 and S7 no row
    /// and no receptacle is a selection target. The stage and the list read
    /// this rather than each guarding a step of their own.
    var isSelectionFrozen: Bool { step != .choose }

    /// The selection the stage holds while it is frozen, or `nil` while the
    /// user is still choosing.
    var frozenSelection: Set<String>? { isSelectionFrozen ? selection : nil }

    /// §S5: "OS password dialog up (the working area dims 20 % and says
    /// nothing over it)".
    var isAuthorizing: Bool { step == .review && apply?.phase == .authorizing }

    // MARK: - The footer

    /// §S4b: `Cancel` leading while Identify is up, `Back` everywhere else.
    var backTitle: LocalizedStringResource {
        identify != nil ? WizardAction.cancel.title : WizardAction.back.title
    }

    /// §2.3 band 4. `nil` means the button is gone, not greyed.
    var primary: WizardPrimary? {
        // §S4b's footer: a contextual default button that appears only once
        // there is an answer, over a `Cancel` that is always there.
        if let identify {
            guard let action = identify.defaultAction else { return nil }
            return WizardPrimary(title: action.title, isEnabled: true)
        }
        switch step {
        case .choose:
            // §1.3 rule 5: a refusal removes the primary action entirely, so
            // there are never two default buttons on screen and never a
            // disabled one inviting a modifier key.
            guard refusal == nil else { return nil }
            return WizardPrimary(
                title: WizardAction.continue.title, isEnabled: !selection.isEmpty)
        case .review:
            guard reviewRefusal == nil, let plan = reviewPlan, !plan.ports.isEmpty,
                plan.ports.allSatisfy(\.canProceed)
            else { return nil }
            // §S3: a check that said no *disables* the button, with the reason
            // above the separator, because the check clears by itself. The
            // greying while the dialog is up is the same shape as re-checking.
            return WizardPrimary(
                title: LocalizedStringResource(core: plan.buttonTitle),
                isEnabled: checks.canProceed && !isAuthorizing)
        case .apply:
            // S6's buttons disappear entirely: there is no control the app
            // could honour once the burst has started.
            return nil
        case .ready:
            return WizardPrimary(title: WizardAction.done.title, isEnabled: true)
        }
    }

    /// §6.1 rule 10: `Back` always remains, so the only ways out of a refusal
    /// are backwards or fixing the cause. The exceptions are the password
    /// moment and the burst, which cannot be interrupted, and S7, where there
    /// is nothing to go back to.
    var showsBack: Bool {
        if identify != nil { return true }
        switch step {
        case .choose:
            return true
        case .review:
            return !isAuthorizing
        case .apply:
            return apply?.phase == .refused
        case .ready:
            return false
        }
    }

    /// Printed in `.callout` `.orange` directly above the footer separator.
    var disabledReason: LocalizedStringResource? {
        step == .review && reviewRefusal == nil ? checks.disabledReason : nil
    }

    /// `.caption` secondary between `Back` and the primary.
    var footerCaption: LocalizedStringResource? {
        step == .choose ? choose.counter : nil
    }

    // MARK: - Live state

    /// Every live read lands here. The whole assistant re-derives itself from
    /// it, which is what makes a check flip in the same beat as the cable.
    func update(
        ports: [PortSnapshot],
        hardware: HardwareModel?,
        switchState: RDMASwitchState,
        findings: PreflightFindings
    ) {
        let previous = self.ports
        let checksBefore = checks.rows.map(\.state)
        self.ports = ports
        self.hardware = hardware
        self.switchState = switchState
        self.findings = findings

        // A receptacle that stopped being reported cannot stay selected.
        selection.formIntersection(Set(ports.map(\.id)))

        identify?.observe(ports.map(IdentifyObservation.init))
        identify?.tick()

        noteLiveChange(previous: previous, current: ports)
        checkReviewTopology(current: ports)
        // §S3 "A check flips live": the plan carries Core's own answer to the
        // same four questions, so it is read again when a row changes its
        // mind — a route that appears takes R5's card away, and a cable that
        // arrives puts it up — without the sections vanishing in between.
        if step == .review, apply == nil, checks.rows.map(\.state) != checksBefore {
            beginPlanning(keepingPlan: true)
        }
    }

    // MARK: - Opening

    /// The run's first screen (§S4 "When this screen appears"). The choice is
    /// made at the beginning, and only once: a port already in hand — chosen
    /// on the hub, double-clicked, or a row's own set-up action — opens the
    /// run on S5 with it, and so does a pre-selection; otherwise it opens on
    /// S4. A port in hand that S4 would route elsewhere gets S4 and the same
    /// answer a click there would give.
    func open(choosing portID: String?) {
        if let portID {
            if route(for: portID) == nil { selection = [portID] }
        } else {
            let picker = choose
            selection = picker.preSelection
            reviewPreSelectionLine = selection.isEmpty ? nil : picker.preSelectionLine
        }
        openedOn = selection.isEmpty ? .choose : .review
        move(to: openedOn)
        if let portID, selection.isEmpty { routeClick(portID) }
        if step == .review { beginReview() }
    }

    // MARK: - Moving

    func goForward() {
        if let session = identify {
            switch session.defaultAction {
            case .useThisPort: useIdentifiedPort()
            case .identifyAgain: session.restart()
            case .pickFromTheList: dismissIdentify()
            default: break
            }
            return
        }
        guard let primary, primary.isEnabled else { return }
        switch step {
        case .choose:
            move(to: .review)
            beginReview()
        case .review:
            // §S5: "pressing it asks macOS for the password straight away —
            // there is no screen between this one and the work."
            guard let plan = reviewPlan, apply == nil else { return }
            let run = ApplyRun(plan: plan, runner: makeRunner)
            run.onPhaseChange = { [weak self] phase in self?.applyPhaseChanged(phase) }
            apply = run
            run.begin()
        case .apply:
            break
        case .ready:
            finish()
        }
    }

    /// Escape, and the footer's leading button. Always backwards, never
    /// forwards (§8.3).
    func goBack() {
        if identify != nil {
            cancelIdentify()
            return
        }
        refusal = nil
        switch step {
        case .choose:
            finish()
        case .review:
            planning?.cancel()
            reviewPlan = nil
            // A card can be acted on while the OS dialog is up (R17 lands
            // from the topology check); a burst must not start against a
            // screen that is no longer S5.
            apply?.cancel()
            apply = nil
            // §S4: "`Back` from S5 is this screen, for anyone who'd rather
            // choose." Once they are choosing, the choice is theirs, and the
            // run now has the picker in it, so the label counts it.
            reviewPreSelectionLine = nil
            openedOn = .choose
            move(to: .choose, forward: false)
        case .apply:
            apply?.cancel()
            apply = nil
            move(to: .review, forward: false)
            beginReview()
        case .ready:
            finish()
        }
    }

    /// R7's `Try Again`, and R8's and R10's: "returns to S5 with the
    /// selection intact; the default button asks again" (§6.2 R7). S5
    /// proper — the sections and a live `Set Up Port` — so what will change
    /// can be read again before it is asked for again; the card's button is
    /// the way back, not the ask. A refusal that came before the first write
    /// is already on S5, so only its card goes; one that came after returns
    /// there after re-verifying the world (§6.2 R8, R10).
    func tryAgain() {
        switch step {
        case .review:
            apply?.cancel()
            apply = nil
            refusal = nil
        case .apply:
            apply?.cancel()
            apply = nil
            move(to: .review, forward: false)
            beginReview()
        case .choose, .ready:
            break
        }
    }

    /// S6 finished: S7 follows about 400 ms after the last checkmark settles.
    func advanceToReady() {
        guard step == .apply, apply?.phase == .finished else { return }
        move(to: .ready)
    }

    /// **Review hook only** (App/SnapshotHook.swift). Puts the assistant on a
    /// screen without walking the gates in front of it, so each one can be
    /// captured on a Mac whose own state would stop at the first, and with
    /// the run shape the label is to be seen with.
    ///
    /// It reads and it draws. S6's burst is not reachable this way: nothing
    /// here presses S5's button, which is the only thing that asks for the
    /// credential.
    func route(to step: WizardStep, openedOn first: WizardStep) {
        // A Mac where every port routes somewhere else has nothing to plan
        // once `open(choosing:)` has rightly refused it, so a review route
        // takes the first receptacle that exists rather than none. The
        // picker is left as it opened: §S4's `Continue` is "disabled until a
        // selectable port is chosen", and a render of S4 with nothing chosen
        // has to show that.
        if step == .review, selection.isEmpty,
            let port = ports.first(where: { $0.port.isThunderbolt })
        {
            selection = [port.id]
        }
        openedOn = first
        // A run that opened on the picker chose for itself (§S4), so it has
        // no rationale line — `goBack()` clears it the same way.
        if first == .choose { reviewPreSelectionLine = nil }
        move(to: step)
        if step == .review { beginReview() }
    }

    private func move(to next: WizardStep, forward: Bool = true) {
        isMovingForward = forward
        refusal = nil
        liveChangeLine = nil
        routingLine = nil
        step = next
    }

    /// S5 opens: remember what the user is about to read, and read it.
    private func beginReview() {
        reviewTopology = topology(of: selectedPorts)
        beginPlanning()
    }

    /// The plan is a read, so a task that outlives the screen costs nothing
    /// and writes nothing; it is cancelled the moment another one starts or
    /// the user goes back.
    ///
    /// - Parameter keepingPlan: a live re-read replaces the plan when the new
    ///   one lands rather than taking the sections down in the meantime.
    private func beginPlanning(keepingPlan: Bool = false) {
        planning?.cancel()
        if !keepingPlan { reviewPlan = nil }
        let ports = selectedOperationPorts
        guard !ports.isEmpty else { return }
        planning = Task { [planner] in
            do {
                let plan = try await planner(ports)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.step == .review else { return }
                    self.reviewPlan = plan
                }
            } catch let refusal as Refusal {
                await MainActor.run { self.land(refusal: WizardRefusal(refusal)) }
            } catch is CancellationError {
                // The user went back. Nothing to say.
            } catch {
                await MainActor.run { self.land(refusal: WizardRefusals.arrangementChanged) }
            }
        }
    }

    /// A refusal the planner raised, put on screen only if the screen it is
    /// about is still the one showing.
    ///
    /// The read behind S5 is a `Task.detached`, which a parent's cancellation
    /// does not reach, so it runs to completion after `Back`. Landing its
    /// refusal on S4 would draw a card about a review the user has already
    /// left — and `primary` removes `Continue` whenever S4 has a refusal, so
    /// the only way out would be clicking a port row.
    private func land(refusal: WizardRefusal) {
        guard step == .review else { return }
        self.refusal = refusal
    }

    /// What the run reports. The permission landing is what moves S5 to S6;
    /// a refusal before the first write is S5's to show, "back here with the
    /// selection intact" (§S5) — the run is over and its card is the review's.
    private func applyPhaseChanged(_ phase: ApplyRun.Phase) {
        switch phase {
        case .authorizing, .finished:
            break
        case .running:
            if step == .review { move(to: .apply) }
        case .refused:
            guard step == .review, let refusal = apply?.refusal else { return }
            apply = nil
            self.refusal = refusal
        }
    }

    // MARK: - Selection (S4)

    /// A plain click: one port, replacing whatever was chosen. Only S4 has a
    /// selection to make (§S4 "After this screen the choice is frozen").
    func select(_ id: String) {
        guard step == .choose else { return }
        guard route(for: id) == nil else { return routeClick(id) }
        // R3's recovery, and R16's: choosing a port that works is the way out
        // of a refusal about one that doesn't.
        refusal = nil
        selection = [id]
        reviewPreSelectionLine = nil
        liveChangeLine = nil
        routingLine = nil
    }

    /// ⌘-click and ⇧-click. §S4's multi-select, which runs one port after the
    /// other from the same password.
    func extendSelection(_ id: String) {
        guard step == .choose else { return }
        guard route(for: id) == nil else { return routeClick(id) }
        refusal = nil
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
        reviewPreSelectionLine = nil
        liveChangeLine = nil
        routingLine = nil
    }

    /// Where a click on this receptacle goes, or `nil` when it simply selects.
    func route(for id: String) -> ChooseRefusalRoute? {
        guard let snapshot = ports.first(where: { $0.id == id }) else { return nil }
        return ChoosePortReport.route(for: snapshot)
    }

    private func routeClick(_ id: String) {
        guard let snapshot = ports.first(where: { $0.id == id }),
            let route = ChoosePortReport.route(for: snapshot)
        else { return }
        switch route {
        case .usbPort:
            refusal = WizardRefusals.usbPort(isMacMini: hardware?.archetype == .mini)
        case .alreadyReady:
            refusal = nil
            routingLine = WizardRefusals.alreadyALink
        case .adopt:
            refusal = nil
            routingLine = WizardRefusals.alreadyDoneProperly
        case .foreignService:
            refusal = WizardRefusals.foreignService(
                positionName: snapshot.port.positionName, portBSDName: snapshot.port.bsdName)
        }
    }

    // MARK: - Identify (S4b)

    func beginIdentify() {
        identify = IdentifySession(
            previousSelection: selection,
            previousPositionName: selectedPorts.first?.port.positionName)
        identify?.observe(ports.map(IdentifyObservation.init))
    }

    /// Cancelling returns to S4 with the previous selection intact.
    func cancelIdentify() {
        guard let session = identify else { return }
        selection = session.previousSelection.intersection(Set(ports.map(\.id)))
        identify = nil
    }

    /// `Use This Port`.
    func useIdentifiedPort() {
        guard let port = identify?.identified, port.isThunderbolt else { return }
        identify = nil
        select(port.id)
    }

    /// `Pick from the List`.
    func dismissIdentify() { identify = nil }

    // MARK: - R17

    private func topology(of ports: [PortSnapshot]) -> [String: LinkState] {
        Dictionary(ports.map { ($0.id, $0.port.link) }, uniquingKeysWith: { first, _ in first })
    }

    /// §S5: "Topology changed since S4 → R17." The review stops before doing
    /// anything rather than act on old information. Core raises the same
    /// refusal again inside the burst, from its own re-read, so a cable that
    /// moves between this screen and the password cannot slip through either.
    private func checkReviewTopology(current: [PortSnapshot]) {
        guard step == .review, !reviewTopology.isEmpty, refusal == nil else { return }
        let now = topology(of: current.filter { reviewTopology[$0.id] != nil })
        guard now != reviewTopology else { return }
        refusal = WizardRefusals.arrangementChanged
    }

    /// §S4's live-change line. Not a refusal: the selection survives, and the
    /// user is asked to look rather than told off.
    private func noteLiveChange(previous: [PortSnapshot], current: [PortSnapshot]) {
        guard step == .choose, !selection.isEmpty else { return }
        let before = topology(of: previous)
        guard
            let moved = current.first(where: {
                selection.contains($0.id) && before[$0.id] != nil && before[$0.id] != $0.port.link
            })
        else { return }
        liveChangeLine = ChooseLiveChange.line(positionName: moved.port.positionName)
    }
}
