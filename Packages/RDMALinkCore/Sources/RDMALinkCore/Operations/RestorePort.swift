import Foundation

/// How a moment is written in the copy that quotes one: "3 September at 14:21".
enum Moment {
    static func text(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        let day = date.formatted(.dateTime.locale(locale).day().month(.wide))
        let time = date.formatted(
            .dateTime.locale(locale).hour(.twoDigits(amPM: .omitted)).minute())
        return "\(day) at \(time)"
    }
}

/// What putting one port back would do — UX_SPEC §S10.
public struct RestorePortPlan: Sendable, Equatable {
    public var port: OperationPort
    public var headline: String
    public var body: String
    /// The four rows, in the spec's order.
    public var rows: [String]
    /// The notes under them, only the ones that apply.
    public var notes: [String]
    /// The service RDMALink made, as it is named right now.
    public var serviceName: String?
    /// Someone removed the service already. Only the membership is left.
    public var isServiceAlreadyGone: Bool
    /// The bridges the note recorded, as System Settings names them.
    public var bridgesToRejoin: [String]
    /// Bridges in the note that are not on this Mac any more — R21.
    public var missingBridges: [String]
    /// Set when the note is a return record (§7.5): Return to Bridge wrote it
    /// and the port already has everything it describes, so there is nothing
    /// here to put back. `Set It Up Again` and `Forget This Port` are the
    /// actions that apply, and ``refusal`` is set as well.
    public var returnedToBridge: BridgeReturn?
    public var refusal: Refusal?

    /// True when the whole restore can run.
    public var canProceed: Bool { refusal == nil }
    /// R21's offer: RDMALink will still delete its own service.
    public var mayRemoveServiceOnly: Bool { refusal?.code == .originalBridgeGone }
    public var buttonTitle: String? { canProceed ? "Restore" : nil }
}

/// What one restore came out as.
public struct RestorePortResult: Sendable, Equatable {
    public var bsdName: String
    public var positionName: String
    /// The service was already gone when RDMALink looked.
    public var serviceWasAlreadyGone: Bool
    /// The bridges the port is back in.
    public var rejoinedBridges: [String]
    /// True once the kernel agreed and the note was deleted.
    public var noteWasDeleted: Bool
    public var agreement: KernelAgreement
    public var elapsed: TimeInterval

    public var completionLine: String { OperationTiming.completionLine(seconds: elapsed) }
    /// UX_SPEC §S10's success headline.
    public var successHeadline: String { "Everything is back" }

    /// §S10's success body, when there is a bridge to name.
    ///
    /// A port RDMALink set up while it was **already** standalone has no
    /// bridge to go back into, and §S10 writes no success body for that shape:
    /// "is a member of \(bridgeName) again" would be a claim about a bridge the
    /// port never left. The nearest sentence the spec does write for exactly
    /// this outcome — the service gone, the port standalone — is R21's
    /// confirmation, and it is used without its note clause, which does not
    /// apply once the note has been forgotten.
    /// **Owed from the spec owner:** the no-bridge success body.
    public func successBody(bridgeName: String) -> String {
        guard !rejoinedBridges.isEmpty, !bridgeName.isEmpty else {
            return """
                The service is gone and the port is standalone. Nothing else on \
                this Mac was touched.
                """
        }
        return """
            \(positionName) is a member of \(bridgeName) again, and RDMALink has \
            forgotten it. Nothing else on this Mac was touched.
            """
    }
}

/// Puts one port back exactly as it was found, verifies it landed, and only
/// then forgets the baseline (UX_SPEC §7.2).
public struct RestorePort: Sendable {
    /// Which of the two things the user asked for.
    public enum Mode: Sendable, Equatable {
        /// Delete the service and put the port back in every bridge.
        case full
        /// R21's offer, when the bridge it came from is gone: delete only the
        /// service RDMALink made, and **keep** the note.
        case serviceOnly
    }

    /// The spec's fixed lines.
    public static let identifierNote = """
        RDMALink matches the service by its identifier, not its name, so it \
        only ever deletes the one it made — even if it's been renamed since.
        """
    public static let rdmaNote = """
        Your RDMA system setting isn't RDMALink's to touch, so it stays exactly \
        as it is.
        """
    public static let twoBridgesNote =
        "The port goes back into both bridges it belonged to, including the unused one."
    public static let serviceAlreadyGone = """
        The service RDMALink made isn't there any more — someone removed it \
        already. It'll just get the bridge membership back.
        """
    public static let serviceOnlyConfirmation = """
        The service is gone and the port is standalone. RDMALink has kept your \
        note, in case you rebuild that bridge and want the rest put back.
        """

