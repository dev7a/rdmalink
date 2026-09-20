//
//  RestorePlan.swift
//
//  What S10's sheet says, in every form. **The words are RDMALinkCore's**:
//  `RestorePort.preview`, `ReturnToBridge.preview`, `StopManaging` and
//  `RestoreAll` hold the spec's copy, and the same values gate what
//  `perform` will do — so the sheet can never offer a button the burst is
//  going to refuse, and can never refuse something the burst would have done.
//
//  What is left here is the sheet's own shape: which form it is in, which
//  button row §6.2 gives each refusal, and which volumes `Show in Finder`
//  would reveal.
//

import Foundation
import RDMALinkCore

/// A button in the Restore sheet. Every title is §S10's or §6.2's.
///
/// `WizardAction` carries the set-up side's buttons; these are the undo
/// side's, and the two sets barely overlap. **Owed:** one table, once the two
/// slices meet.
enum RestoreAction: String, Sendable, Equatable, Identifiable, CaseIterable {
    case restore
    case returnToBridge
    case stopManaging
    case cancel
    case done
    case tryAgain
    case showInFinder
    case openNetworkSettings
    case copyTheseSteps
    case stopManagingThisPort
    /// §6.2 R28's and R30's `Stop Managing…`: the Port menu's title for
    /// forgetting a note, with its ellipsis, where R19 spells the port out.
    case stopManagingEllipsis
    case setItUpAgain
    case removeMyServiceOnly
    case leaveEverythingAlone
    case copyDetails
    /// §6.2 R12's default: look again, rather than ask for another password.
    case checkAgain

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .restore: "Restore"
        case .returnToBridge: "Return to Bridge"
        case .stopManaging: "Stop Managing"
        case .cancel: "Cancel"
        case .done: "Done"
        case .tryAgain: "Try Again"
        case .showInFinder: "Show in Finder"
        case .openNetworkSettings: "Open Network Settings"
        case .copyTheseSteps: "Copy These Steps"
        case .stopManagingThisPort: "Stop Managing This Port"
        case .stopManagingEllipsis: "Stop Managing…"
        case .setItUpAgain: "Set It Up Again"
        case .removeMyServiceOnly: "Remove My Service Only"
        case .leaveEverythingAlone: "Leave Everything Alone"
        case .copyDetails: "Copy Details"
        case .checkAgain: "Check Again"
        }
    }
}

/// The symbol, the tint and the button row §6.2 gives each refusal that can be
/// raised inside this sheet. The copy itself is Core's and is never re-decided
/// here.
enum RestoreRefusals {
    static func symbol(for code: RefusalCode) -> String {
        switch code {
        case .volumeMounted: "externaldrive"
        default: "exclamationmark.circle"
        }
    }

    /// `.orange` is the panel's warning tint (§3.1) and R20 is the one state
    /// here that is genuinely half-done.
    static func isAttention(_ code: RefusalCode) -> Bool {
        code == .notBackInBridge
    }

    /// §6.2's own rows. The last action is the default.
    ///
    /// Each row keeps a way out, because §6.1 rule 10 leaves `Back` on every
    /// refusal and `Cancel` is this sheet's `Back`.
    static func actions(for code: RefusalCode) -> [RestoreAction] {
        switch code {
        case .volumeMounted:
            [.cancel, .showInFinder]
        case .undoNoteMissing:
            [.stopManagingThisPort, .copyTheseSteps, .openNetworkSettings]
        case .notBackInBridge:
            [.copyTheseSteps, .openNetworkSettings, .tryAgain]
        case .originalBridgeGone:
            [.leaveEverythingAlone, .removeMyServiceOnly]
        case .noBridgeToReturnTo:
            [.cancel, .openNetworkSettings]
        // §6.2 R28 and R30 both write `Stop Managing…`; only R19 spells the
        // port out. The three do the same thing.
        case .createdServiceEdited:
            [.copyDetails, .stopManagingEllipsis, .openNetworkSettings]
        // R30's row, in §6.2's order with the default last: `Cancel` ·
        // `Stop Managing…` · `Set It Up Again`.
        case .noteIsAReturnRecord:
            [.cancel, .stopManagingEllipsis, .setItUpAgain]
        // R12 polls quietly and clears itself when the lock does, so its
        // default looks again rather than asking for another password.
        case .networkBusy:
            [.cancel, .checkAgain]
        case .credentialExpired:
            [.copyDetails, .cancel, .tryAgain]
        default:
            [.copyDetails, .cancel]
        }
    }
}

