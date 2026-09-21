//
//  HubActionsModel.swift
//
//  The one object the hub's actions go through: which sheet is up, which
//  checklist is running, which notes exist, and what the change log says
//  (UX_SPEC §S1, §S9, §S10, §S11, §2.8).
//
//  It never opens an authorized session of its own. Every write to the system
//  lives in RDMALinkCore's operation types, which take the password burst with
//  them; what is left here is routing, RDMALink's own notes, and its own log.
//

import Foundation
import Observation
import RDMALinkCore

@MainActor
@Observable
final class HubActionsModel {

    /// Mirrored from `InventoryModel` by the window, so an action raised in a
    /// row, a menu or the change log all resolve against the same reading.
    var ports: [PortSnapshot] = []

    /// Which of §2.6's sheets is up.
    var sheet: HubSheet?

    /// §S11 replaces the working area rather than opening a sheet.
    var showsChangeLog = false

    /// What the footer offers, mirrored from `InventoryModel` by the window.
    /// The Port menu reads the same value, so a menu item and a button are
    /// never available on different terms.
    var footer = HubFooterModel(
        primary: nil,
        primaryTitle: "Set Up a Port…",
        isPrimaryEnabled: false,
        disabledReason: nil,
        offersRestore: true
    )

    /// The set-up flow's inbox (S4–S7). Written here, taken by the flow.
    var pendingSetUp: SetUpRequest?

    /// The live checklist, while an operation is running or has just ended.
    private(set) var run: OperationRun?

    /// The change log, newest first, and the notes that still exist.
    private(set) var log: [ChangeEntry] = []
    /// Every note on disk, by interface name — including notes for ports that
    /// are not on this Mac any more.
    private(set) var noted: Set<String> = []
    /// The notes `Restore…` can list: every note that is not a return record.
    /// A return record describes a port that already has everything it says
    /// (§7.5 step 5), so it is never listed, counted or offered. A note that
    /// cannot be read stays here, so R19 can say so.
    private(set) var restorable: Set<String> = []

    /// What this Mac is, mirrored from `InventoryModel`, so a sheet can
    /// re-read the world without reaching back into the window — and so the
    /// hub knows whether it is in R31's read-only mode.
    var hardware: HardwareModel?

    /// UX_SPEC §6.2 R31: neither rule in §4.7 recognizes this Mac. Nothing
    /// that writes is offered anywhere — set-up, Restore, Adopt, Return to
    /// Bridge, Stop Managing, Forget, notes included — and Identify is not
    /// offered either, because there is no model for it to point at. The
    /// buttons are absent, not disabled; Core refuses too, so the hiding is
    /// not the only guard.
    var isUnrecognized: Bool { hardware?.isRecognized == false }

    /// What a sheet is reading right now: the kernel's bridge membership, the
    /// services, the volumes mounted over these links, and whether a note can
    /// be saved. Read once when a sheet opens and never read again while it is
    /// up, exactly as `ObservedWorld` is meant to be used.
    ///
    /// **Read-only.** `ObservedWorld.read` takes no credential, no lock and
    /// writes nothing.
    private(set) var world: ObservedWorld?
    /// Why the read refused, when it did. A sheet that cannot see the world
    /// says so rather than offering a button over a guess.
    private(set) var worldFailure: String?

    private var stage: StageModel?
    /// The receptacle the running operation is about, for §S10's ring.
    private var runPortID: String?
    private var identifyBreath: Task<Void, Never>?
    private var closeAfterConfirmation: Task<Void, Never>?

    private let store = NotesLocation.store
    private let changeLog = NotesLocation.changeLog

    init() {}

    /// The window hands over the stage once; `Show Me` and `Identify a Port…`
    /// are camera moves and nothing else.
    func attach(stage: StageModel) {
        self.stage = stage
    }

    // MARK: - Lookups

    func snapshot(id: String) -> PortSnapshot? {
        ports.first { $0.id == id }
    }

    func snapshot(bsdName: String) -> PortSnapshot? {
        ports.first { $0.port.bsdName == bsdName }
    }

    /// The undo note for a port, as this reading found it.
    func baseline(id: String) -> PortBaseline? {
        snapshot(id: id)?.baseline
    }

    /// §2.8: "Whenever any baseline exists, the footer of the hub carries
    /// `Restore…`" — any baseline `Restore…` can put something back from,
    /// which a return record is not (§7.5 step 5). A note for a port that is
    /// not on this Mac any more still counts, which is why the store's own
    /// list is consulted and not only the live ports.
    var hasRestorableNote: Bool {
        !restorable.isEmpty || !restorablePorts.isEmpty
    }

    /// Every port with a note `Restore…` can act on, in physical order.
    var restorablePorts: [PortSnapshot] {
        ports.filter { $0.baseline.map(Self.isRestorable) == true }
    }