    public let port: OperationPort
    public let mode: Mode

    public init(port: OperationPort, mode: Mode = .full) {
        self.port = port
        self.mode = mode
    }

    // MARK: - Preview

    /// What would happen. Pure.
    ///
    /// - Parameter note: the undo note, or `nil` when there isn't one — which
    ///   is R19, and RDMALink will not guess at network settings it never
    ///   wrote down.
    public func preview(note: PortBaseline?, world: ObservedWorld) -> RestorePortPlan {
        var plan = RestorePortPlan(
            port: port,
            headline: "Put \(port.positionName) the way it was?",
            body: "",
            rows: [],
            notes: [],
            serviceName: nil,
            isServiceAlreadyGone: true,
            bridgesToRejoin: [],
            missingBridges: [],
            returnedToBridge: nil,
            refusal: nil)

        guard let note else {
            plan.refusal = Refusals.undoNoteMissing(port: port.observed)
            return plan
        }
        // A return record is not one `Restore…` lists (§7.5 step 5): the port
        // is in the bridge the note names and has nothing of RDMALink's on it.
        // The plan says which record it is, and §6.2 R30 says so in words —
        // R19 would claim the note is missing, and it is sitting right there.
        if let returnedToBridge = note.returnedToBridge {
            plan.returnedToBridge = returnedToBridge
            plan.refusal = Refusals.noteIsAReturnRecord(
                port: port.observed, bridgeName: returnedToBridge.name)
            return plan
        }
        // An adopted note is the other record with nothing to put back (§7.3
        // — "there's no 'put it back' for an adopted port"): no bridge history
        // RDMALink witnessed, no service it made. Restoring it would take a
        // password, change nothing, and then print "Everything is back" and
        // delete the only record there was. §6.2 R30's adopted form says so —
        // R19 would claim the note is missing, and it is sitting right there.
        if note.isAdopted {
            plan.refusal = Refusals.noteIsAnAdoptionRecord(port: port.observed)
            return plan
        }
        // What is left with nothing in it is a note that records no bridge
        // history and no service RDMALink made, which no operation writes:
        // R19's "won't guess at your network settings" is the nearest the
        // spec has for it, and its row clears only RDMALink's own record.
        guard !Self.describesNothingToUndo(note) else {
            plan.refusal = Refusals.undoNoteMissing(port: port.observed)
            return plan
        }

        let bridgeNames = note.bridges.map { $0.displayName ?? $0.bridgeName }
        let live = Set(world.bridges.map(\.bsdName) + world.snapshot.bridgeNames)
        plan.bridgesToRejoin = bridgeNames
        plan.missingBridges = note.bridges
            .filter { !live.contains($0.bridgeName) }
            .map { $0.displayName ?? $0.bridgeName }

        let removal = note.createdService.map {
            StandalonePortRemoval(port: port.observed, record: $0)
                .preview(services: world.services)
        }
        plan.serviceName = removal?.serviceName ?? note.createdService?.name
        plan.isServiceAlreadyGone = removal?.isAlreadyGone ?? true

        let named = bridgeNames.first ?? "Thunderbolt Bridge"
        plan.body = """
            RDMALink will delete the service it made and return the port to \
            \(named) — exactly as it was on \(Moment.text(note.recordedAt)).
            """
        plan.rows = [
            "Delete the service \(plan.serviceName ?? note.positionName)",
            "Add the port back to \(named)",
            "Check that it really is back, then forget the whole thing",
            "Leave every other setting alone",
        ]
        plan.notes = [Self.identifierNote, Self.rdmaNote]
        if note.bridges.count > 1 { plan.notes.append(Self.twoBridgesNote) }
        if plan.isServiceAlreadyGone { plan.notes.append(Self.serviceAlreadyGone) }

        // In the order the spec raises them: a mounted volume means Restore is
        // not offered at all, a service somebody has taken over is not
        // RDMALink's to delete, and a bridge that has gone gets R21's offer.
        if let refusal = Refusals.nothingMountedOverThunderbolt(world.mountedVolumes) {
            plan.refusal = refusal
        } else if let refusal = removal?.refusal {
            plan.refusal = refusal
        } else if let missing = plan.missingBridges.first {
            plan.refusal = Refusals.originalBridgeGone(port: port.observed, bridgeName: missing)
        }
        return plan
    }