/// Everything the sheet draws for one subject.
struct RestorePlan: Sendable {
    enum Kind: Sendable, Equatable { case restore, returnToBridge, stopManaging, all }

    var kind: Kind
    var headline: LocalizedStringResource
    /// Absent where a refusal stands in for the whole plan: the refusal names
    /// the situation itself, and two headlines is one too many.
    var body: LocalizedStringResource?
    /// "What will happen", in §S10's order.
    var rows: [LocalizedStringResource] = []
    var notes: [LocalizedStringResource] = []
    var primary: RestoreAction
    /// The live checklist, in the order the writes happen — the same steps the
    /// operation reports, so no row can go unmarked.
    var steps: [OperationStep] = []
    var refusal: Refusal?
    var port: PortSnapshot?
    /// The bridge the port is going back into, for the success line.
    var bridgeName: String?
    /// Restore All's subjects, in physical order.
    var ports: [PortSnapshot] = []
    /// What R4 is about, when it is raised.
    var volumes: [MountedVolume] = []
}

/// Reads the hub's model, so it stays where the model is. The work itself is
/// Core's: this takes a reading and hands back Core's own plan.
@MainActor
enum RestorePlanning {

    static func plan(subject: RestoreSubject, hub: HubActionsModel) -> RestorePlan? {
        guard let world = hub.world else { return nil }
        switch subject {
        case .restore(let portID):
            return restore(portID: portID, hub: hub, world: world)
        case .returnToBridge(let portID):
            return returnToBridge(portID: portID, hub: hub, world: world)
        case .stopManaging(let portID):
            return stopManaging(portID: portID, hub: hub)
        case .all:
            return all(hub: hub, world: world)
        }
    }

    // MARK: - A port RDMALink set up

    private static func restore(
        portID: String, hub: HubActionsModel, world: ObservedWorld
    ) -> RestorePlan? {
        guard let port = hub.snapshot(id: portID) else { return nil }
        // §7.3: an adopted note has no bridge history, and RDMALink "will not
        // invent a history it did not witness". The ordinary thing is §7.5's.
        //
        // An empty bridge list is **not** on its own that case: a port set up
        // while it was already standalone has one too, and it has a service
        // RDMALink made and a note that says so. Sending that port to Return
        // to Bridge would put it into a bridge it was never a member of and
        // overwrite the record of how it really was, under a button that
        // promises "exactly as it was". Only a note with nothing of RDMALink's
        // in it goes the other way (Core asks the same question before it
        // takes a password).
        //
        // A return record is the other note with nothing to undo, and it goes
        // nowhere: the port is already in the bridge. Core's preview names it
        // and refuses, and its refusal is what the sheet shows.
        if let baseline = port.baseline, !baseline.isReturned,
            RestorePort.describesNothingToUndo(baseline) {
            return returnToBridge(portID: portID, hub: hub, world: world)
        }
        let operationPort = OperationPort(port.port)
        let scoped = scope(world, to: [port])
        let core = RestorePort(port: operationPort).preview(note: port.baseline, world: scoped)

        var steps: [OperationStep] = []
        // Named exactly as `perform` names it: the live name of the service the
        // note recorded, whatever it has been renamed to since.
        if port.baseline?.createdService != nil {
            steps.append(.deleteCreatedService(named: core.serviceName ?? ""))
        }
        steps.append(contentsOf: core.bridgesToRejoin.map { .rejoinBridge(named: $0) })
        steps.append(.checkBackInBridge)

        return RestorePlan(
            kind: .restore,
            headline: LocalizedStringResource(core: core.headline),
            body: core.refusal == nil ? LocalizedStringResource(core: core.body) : nil,
            rows: core.refusal == nil ? core.rows.map { LocalizedStringResource(core: $0) } : [],
            notes: core.refusal == nil ? core.notes.map { LocalizedStringResource(core: $0) } : [],
            primary: .restore,
            steps: steps,
            refusal: core.refusal,
            port: port,
            bridgeName: core.bridgesToRejoin.first,
            volumes: scoped.mountedVolumes)
    }