    /// §7.5 step 5: "A returned note is not one `Restore…` lists."
    private static func isRestorable(_ note: PortBaseline) -> Bool {
        !note.isReturned
    }

    /// §2.8: "Restore is never hidden." The footer's and the Port menu's
    /// `Restore…` mean the port in hand when there is one, the only noted port
    /// when there is only one, and §S10's Restore All when there is neither —
    /// the sheet that can name them all.
    var restoreAction: HubAction {
        if let selected = selectedPort, selected.baseline.map(Self.isRestorable) == true {
            return .restore(portID: selected.id)
        }
        let ports = restorablePorts
        if ports.count == 1, let only = ports.first { return .restore(portID: only.id) }
        return .restoreAll
    }

    /// The port the stage and the list agree is selected (§2.4). The Port menu
    /// acts on it, and its items are unavailable rather than missing when
    /// there isn't one.
    var selectedPort: PortSnapshot? {
        guard let id = stage?.selectedID else { return nil }
        return snapshot(id: id)
    }

    /// Whether an action has anything to act on. One answer for the row
    /// buttons, the footer and the Port menu (§2.7: the menu is the same shape
    /// on every machine, and unavailable rather than missing).
    func canPerform(_ action: HubAction) -> Bool {
        // R31 first, as Core asks it first: the change log is the one thing
        // §6.2 R31 leaves working, and it only reads.
        if isUnrecognized { return action == .changeLog }
        switch action {
        case .setUpAPort, .setItUpAgain:
            return footer.primary != nil && footer.isPrimaryEnabled
        case .identifyAPort(let portID):
            let port = portID.flatMap(snapshot(id:)) ?? selectedPort
            return port?.port.isThunderbolt == true
        case .adopt(let portID):
            // The same question §S9's sheet asks: a full match to adopt, or a
            // near match to explain. Anything else is never offered one.
            guard let port = snapshot(id: portID) else { return false }
            return AdoptForm(port) != nil
        case .restore(let portID):
            return snapshot(id: portID)?.baseline.map(Self.isRestorable) == true
        case .returnToBridge(let portID):
            guard let port = snapshot(id: portID) else { return false }
            // §S1's one exception, and the row gives the same answer: a port
            // RDMALink set up is offered `Restore…` and nothing else. Return
            // to Bridge writes a fresh note, and a fresh note over that port's
            // would destroy the only record of the bridges it really came from
            // — after which there is no way back at all. **Owed from the spec
            // owner:** §S1 says any port out of the bridge carries `Return to
            // Bridge…`; for a port RDMALink set up that cannot be true without
            // losing its history, so `Restore…` stands alone there.
            guard port.readiness != .managed else { return false }
            // And the same question Core asks before it writes: a note that
            // records a service RDMALink made is the history this action would
            // overwrite, whatever the port's live configuration has drifted to.
            if let baseline = port.baseline,
                !baseline.isAdopted, baseline.createdService != nil {
                return false
            }
            return port.isOutOfEveryBridge
        case .stopManaging(let portID):
            // §7.5 step 5: `Forget This Port` clears a return record. §S1
            // gives the returned row no button for it, so it is reached the
            // way an adopted port's is — the Port menu's `Stop Managing…`,
            // whose sheet says exactly what it does: forgets the note and
            // changes nothing. It is keyed on the note, not on what the port
            // is doing now: a return record whose port has since left the
            // bridge reads as no note in the row, and this is the one door
            // left through which it can be cleared.
            guard let note = snapshot(id: portID)?.baseline else { return false }
            return note.isAdopted || note.isReturned
        case .forgetThisPort(let portID):
            return snapshot(id: portID)?.baseline != nil
        case .showMe(let portID):
            return snapshot(id: portID) != nil
        case .restoreAll:
            return hasRestorableNote
        case .changeLog:
            return true
        case .forgetThisNote(let bsdName):
            return noted.contains(bsdName)
        }
    }

    /// §7.5: "with more than one bridge, the one named Thunderbolt Bridge
    /// wins; with none, the sheet stops and hands off to System Settings".
    ///
    /// The name is compared against the one System Settings gives a Thunderbolt
    /// Bridge, which is the name §7.5 names; any other bridge is only ever a
    /// fallback, never a second guess about which one the user meant.
    var bridgeToReturnTo: BridgeSPI.Membership? {
        let bridges = world?.bridges ?? []
        if let named = bridges.first(where: { $0.displayName == ReturnToBridge.preferredBridgeName }) {
            return named
        }
        // With two bridges and neither of them named, there is no answer
        // RDMALink is entitled to guess at — `ReturnToBridge` makes the same
        // call, and the sheet shows §7.5's hand-off instead.
        return bridges.count == 1 ? bridges[0] : nil
    }