    /// True when the note has nothing in it that a restore could put back.
    ///
    /// The same question §7.3 answers for an adopted port and §7.5 leaves
    /// behind after a return: the app asks it before offering `Restore…`, and
    /// this asks it again before a credential is taken.
    public static func describesNothingToUndo(_ note: PortBaseline) -> Bool {
        note.isAdopted || note.isReturned || (note.bridges.isEmpty && note.createdService == nil)
    }

    // MARK: - Perform

    /// Deletes the service RDMALink made, puts the port back in every bridge
    /// the note records, **verifies membership from the kernel**, and only
    /// then deletes the note (UX_SPEC §7.2).
    @discardableResult
    public func perform(
        session: AuthorizedSession,
        environment: OperationEnvironment,
        progress: @escaping OperationProgress = { _, _ in }
    ) throws -> RestorePortResult {
        try perform(writer: LiveNetworkWriter(session: session, runner: environment.runner),
                    environment: environment, progress: progress)
    }

    @discardableResult
    func perform(
        writer: NetworkWriter,
        environment: OperationEnvironment,
        progress: OperationProgress
    ) throws -> RestorePortResult {
        try writer.lock()
        let world = try ObservedWorld.reread(
            ports: [port], writer: writer, archetype: environment.archetype,
            notesDirectory: environment.store.directory, runner: environment.runner)
        return try perform(writer: writer, world: world,
                           environment: environment, progress: progress)
    }

    /// Another writer holding the configuration is R12, and nothing was
    /// committed, so the note stays exactly where it is and the sheet says
    /// what is in the way rather than printing a raw error.
    private func commitOrBusy(_ writer: NetworkWriter) throws {
        do {
            try writer.commitAndApply()
        } catch let error as NetworkConfigurationError {
            if case .busy = error { throw Refusals.networkIsBusy(port: port.observed) }
            throw error
        }
    }

