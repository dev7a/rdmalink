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
    /// The screen this run opened on, fixed when it opens and never changed
    /// (§2.3 band 1): the picker for the footer's `Set Up Port…` and ⌘N,
    /// which have three steps; Review for a control that names its port,
    /// which has two and no picker in it. The step label counts from it, and
    /// its first screen's leading button reads `Cancel` (§2.3 band 4).
    private(set) var openedOn: WizardStep = .choose
    /// Which way the working area pushes: a leading-edge slide forward, the
    /// reverse going back (§2.5).
    private(set) var isMovingForward = true

    /// The receptacles chosen at S4, by BSD name. Physical order is imposed
    /// when the selection is read, never stored, so a live re-read cannot
    /// reorder it.
    private(set) var selection: Set<String> = []

    /// §S4's pre-selection: the port this run picked for the user when it
    /// opened, because it was the one with a Mac on the end. The picker
    /// states why only while that pick is still the selection, and it is
    /// forgotten the moment the user chooses (`select`, `extendSelection`). A
    /// port that came from the hub is the user's own choice and is never
    /// this. S5 never says any of it: the choice was made before S5.
    private(set) var picked: Set<String>?

    /// Whether the selection on screen is one the app made.
    var pickedForTheUser: Bool { picked != nil && picked == selection }

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
    /// The dimmed row whose click printed `routingLine`. It is the row the
    /// Port menu's `Restore…` and `Adopt…` mean on the picker, the one place
    /// a sheet may open over the assistant (§2.6, §2.7). It goes with the line.
    private(set) var routedPortID: String?

    /// §6.2 R17's recovery: the port that moved, breathing once while S5 is
    /// read again. Cleared after one breath (§3.5: 1.6 s).
    private(set) var breathing: Set<String> = []
    private var breath: Task<Void, Never>?

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
    ///   - finish: leaves the assistant — `Cancel` on the run's first screen,
    ///     `Done` on S7 and on a refused S6's card.
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
        ChoosePortReport(ports: ports, hardware: hardware, selection: selection, picked: picked)
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
    /// themselves (§S3, §S5). Last, R27's backstop: a port Core would route
    /// to Adopt and never plan is a card, never an empty Review.
    var reviewRefusal: WizardRefusal? {
        let card: WizardRefusal?
        if let refusal {
            card = refusal
        } else if let replacement = checks.replacement {
            card = replacement
        } else if let plan = reviewPlan {
            card = plan.refusals.first { !Self.isACheck($0.code) }.map(reviewCard)
                ?? routesToAdopt(plan)
        } else {
            card = nil
        }
        return card.map(onReview)
    }

    /// The row a card keeps on S5. The footer's leading button is the way
    /// out there, so a card never repeats it or offers a second one — no
    /// `Back`, no `Cancel`, no `Done` (§6.1 rule 10) — and a run that opened
    /// on S5 never had a picker for `Choose Another Port` to go back to
    /// (§6.2 R16): the footer's `Cancel` is its way out.
    private func onReview(_ card: WizardRefusal) -> WizardRefusal {
        var unwanted: Set<WizardAction> = [.back, .cancel, .done]
        if openedOn == .review { unwanted.insert(.chooseAnotherPort) }
        return card.removing(unwanted)
    }

    /// Core's refusal as S5 draws it — save R16 over the service RDMALink
    /// made, given a fixed IPv4 address by hand since. Core sees the address
    /// and not whose service it is, and "It isn't RDMALink's" would be false
    /// (§1.3 rule 10): that port is R27's backstop, headed as R28 is, the
    /// route the picker and the row name for it (§6.2 R27, §S5).
    private func reviewCard(_ refusal: Refusal) -> WizardRefusal {
        guard refusal.code == .foreignService,
            let snapshot = ports.first(where: { refusal.subjects.contains($0.port.bsdName) }),
            ChoosePortReport.route(for: snapshot) == .editedService,
            let line = ChoosePortReport.routingLine(for: .editedService, snapshot: snapshot)
        else { return WizardRefusal(refusal) }
        return WizardRefusals.routesToAdopt(
            line: line,
            headline: ChoosePortReport.backstopHeadline(for: .editedService, snapshot: snapshot),
            portBSDName: snapshot.port.bsdName)
    }

    /// §S5's R27 card, for the first port the plan routes to Adopt, in the
    /// words the picker would have used for it — and headed as that route
    /// is (§6.2 R27): S9's full-match headline for a port set up properly,
    /// S9's near-match one for a near match, R28's for RDMALink's own service
    /// edited since. A service of its own on a port still in a bridge, which
    /// Adopt can't take either, is R16's card instead, as it is on the picker.
    private func routesToAdopt(_ plan: SetUpPortsPlan) -> WizardRefusal? {
        guard let adopting = plan.ports.first(where: \.routesToAdopt) else { return nil }
        let bsdName = adopting.port.bsdName
        let snapshot = ports.first { $0.port.bsdName == bsdName }
        let route = snapshot.flatMap(ChoosePortReport.route(for:))
        if let snapshot, route == .foreignService {
            return WizardRefusals.foreignService(snapshot)
        }
        // A port this reading doesn't route — it changed after the plan was
        // read — keeps R27's plain full-match words, as the card always has.
        guard let snapshot, let route,
            let line = ChoosePortReport.routingLine(for: route, snapshot: snapshot)
        else {
            return WizardRefusals.routesToAdopt(
                line: "This one was set up by hand, and properly. Adopt… looks after it without changing it.",
                headline: WizardRefusals.alreadySetUpHeadline, portBSDName: bsdName)
        }
        return WizardRefusals.routesToAdopt(
            line: line, headline: ChoosePortReport.backstopHeadline(for: route, snapshot: snapshot),
            portBSDName: bsdName)
    }

    /// §S6: a refused S6's card. The footer's leading button stays hidden
    /// there, so the card holds every way out: R8's and R10's `Try Again` and
    /// `Done`, R11's `Done` — and `Done` on any other refusal that lands
    /// there (R9, R12, R14), which would otherwise leave no way out at all.
    ///
    /// After a partial run the ports that landed are listed under the card,
    /// and its "Nothing has been changed." goes: the run did change
    /// something, and a summary never rounds up (§S6, §S10).
    var applyRefusal: WizardRefusal? {
        guard step == .apply, let apply, var card = apply.refusal else { return nil }
        if !apply.landed.isEmpty { card.rollbackLine = nil }
        return card.removing([.back, .cancel]).adding(.done)
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
        let named = Set(reviewRefusal?.subjects ?? []).union(breathing)
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

    /// §S4b: `Cancel` leading while Identify is up. §2.3 band 4: `Cancel` on
    /// the run's first screen — the picker, or Review in a run that opened
    /// there — because `goBack()` there leaves the assistant, and `Back`
    /// moves between steps and never dismisses. `Back` only on Review in a
    /// run that opened on the picker, where it goes to the picker.
    var backTitle: LocalizedStringResource {
        identify != nil || step == openedOn ? WizardAction.cancel.title : WizardAction.back.title
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

    /// §6.1 rule 10: the leading button — `Back`, or `Cancel` on a run's
    /// first screen — always remains beside a refusal, so the only ways out
    /// are backwards or fixing the cause. The exceptions are the password
    /// moment and S6, and S7, where there is nothing to go back to. On S6 it
    /// stays hidden even once the run is refused: the card holds every way
    /// out (`applyRefusal`), and a `Back` beside it would re-plan over what
    /// the card says — after R11, over the one note that says how the port
    /// was (§S6).
    var showsBack: Bool {
        if identify != nil { return true }
        switch step {
        case .choose:
            return true
        case .review:
            return !isAuthorizing
        case .apply, .ready:
            return false
        }
    }

    /// §8.3, Escape on the picker: a card is a layer of its own, so Escape
    /// puts it away first and only the next one leaves. The footer's button
    /// keeps its words and its click: it is still `Cancel`.
    var escapePutsCardAway: Bool {
        step == .choose && identify == nil && refusal != nil
    }

    /// §2.6, §2.7: how much of the assistant the menus have to leave alone.
    /// The window mirrors it into the hub's actions.
    var presence: AssistantPresence {
        step == .choose && identify == nil ? .picker(routed: routedPortID) : .underWay
    }

    /// Printed in `.callout` `.primary`, behind the orange attention symbol,
    /// directly above the footer separator (§2.3 band 4).
    var disabledReason: LocalizedStringResource? {
        step == .review && reviewRefusal == nil ? checks.disabledReason : nil
    }

    /// §2.3 band 4: the screen's own other buttons, just before the default
    /// and after the caption — S4b's `Identify Again…` and `Choose from
    /// List`, S7's `What to Do on the Other Mac`. Band 2 holds none (§2.3
    /// band 2).
    var footerSecondaries: [WizardAction] {
        if let identify { return identify.secondaryActions }
        return step == .ready ? [.whatToDoOnTheOtherMac] : []
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
        refreshRoutingLine()
        // §S3 "A check flips live": the plan carries Core's own answer to the
        // same four questions, so it is read again when a row changes its
        // mind — a route that appears takes R5's card away, and a cable that
        // arrives puts it up — without the sections vanishing in between.
        if step == .review, apply == nil, checks.rows.map(\.state) != checksBefore {
            beginPlanning(keepingPlan: true)
        }
    }

    // MARK: - Opening

    /// The run's first screen, and with it the run's shape, which never
    /// changes afterwards (§2.3 band 1, §S4 "When this screen appears").
    ///
    /// `.choose` — the footer and ⌘N — always opens the picker, step 1 of 3.
    /// The port selected on the hub comes with it when set-up can take it,
    /// by the same test a row's `Set Up…` uses, and says nothing: the user
    /// chose it. Otherwise the one port set-up can take with a Mac linked is
    /// picked, and the picker says why (`ChoosePortReport.preSelectionLine`).
    ///
    /// `.port` — a control that names its port — opens Review for it, step 1
    /// of 2, and has no picker in it. Core's plan answers for the port there,
    /// as it would for any port: a refusal, or R27's card.
    func open(_ request: SetUpRequest) {
        switch request {
        case .choose(let suggested):
            openedOn = .choose
            if let suggested, let port = ports.first(where: { $0.id == suggested }),
                PortRowPresentation.offersSetUp(port) {
                selection = [suggested]
                picked = nil
            } else {
                selection = []
                let pick = choose.preSelection
                selection = pick
                picked = pick.isEmpty ? nil : pick
            }
            move(to: .choose)
        case .port(let id):
            openedOn = .review
            selection = ports.contains { $0.id == id } ? [id] : []
            picked = nil
            move(to: .review)
            beginReview()
        }
    }

    // MARK: - Moving

    func goForward() {
        if let session = identify {
            switch session.defaultAction {
            case .useThisPort: useIdentifiedPort()
            case .identifyAgain: session.restart()
            case .chooseFromList: dismissIdentify()
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

    /// The footer's leading button, and Escape. Always backwards, never
    /// forwards (§8.3): `Back` moves between steps, and on the run's first
    /// screen `Cancel` returns to where the run started — the hub, or the
    /// change log if it started there (§2.3 band 4).
    func goBack() {
        if identify != nil {
            cancelIdentify()
            return
        }
        // While macOS's password dialog is up nothing on S5 leads here — the
        // footer's leading button is hidden and a card is inert — and nothing
        // could honour it: cancelling stops only the task that reads the
        // burst's progress, never the burst waiting on the dialog
        // (`OperationHost`), which would then write with nothing on screen.
        // So the door is shut here too.
        guard !isAuthorizing else { return }
        refusal = nil
        switch step {
        case .choose:
            finish()
        case .review:
            planning?.cancel()
            reviewPlan = nil
            // Only a run that is over reaches here: its answer has already
            // landed as S5's card, and the run is let go with it.
            apply?.cancel()
            apply = nil
            // A run that opened here has no picker to go back to: this is
            // its first screen, and the button reads `Cancel`.
            if openedOn == .review {
                finish()
            } else {
                move(to: .choose, forward: false)
            }
        case .apply:
            // No leading button on S6, running or refused: the burst can't be
            // interrupted, and a refused S6's card holds every way out (§S6).
            break
        case .ready:
            finish()
        }
    }

    /// §8.3: Escape, one layer at a time. On the picker a card goes first,
    /// leaving the selection as it was — as R16's `Choose Another Port` does
    /// — and only then does Escape act as `Cancel`.
    func escape() {
        if escapePutsCardAway {
            refusal = nil
        } else {
            goBack()
        }
    }

    /// §S6: `Done` on a refused S6's card, R8's, R10's and R11's alike. The
    /// assistant closes the way S7's `Done` closes it, back to where the run
    /// started. Nothing was left half-changed (R8, R10), or the hub's
    /// needs-a-hand row takes over (R11) — which is why this never returns to
    /// S5 to plan the port again.
    func leave() {
        planning?.cancel()
        apply?.cancel()
        apply = nil
        finish()
    }

    /// R7's `Try Again`, and R8's and R10's: "returns to S5 with the
    /// selection intact. `Try Again` brings back what will change; `Set Up
    /// Port` asks again" (§6.2 R7). S5 proper — the sections and a live `Set Up Port` — so what will change
    /// can be read again before it is asked for again; the card's button is
    /// the way back, not the ask. A refusal that came before the first write
    /// is already on S5, so only its card goes; one that came after returns
    /// there after re-verifying the world (§6.2 R8, R10) — and a port that
    /// landed before the run stopped is set up now, so it is not planned
    /// again: S5 plans only the ports that did not land (§S6).
    func tryAgain() {
        // Never over a run waiting on macOS's dialog, which this could not
        // cancel (`goBack`).
        guard !isAuthorizing else { return }
        switch step {
        case .review:
            apply?.cancel()
            apply = nil
            refusal = nil
        case .apply:
            let landed = Set(apply?.landed.map(\.bsdName) ?? [])
            let unfinished = selection.filter { id in
                !landed.contains(ports.first { $0.id == id }?.port.bsdName ?? id)
            }
            if !unfinished.isEmpty { selection = unfinished }
            apply?.cancel()
            apply = nil
            move(to: .review, forward: false)
            beginReview()
        case .choose, .ready:
            break
        }
    }

    /// §6.2 R16's `Choose Another Port`. On the picker it puts the card away
    /// and leaves the user choosing, the way clicking a port that works does
    /// (`select(_:)`) — `goBack()` there would leave the assistant, which is
    /// `Cancel`'s job (§2.3 band 4). Raised on S5 in a run that opened on the
    /// picker, it is `Back` to the picker; a run that opened on S5 has no
    /// picker, and its card never carries the button (`onReview`).
    func chooseAnotherPort() {
        guard step == .choose else { return goBack() }
        refusal = nil
    }

    /// `Check Again` on a card in the assistant, after the window has re-read
    /// this Mac (`WizardPerformer`). The read alone clears a card only when
    /// one of §S3's rows changes its mind; a card the run put up, or one the
    /// plan raised that no check is about, needs looking at again itself.
    ///
    /// - On S5 with a card up (R12 after the password, R14, R15, …): the card
    ///   goes and S5 is read again in place — a read, never a write — so the
    ///   plan raises whatever is still true, and `Set Up Port` asks again
    ///   when nothing is (§6.2 R12).
    /// - On a refused S6 whose card carries it (R9, R12, R14): back to S5 the
    ///   way `Try Again` goes, planning only the ports that did not land —
    ///   nothing was written for the port the card is about (§S6).
    /// - On R11's S6: nothing more. It never returns to S5, where planning
    ///   the port again would write a fresh note over the one that says how
    ///   it was, so the window's re-read in place is the whole answer: the
    ///   list and the model show the port back in the bridge once it has
    ///   been added back by hand (§6.2 R11).
    /// - Everywhere else — the picker, the Checked group with no card — the
    ///   window's re-read is the whole answer.
    func checkAgain() {
        switch step {
        case .review:
            guard apply == nil, reviewRefusal != nil else { return }
            refusal = nil
            beginReview()
        case .apply:
            guard let card = applyRefusal, card.actions.contains(.checkAgain),
                card.code != RefusalCode.rollbackFailed.rawValue
            else { return }
            tryAgain()
        case .choose, .ready:
            break
        }
    }

    /// §6.2 R17's `Take Another Look`: S5 read again in place, in either run
    /// shape — what the user is reading is captured afresh and the plan is
    /// read again — with the port that moved breathing once. The new plan,
    /// or its card, says what is true now; the footer's leading button stays
    /// the way to choose again or to leave.
    func takeAnotherLook() {
        // R17 never lands while macOS's dialog is up (`checkReviewTopology`),
        // and a run waiting on it is not one this could cancel (`goBack`).
        guard step == .review, !isAuthorizing else { return }
        let moved = Set(reviewRefusal?.subjects ?? [])
        apply?.cancel()
        apply = nil
        refusal = nil
        beginReview()
        breathe(moved)
    }

    /// One 1.6 s breath on these receptacles (§3.5), through the same
    /// attention ring the checks use.
    private func breathe(_ ids: Set<String>) {
        breath?.cancel()
        breathing = ids
        guard !ids.isEmpty else { return }
        breath = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            self?.breathing = []
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
        // A picker that opened with nothing chosen has nothing to plan, so a
        // review route takes the first port set-up can take — or, on a Mac
        // where every port routes somewhere else, the first receptacle that
        // exists rather than none, so S5 shows Core's answer for it. The
        // picker is left as it opened: §S4's `Continue` is "disabled until a
        // selectable port is chosen", and a render of S4 with nothing chosen
        // has to show that.
        if step == .review, selection.isEmpty,
            let port = ports.first(where: PortRowPresentation.offersSetUp)
                ?? ports.first(where: { $0.port.isThunderbolt })
        {
            selection = [port.id]
        }
        openedOn = first
        move(to: step)
        if step == .review { beginReview() }
    }

    private func move(to next: WizardStep, forward: Bool = true) {
        isMovingForward = forward
        refusal = nil
        liveChangeLine = nil
        clearRoutingLine()
        step = next
    }

    /// R27's line and the row it is about go together.
    private func clearRoutingLine() {
        routingLine = nil
        routedPortID = nil
    }

    /// R27's line says what the row is now. A sheet the picker opened for it
    /// can change the answer — a port restored or adopted over the picker —
    /// and the line then follows the row, or goes once the row routes nowhere.
    private func refreshRoutingLine() {
        guard let id = routedPortID else { return }
        guard let snapshot = ports.first(where: { $0.id == id }),
            let route = ChoosePortReport.route(for: snapshot),
            let line = ChoosePortReport.routingLine(for: route, snapshot: snapshot)
        else { return clearRoutingLine() }
        if routingLine != line { routingLine = line }
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
                await MainActor.run { self.land(refusal: WizardRefusals.arrangementChanged()) }
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
        // The choice is the user's now, and RDMALink's reason goes with it.
        picked = nil
        liveChangeLine = nil
        clearRoutingLine()
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
        picked = nil
        liveChangeLine = nil
        clearRoutingLine()
    }

    /// Where a click on this receptacle goes, or `nil` when it simply selects.
    func route(for id: String) -> ChooseRefusalRoute? {
        guard let snapshot = ports.first(where: { $0.id == id }) else { return nil }
        return ChoosePortReport.route(for: snapshot)
    }

    /// §6.2 R27, R3 and R16: a click on a dimmed row. A route prints one
    /// line that names the row's own button — nothing opens until that button
    /// is pressed, and it is the one sheet the picker lets open over it
    /// (§2.6); the Port menu's item for it means this row until the line goes
    /// (§2.7). A USB-only port and R16's raise their card instead.
    private func routeClick(_ id: String) {
        guard let snapshot = ports.first(where: { $0.id == id }),
            let route = ChoosePortReport.route(for: snapshot)
        else { return }
        switch route {
        case .usbPort:
            clearRoutingLine()
            refusal = WizardRefusals.usbPort(isMacMini: hardware?.archetype == .mini)
        case .foreignService:
            clearRoutingLine()
            refusal = WizardRefusals.foreignService(snapshot)
        case .alreadyReady, .needsAHand, .adopt, .editedService:
            refusal = nil
            routingLine = ChoosePortReport.routingLine(for: route, snapshot: snapshot)
            routedPortID = id
        }
    }

    // MARK: - Identify (S4b)

    /// S4b, from the picker's own `Identify Port…` or the Port menu's ⌘I
    /// (§2.7). The picker's alone: nothing starts it on S5 to S7, where the
    /// choice is frozen.
    func beginIdentify() {
        guard step == .choose, identify == nil else { return }
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

    /// `Choose from List`.
    func dismissIdentify() { identify = nil }

    // MARK: - R17

    private func topology(of ports: [PortSnapshot]) -> [String: LinkState] {
        Dictionary(ports.map { ($0.id, $0.port.link) }, uniquingKeysWith: { first, _ in first })
    }

    /// §S5: "Topology changed since S4 → R17." The review stops before doing
    /// anything rather than act on old information. Core raises the same
    /// refusal again inside the burst, from its own re-read, so a cable that
    /// moves between this screen and the password cannot slip through either.
    ///
    /// Never while a run exists. While macOS's dialog is up a card here would
    /// offer `Take Another Look`, a cancel the app cannot honour: the burst is
    /// waiting on the dialog and writes if the user then authenticates. Core
    /// re-reads inside the burst and raises R17 itself before any write, and
    /// that lands on S5 as the run's answer (`applyPhaseChanged`).
    private func checkReviewTopology(current: [PortSnapshot]) {
        guard step == .review, apply == nil, !reviewTopology.isEmpty, refusal == nil else {
            return
        }
        let now = topology(of: current.filter { reviewTopology[$0.id] != nil })
        guard now != reviewTopology else { return }
        // The ports that moved — or went — ring while the card is up, and
        // breathe once when S5 is read again (§6.2 R17).
        let moved = reviewTopology.keys.filter { now[$0] != reviewTopology[$0] }.sorted()
        refusal = WizardRefusals.arrangementChanged(subjects: moved)
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