    // MARK: - Raising an action

    func perform(_ action: HubAction) {
        // Every surface that raises an action is absent on an unrecognized
        // Mac; this is the one door they all go through, so it is shut too.
        guard !isUnrecognized || action == .changeLog else { return }
        switch action {
        case .setUpAPort(let portID):
            pendingSetUp = SetUpRequest(portID: portID ?? stage?.selectedID)
        case .setItUpAgain(let portID):
            pendingSetUp = SetUpRequest(portID: portID)
        case .identifyAPort(let portID):
            identify(portID ?? stage?.selectedID)
        case .adopt(let portID):
            open(.adopt(portID: portID))
        case .restore(let portID):
            open(.restore(.restore(portID: portID)))
        case .returnToBridge(let portID):
            open(.restore(.returnToBridge(portID: portID)))
        case .stopManaging(let portID):
            open(.restore(.stopManaging(portID: portID)))
        case .restoreAll:
            open(.restore(.all))
        case .showMe(let portID):
            showMe(portID)
        case .changeLog:
            openChangeLog()
        case .forgetThisPort(let portID):
            guard let port = snapshot(id: portID) else { return }
            forget(bsdName: port.port.bsdName, positionName: port.port.positionName)
        case .forgetThisNote(let bsdName):
            let positionName = log.first { $0.port == bsdName }?.positionName ?? bsdName
            forget(bsdName: bsdName, positionName: positionName)
        }
    }

    private func open(_ sheet: HubSheet) {
        run = nil
        closeAfterConfirmation?.cancel()
        if case .restore(let subject) = sheet {
            // §S9 and §S10: "the camera turns to the port and rings it" before
            // the sheet is up — nobody should act on a port they cannot see.
            if let portID = subject.portID { showMe(portID) }
        }
        if case .adopt(let portID) = sheet { showMe(portID) }
        // §4.4: the ribbon stays up for the whole of a restore, so the port's
        // way back into the bridge is on screen while it is described.
        stage?.ribbons = .all
        self.sheet = sheet
        Task { await readWorld() }
    }

    /// §S1's `Show Me`, and the beat §S9 and §S10 open with: select the port
    /// and turn the Mac to the face it is on.
    private func showMe(_ portID: String) {
        stage?.select(portID)
    }

    /// §2.7's `Identify a Port…`: the port is selected, the Mac turns to it,
    /// and the receptacle breathes once. It changes nothing.
    private func identify(_ portID: String?) {
        guard let portID, let stage else { return }
        stage.select(portID)
        stage.attention(ids: [portID])
        identifyBreath?.cancel()
        identifyBreath = Task { [weak stage] in
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            stage?.attention(ids: [])
        }
    }

    // MARK: - The change log (§S11)

    func openChangeLog() {
        showsChangeLog = true
    }

    func closeChangeLog() {
        showsChangeLog = false
    }

    /// The log and the notes, read off the main actor. Both are small files in
    /// Application Support and neither is a system read.
    func reloadLog() async {
        let log = changeLog
        let store = store
        let reading = await Task.detached(priority: .userInitiated) { () -> LogReading in
            LogReading(
                entries: ((try? log.entries()) ?? []).sorted { $0.date > $1.date },
                notes: NotesReading(store))
        }.value
        self.log = reading.entries
        self.noted = reading.notes.all
        self.restorable = reading.notes.restorable
    }

    /// Which notes exist, without reading the whole log.
    func refreshNotes() async {
        let store = store
        let notes = await Task.detached(priority: .utility) { NotesReading(store) }.value
        noted = notes.all
        restorable = notes.restorable
    }

    /// What the open sheet is looking at: bridges, services, mounted volumes
    /// and whether a note can be saved (R4 and R14 both live in here).
    ///
    /// Read-only, off the main actor, and re-read whenever a sheet opens —
    /// never cached across sheets, because the thing this is protecting
    /// against is acting on a world that moved.
    func readWorld() async {
        let operationPorts = ports.map { OperationPort($0.port) }
        guard !operationPorts.isEmpty, let hardware else { return }
        // R14 is measured against the folder the notes really go to.
        let notesDirectory = store.directory
        let result = await Task.detached(priority: .userInitiated) { () -> Result<ObservedWorld, any Error> in
            do {
                return .success(try ObservedWorld.read(
                    ports: operationPorts, hardware: hardware, notesDirectory: notesDirectory))
            } catch {
                return .failure(error)
            }
        }.value
        switch result {
        case .success(let world):
            self.world = world
            self.worldFailure = nil
        case .failure(let error):
            self.world = nil
            self.worldFailure = "\(error)"
        }
    }

    // MARK: - Forgetting a note