    /// The burst itself, against a world that has already been read.
    @discardableResult
    func perform(
        writer: NetworkWriter,
        world: ObservedWorld,
        environment: OperationEnvironment,
        progress: OperationProgress
    ) throws -> RestorePortResult {
        let clock = ContinuousClock()
        let started = clock.now
        try writer.lock()
        // §6.2 R19 covers "missing **or unreadable**", and nothing else: a
        // failure that is neither is not turned into a refusal whose button
        // row would delete a note that is sitting there intact.
        let note: PortBaseline
        do {
            note = try environment.store.load(port: port.bsdName)
        } catch let error as BaselineStoreError {
            switch error {
            case .missing, .unreadable, .malformed, .unsupportedVersion, .invalidPortName:
                throw Refusals.undoNoteMissing(port: port.observed)
            case .cannotWrite:
                throw error
            }
        }
        let plan = preview(note: note, world: world)
        // R21 is not a refusal when the user has taken its offer.
        if let refusal = plan.refusal, !(mode == .serviceOnly && plan.mayRemoveServiceOnly) {
            throw refusal
        }

        // The service RDMALink made, by identifier, and only while it is still
        // on this port. Already gone counts as done.
        var wasAlreadyGone = true
        if let created = note.createdService {
            // The live name, exactly as the preview's row printed it: a service
            // that has been renamed since must not read one way in the plan and
            // another way in the checklist.
            let step = OperationStep.deleteCreatedService(named: plan.serviceName ?? "")
            progress(step, .running)
            let deleted = try writer.deleteService(
                identifier: created.identifier, expectedInterface: created.interfaceBSDName)
            wasAlreadyGone = !deleted
            if deleted, mode == .full, !note.bridges.isEmpty {
                // The deletion goes in a commit of its own and the port is
                // given time to go quiet: written into the same apply, the
                // membership lands while IPv6 is still being torn down and the
                // kernel refuses it (see `BridgeRejoin`).
                try commitOrBusy(writer)
                if !writer.isDryRun {
                    _ = try KernelVerification.waitUntilQuiet(
                        port.bsdName, writer: writer, policy: environment.policy)
                }
            }
            progress(step, .done)
        }

        var rejoined: [String] = []
        var rewroteAtAddTime = false
        if mode == .full {
            for bridge in note.bridges {
                let named = bridge.displayName ?? bridge.bridgeName
                let step = OperationStep.rejoinBridge(named: named)
                progress(step, .running)
                if try BridgeRejoin.add(port.bsdName, to: bridge,
                                        at: bridge.members.firstIndex(of: port.bsdName),
                                        writer: writer, policy: environment.policy) {
                    rewroteAtAddTime = true
                }
                rejoined.append(named)
                progress(step, .done)
            }
        }
        try commitOrBusy(writer)

        // Never an assumption: an explicit, visible step.
        progress(.checkBackInBridge, .running)
        var agreement = KernelAgreement(agreed: true, settledOnItsOwn: true,
                                        retriedMembership: false, settledAfterRetry: false,
                                        reads: 0)
        if mode == .full, !writer.isDryRun, !note.bridges.isEmpty {
            // Both sources: the port is back when the kernel is bridging it
            // **and** the preferences list it again, which is the state it
            // was found in.
            agreement = try KernelVerification.wait(
                writer: writer, policy: environment.policy,
                retry: {
                    for bridge in note.bridges {
                        try BridgeRejoin.toggle(port.bsdName, in: bridge,
                                                at: bridge.members.firstIndex(of: port.bsdName),
                                                writer: writer, policy: environment.policy)
                    }
                    try writer.commitAndApply()
                }) { reading in
                    reading.isMember(port.bsdName, ofAll: note.bridges.map(\.bridgeName))
                }
                .foldingRewrite(atAddTime: rewroteAtAddTime)
            guard agreement.agreed else {
                // The note is **never** deleted until verification passes, so
                // there is always something to try again with (R20).
                throw Refusals.notBackInBridge(
                    port: port.observed,
                    bridgeName: note.bridges.first.map { $0.displayName ?? $0.bridgeName }
                        ?? "Thunderbolt Bridge",
                    removedService: true)
            }
        } else {
            agreement = agreement.foldingRewrite(atAddTime: rewroteAtAddTime)
        }
        progress(.checkBackInBridge, .done)

        var deletedNote = false
        if mode == .full, !writer.isDryRun {
            try environment.store.delete(port: port.bsdName)
            deletedNote = true
            try? environment.log.append(ChangeEntry(
                port: port.bsdName, positionName: port.positionName, kind: .restored,
                sentence: ChangeSentence.alreadyPutBack(moment: Moment.text(Date()))))
        }

        let elapsed = clock.now - started
        return RestorePortResult(
            bsdName: port.bsdName,
            positionName: port.positionName,
            serviceWasAlreadyGone: wasAlreadyGone,
            rejoinedBridges: rejoined,
            noteWasDeleted: deletedNote,
            agreement: agreement,
            elapsed: Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18)
    }
}

/// Every port with a note, one after the other, from one password.
///
/// Sequential on purpose, and it stops at the first thing that looks wrong:
/// the summary never rounds up (UX_SPEC §S10).
public struct RestoreAll: Sendable {
    public let ports: [OperationPort]

    public init(ports: [OperationPort]) { self.ports = ports }

    public var headline: String { "Put every port back?" }

    /// §S10 writes this sentence for **two** ports — "their services", "covers
    /// both" — and the sheet is reachable with one port (an adopted note is
    /// filtered out) and with three. The two-port sentence is the spec's,
    /// verbatim; the other counts keep its shape with the agreement corrected,
    /// because printing "covers both" over one port is the plain falsehood
    /// §1.3 rule 10 forbids.
    /// **Owed from the spec owner:** the one-port and three-or-more wordings.
    public var body: String {
        let subject = Self.count(ports.count, capitalized: true)
        if ports.count == 2 {
            return """
                \(subject) will return to Thunderbolt Bridge and their services \
                will be deleted. One password covers both. RDMALink does them one \
                at a time and stops at the first thing that looks wrong.
                """
        }
        if ports.count == 1 {
            return """
                \(subject) will return to Thunderbolt Bridge and its service will \
                be deleted. One password covers it. RDMALink does them one at a \
                time and stops at the first thing that looks wrong.
                """
        }
        return """
            \(subject) will return to Thunderbolt Bridge and their services will \
            be deleted. One password covers all of them. RDMALink does them one \
            at a time and stops at the first thing that looks wrong.
            """
    }

