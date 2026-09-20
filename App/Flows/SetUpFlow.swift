//
//  SetUpFlow.swift
//
//  The set-up assistant's state machine: S3 → S7, the selection, the Identify
//  modal state, the apply run, and the footer (UX_SPEC §2.3, §2.5, §S3–§S7).
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

    private(set) var step: WizardStep = .preflight
    /// Which way the working area pushes: a leading-edge slide forward, the
    /// reverse going back (§2.5).
    private(set) var isMovingForward = true

    /// The receptacles chosen at S4, by BSD name. Physical order is imposed
    /// when the selection is read, never stored, so a live re-read cannot
    /// reorder it.
    private(set) var selection: Set<String> = []

    /// S4b is a modal *state* within S4, not a step and not a sheet.
    private(set) var identify: IdentifySession?

    /// S5's plan, once the read behind it has landed.
    private(set) var reviewPlan: SetUpPortsPlan?

    /// S6's run, made when the review is accepted.
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
    ///   - finish: leaves the assistant — `Back` from S3 and `Done` from S7.
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

    var preflight: PreflightReport { PreflightReport(findings) }

    var choose: ChoosePortReport {
        ChoosePortReport(ports: ports, hardware: hardware, selection: selection)
    }

    var ready: ReadyReport {
        ReadyReport(ports: selectedPorts, switchState: switchState)
    }

    /// §S5: a refusal replaces the sections. R17 is the flow's own; the rest
    /// are Core's, whole-Mac first and then the first port in the way.
    var reviewRefusal: WizardRefusal? {
        if let refusal { return refusal }
        guard let plan = reviewPlan else { return nil }
        return plan.refusals.first.map(WizardRefusal.init)
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
        switch step {
        case .preflight: preflight.attentionPortIDs
        default: Set(reviewRefusal?.subjects ?? [])
        }
    }

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
        case .preflight:
            guard preflight.replacement == nil else { return nil }
            return WizardPrimary(
                title: WizardAction.continue.title, isEnabled: preflight.canContinue)
        case .choose:
            // §1.3 rule 5: a refusal removes the primary action entirely, so
            // there are never two default buttons on screen and never a
            // disabled one inviting a modifier key.
            guard refusal == nil else { return nil }
            return WizardPrimary(
                title: WizardAction.continue.title, isEnabled: !selection.isEmpty)
        case .review:
            guard reviewRefusal == nil, let title = reviewPlan?.defaultButtonTitle else {
                return nil
            }
            return WizardPrimary(title: LocalizedStringResource(core: title), isEnabled: true)
        case .apply:
            // Phase B's buttons disappear entirely: there is no control the
            // app could honour once the burst has started.
            guard apply?.phase == .password else { return nil }
            return WizardPrimary(title: WizardAction.continue.title, isEnabled: true)
        case .ready:
            return WizardPrimary(title: WizardAction.done.title, isEnabled: true)
        }
    }

    /// §6.1 rule 10: `Back` always remains, so the only ways out of a refusal
    /// are backwards or fixing the cause. The two exceptions are the burst,
    /// which cannot be interrupted, and S7, where there is nothing to go back
    /// to.
    var showsBack: Bool {
        if identify != nil { return true }
        switch step {
        case .preflight, .choose, .review:
            return true
        case .apply:
            return apply?.phase == .password || apply?.phase == .refused
        case .ready:
            return false
        }
    }

    /// Printed in `.callout` `.orange` directly above the footer separator.
    var disabledReason: LocalizedStringResource? {
        step == .preflight ? preflight.continueReason : nil
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
        case .preflight:
            move(to: .choose)
            applyPreSelection()
        case .choose:
            move(to: .review)
            reviewTopology = topology(of: selectedPorts)
            beginPlanning()
        case .review:
            guard let plan = reviewPlan, plan.canProceed else { return }
            apply = ApplyRun(plan: plan, runner: makeRunner)
            move(to: .apply)
        case .apply:
            apply?.begin()
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
        case .preflight:
            finish()
        case .choose:
            move(to: .preflight, forward: false)
        case .review:
            planning?.cancel()
            reviewPlan = nil
            move(to: .choose, forward: false)
        case .apply:
            apply?.cancel()
            apply = nil
            move(to: .review, forward: false)
            beginPlanning()
        case .ready:
            finish()
        }
    }

    /// S6 finished: S7 follows about 400 ms after the last checkmark settles.
    func advanceToReady() {
        guard step == .apply, apply?.phase == .finished else { return }
        move(to: .ready)
    }

    /// **Review hook only** (App/SnapshotHook.swift). Puts the assistant on a
    /// screen without walking the gates in front of it, so each one can be
    /// captured on a Mac whose own state would stop at the first.
    ///
    /// It reads and it draws. S6's burst is not reachable this way: the apply
    /// screen still opens in phase A, where nothing has been asked for yet and
    /// the credential is taken by its own button.
    func route(to step: WizardStep) {
        move(to: step)
        if step >= .choose {
            applyPreSelection()
            // The review hook asks for the first Thunderbolt port. On a Mac
            // where every port routes somewhere else, `select(_:)` rightly
            // refuses — and the screen would then have nothing to plan, so the
            // hook takes the first receptacle that exists rather than none.
            if selection.isEmpty, let first = ports.first(where: { $0.port.isThunderbolt }) {
                selection = [first.id]
            }
        }
        if step == .review {
            reviewTopology = topology(of: selectedPorts)
            beginPlanning()
        }
    }

    private func move(to next: WizardStep, forward: Bool = true) {
        isMovingForward = forward
        refusal = nil
        liveChangeLine = nil
        routingLine = nil
        step = next
    }

    /// The plan is a read, so a task that outlives the screen costs nothing
    /// and writes nothing; it is cancelled the moment another one starts or
    /// the user goes back.
    private func beginPlanning() {
        planning?.cancel()
        reviewPlan = nil
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

    // MARK: - Selection (S4)

    /// A plain click: one port, replacing whatever was chosen.
    func select(_ id: String) {
        guard route(for: id) == nil else { return routeClick(id) }
        // R3's recovery, and R16's: choosing a port that works is the way out
        // of a refusal about one that doesn't.
        refusal = nil
        selection = [id]
        liveChangeLine = nil
        routingLine = nil
    }

    /// ⌘-click and ⇧-click. §S4's multi-select, which runs one port after the
    /// other from the same password.
    func extendSelection(_ id: String) {
        guard route(for: id) == nil else { return routeClick(id) }
        refusal = nil
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
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

    /// §S4: the pre-selection is applied once, on arrival, and stated in words
    /// rather than assumed. It never overwrites a choice already made.
    private func applyPreSelection() {
        guard selection.isEmpty else { return }
        selection = choose.preSelection
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