    /// §S1's `Forget This Port` and §S11's `Forget This Note`. It deletes
    /// RDMALink's own note and writes the log entry that says so. Nothing on
    /// the system is touched, and no password is asked for.
    private func forget(bsdName: String, positionName: String) {
        let store = store
        let log = changeLog
        Task {
            await Task.detached(priority: .userInitiated) {
                try? store.delete(port: bsdName)
                // §S11 has no sentence for a note cleared after drift. This is
                // the closest the spec gives — the stopped-looking-after line —
                // and a sentence of its own is **owed from the spec owner**.
                let entry = ChangeEntry(
                    port: bsdName,
                    positionName: positionName,
                    kind: .forgotten,
                    sentence: ChangeSentence.stoppedLookingAfter(
                        moment: Moments.dayAtTime(Date())
                    )
                )
                try? log.append(entry)
            }.value
            await refreshNotes()
            if showsChangeLog { await reloadLog() }
        }
    }

    // MARK: - Running an operation

    /// Puts the sheet into its checklist and runs `body`, which is one of
    /// RDMALinkCore's operation types.
    ///
    /// The rows advance from the operation's own progress, so what the user
    /// watches is what actually happened (§S6: "showing real progress"), and
    /// the words are the operation's own ``RDMALinkCore/OperationStep``s.
    func start(
        steps: [OperationStep],
        portID: String? = nil,
        _ body: @escaping @Sendable (@escaping @Sendable (OperationStep, StepState) -> Void)
            async throws -> OperationOutcome
    ) {
        runPortID = portID
        run = OperationRun(steps: steps)
        // §S10: the ring starts solid and re-opens a gap per completed step.
        if let portID, !steps.isEmpty {
            stage?.restoreProgress(step: 0, of: steps.count, for: portID)
        }
        Task {
            let outcome: OperationOutcome
            do {
                outcome = try await body { step, state in
                    Task { @MainActor in self.mark(step, state) }
                }
            } catch let refusal as Refusal {
                outcome = .refused(refusal)
            } catch {
                outcome = .failed(details: "\(error)")
            }
            finish(with: outcome)
        }
    }

    private func mark(_ step: OperationStep, _ state: StepState) {
        guard var run, run.isRunning else { return }
        run.mark(step, state)
        self.run = run
        guard let portID = runPortID, !run.steps.isEmpty else { return }
        stage?.restoreProgress(
            step: run.states.count(where: { $0 == .done }), of: run.steps.count, for: portID)
    }

    private func finish(with outcome: OperationOutcome) {
        guard var run else { return }
        if case .succeeded = outcome { run.finishAllSteps() }
        run.outcome = outcome
        self.run = run
        if let portID = runPortID {
            // §S10: on success the ring is handed back to the port's own state
            // once the re-read lands. On a refusal it is left exactly where it
            // stopped — half-open is what R20 says out loud.
            if case .succeeded = outcome { stage?.clearProgress(for: portID) }
        }
        Task {
            await refreshNotes()
            if showsChangeLog { await reloadLog() }
        }
    }

    /// §S9: "Adopted (the sheet closes and the hub row changes in place)". The
    /// confirmation is shown for a beat first, because a confirmation nobody
    /// sees is not one.
    func closeAfterConfirmation(_ dismiss: @escaping @MainActor () -> Void) {
        closeAfterConfirmation?.cancel()
        closeAfterConfirmation = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    /// §6.2 R12's `Check Again`: drop the answer the sheet is showing and look
    /// at this Mac again. It takes no credential and writes nothing.
    func recheck() {
        run = nil
        runPortID = nil
        Task { await readWorld() }
    }

    /// The sheet is gone; nothing from its run outlives it.
    ///
    /// One sheet can replace another — R19's `Stop Managing This Port` does
    /// exactly that — and the old one's `onDisappear` lands after the new one
    /// has asked for its own reading, so a dismissal that something else has
    /// already answered clears nothing.
    func sheetDismissed() {
        guard sheet == nil else { return }
        stage?.ribbons = .automatic
        if let portID = runPortID { stage?.clearProgress(for: portID) }
        runPortID = nil
        run = nil
        world = nil
        worldFailure = nil
        closeAfterConfirmation?.cancel()
        closeAfterConfirmation = nil
    }
}

/// One read of both files in Application Support.
private struct LogReading: Sendable {
    var entries: [ChangeEntry]
    var notes: NotesReading
}

/// One read of the notes folder: every note's name, and the names of those
/// `Restore…` can list. A note that will not load is kept in both, so that
/// `Restore…` can raise R19 about it rather than hide it.
private struct NotesReading: Sendable {
    var all: Set<String>
    var restorable: Set<String>

    init(_ store: BaselineStore) {
        let names = (try? store.list()) ?? []
        all = Set(names)
        restorable = Set(names.filter { (try? store.load(port: $0))?.isReturned != true })
    }
}