    /// "One port is back. Back, far right didn't finish — its undo note has
    /// been kept, so you can try that one again."
    public static func partialSummary(done: [String], unfinished: [String]) -> String? {
        guard !unfinished.isEmpty else { return nil }
        return """
            \(count(done.count, capitalized: true)) \(done.count == 1 ? "is" : "are") back. \
            \(englishList(unfinished)) didn't finish — its undo note has been kept, \
            so you can try that one again.
            """
    }

    /// "One port", "Two ports" — the spec writes small counts as words.
    ///
    /// Spelled out through `NumberFormatter` rather than an English table, so
    /// the sentence still reads in the languages §8.9 asks for. The plural of
    /// "port" is still English, and is one of the strings localization owes.
    static func count(_ value: Int, capitalized: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        let words = formatter.string(from: NSNumber(value: value)) ?? String(value)
        let word = capitalized ? words.prefix(1).uppercased() + words.dropFirst() : words
        return "\(word) port\(value == 1 ? "" : "s")"
    }

    /// The port the run stopped on.
    ///
    /// An error that is **not** one of the spec's refusals keeps its own text
    /// rather than borrowing a number: relabelling a lock conflict or an
    /// unreadable bridge as R19 hands the user a `Stop Managing This Port`
    /// button that deletes a note that was never the problem.
    public struct Unfinished: Sendable {
        public var port: String
        /// The refusal, when the failure had a number.
        public var refusal: Refusal?
        /// §6.1's shared shape otherwise: "Nothing has been changed." plus
        /// `Copy Details`.
        public var details: String?

        public init(port: String, refusal: Refusal? = nil, details: String? = nil) {
            self.port = port
            self.refusal = refusal
            self.details = details
        }
    }

    public struct Outcome: Sendable {
        public var results: [RestorePortResult]
        public var unfinished: [Unfinished]
        /// Ports whose note records nothing to put back — a return record
        /// (§7.5) or an adopted note (§7.3) — passed over without a write and
        /// without a password, and never counted as "back".
        public var skipped: [String]
        public var summary: String?
    }

    /// Runs them in order and stops at the first failure.
    public func perform(
        session: AuthorizedSession,
        environment: OperationEnvironment,
        progress: @escaping OperationProgress = { _, _ in }
    ) -> Outcome {
        perform(writer: LiveNetworkWriter(session: session, runner: environment.runner),
                environment: environment, progress: progress)
    }

    /// The same run, over the seam the tests drive.
    func perform(
        writer: NetworkWriter,
        environment: OperationEnvironment,
        progress: OperationProgress
    ) -> Outcome {
        var results: [RestorePortResult] = []
        var unfinished: [Unfinished] = []
        var skipped: [String] = []
        for port in ports {
            // A note with nothing to undo is passed over, not restored: a
            // return record already describes the port as it is, and charging
            // a password to change nothing and then delete the record would
            // be the rounding-up §S10 forbids.
            if let note = try? environment.store.load(port: port.bsdName),
                RestorePort.describesNothingToUndo(note) {
                skipped.append(port.positionName)
                continue
            }
            do {
                results.append(try RestorePort(port: port).perform(
                    writer: writer, environment: environment, progress: progress))
            } catch let refusal as Refusal {
                unfinished.append(Unfinished(port: port.positionName, refusal: refusal))
                break
            } catch let error as NetworkConfigurationError {
                // The one unnumbered error the spec does have a number for.
                if case .busy = error {
                    unfinished.append(Unfinished(
                        port: port.positionName,
                        refusal: Refusals.networkIsBusy(port: port.observed)))
                } else {
                    unfinished.append(Unfinished(port: port.positionName,
                                                 details: "\(error)"))
                }
                break
            } catch {
                unfinished.append(Unfinished(port: port.positionName, details: "\(error)"))
                break
            }
        }
        return Outcome(
            results: results,
            unfinished: unfinished,
            skipped: skipped,
            summary: Self.partialSummary(done: results.map(\.positionName),
                                         unfinished: unfinished.map(\.port)))
    }
}