    // MARK: - §7.5 — any port that is out of the bridge

    private static func returnToBridge(
        portID: String, hub: HubActionsModel, world: ObservedWorld
    ) -> RestorePlan? {
        guard let port = hub.snapshot(id: portID) else { return nil }
        let operationPort = OperationPort(port.port)
        let scoped = scope(world, to: [port])
        let core = ReturnToBridge(port: operationPort).preview(world: scoped)

        // §7.5's execution order, which is not the order §S10 lists the rows
        // in: the note is written before anything is touched (§6.1 rule 1).
        var steps: [OperationStep] = [.saveUndoNote]
        if core.serviceID != nil {
            steps.append(.deleteForeignService(named: core.serviceName ?? ""))
        }
        if let bridgeName = core.bridgeName {
            steps.append(.joinBridge(named: bridgeName))
        }
        steps.append(.checkInBridge)

        return RestorePlan(
            kind: .returnToBridge,
            headline: LocalizedStringResource(core: core.headline),
            body: core.canProceed ? LocalizedStringResource(core: core.body) : nil,
            rows: core.canProceed ? core.rows.map { LocalizedStringResource(core: $0) } : [],
            primary: .returnToBridge,
            steps: steps,
            refusal: core.refusal,
            port: port,
            bridgeName: core.bridgeName,
            volumes: scoped.mountedVolumes)
    }

    // MARK: - An adopted port RDMALink should simply let go of

    private static func stopManaging(portID: String, hub: HubActionsModel) -> RestorePlan? {
        guard let port = hub.snapshot(id: portID) else { return nil }
        let core = StopManaging(port: OperationPort(port.port))
        return RestorePlan(
            kind: .stopManaging,
            headline: LocalizedStringResource(core: core.headline),
            body: LocalizedStringResource(core: core.body),
            primary: .stopManaging,
            port: port)
    }

    // MARK: - Every note there is

    private static func all(hub: HubActionsModel, world: ObservedWorld) -> RestorePlan? {
        // Every note RDMALink can actually put something back from. An adopted
        // note has no history to restore (§7.3) and a note left behind by a
        // return records nothing either, so neither is charged a password to
        // change nothing and then be deleted.
        let ports = hub.restorablePorts.filter {
            guard let baseline = $0.baseline else { return false }
            return !RestorePort.describesNothingToUndo(baseline)
        }
        guard !ports.isEmpty else { return nil }
        let scoped = scope(world, to: ports)
        let core = RestoreAll(ports: ports.map { OperationPort($0.port) })

        var steps: [OperationStep] = []
        for port in ports {
            guard let baseline = port.baseline else { continue }
            let plan = RestorePort(port: OperationPort(port.port))
                .preview(note: baseline, world: scope(world, to: [port]))
            if baseline.createdService != nil {
                steps.append(.deleteCreatedService(named: plan.serviceName ?? ""))
            }
            steps.append(contentsOf: plan.bridgesToRejoin.map { .rejoinBridge(named: $0) })
            steps.append(.checkBackInBridge)
        }

        return RestorePlan(
            kind: .all,
            headline: LocalizedStringResource(core: core.headline),
            body: LocalizedStringResource(core: core.body),
            rows: ports.map { LocalizedStringResource(core: $0.port.positionName) },
            primary: .restore,
            steps: steps,
            refusal: Refusals.nothingMountedOverThunderbolt(scoped.mountedVolumes),
            ports: ports,
            volumes: scoped.mountedVolumes)
    }

    // MARK: - Shared

    /// The world as the burst will re-read it: `perform` re-reads only the
    /// ports it is about, so a volume mounted over a *different* link must not
    /// refuse this one. Everything else is the reading the sheet opened with.
    private static func scope(_ world: ObservedWorld, to ports: [PortSnapshot]) -> ObservedWorld {
        let names = Set(ports.map(\.port.bsdName))
        var scoped = world
        scoped.mountedVolumes = world.mountedVolumes.filter { names.contains($0.portBSDName) }
        return scoped
    }
}
