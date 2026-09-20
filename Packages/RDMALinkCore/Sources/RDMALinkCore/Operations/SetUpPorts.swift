import Foundation

/// What every operation needs that is not the world and not the port: where
/// the notes live, how long the kernel is given, and which archetype this Mac
/// is so a re-read can name its ports.
public struct OperationEnvironment: Sendable {
    public var archetype: Archetype
    public var store: BaselineStore
    public var log: ChangeLog
    public var policy: KernelWaitPolicy
    public var runner: CommandRunner
    /// How much wall clock the whole burst may spend, measured from
    /// ``startedAt``.
    ///
    /// `AuthorizationCopyRights` hands back a non-shared credential that lasts
    /// about thirty seconds. Twenty leaves room for the commit that follows the
    /// last write and for a rollback after it, so the burst discovers it is out
    /// of time *before* `SCPreferencesCommitChanges` fails on a destroyed
    /// credential rather than after.
    public var burstBudget: Duration
    /// When the credential was taken — ``AuthorizedSession/begin(clientName:mode:)``
    /// returning. The default is "now", which is right for a burst that starts
    /// immediately after it, and that is the only kind the app runs (§S6).
    public var startedAt: ContinuousClock.Instant

    public init(
        archetype: Archetype,
        store: BaselineStore = BaselineStore(),
        log: ChangeLog = ChangeLog(),
        policy: KernelWaitPolicy = .standard,
        runner: CommandRunner = CommandRunner(),
        burstBudget: Duration = .seconds(20),
        startedAt: ContinuousClock.Instant = ContinuousClock().now
    ) {
        self.archetype = archetype
        self.store = store
        self.log = log
        self.policy = policy
        self.runner = runner
        self.burstBudget = burstBudget
        self.startedAt = startedAt
    }

    /// What is left of the burst's budget. Never negative.
    var remainingBudget: Duration {
        let spent = ContinuousClock().now - startedAt
        return spent >= burstBudget ? .zero : burstBudget - spent
    }
}

/// One row of UX_SPEC §S5's review, with its before → after pair of chips.
public struct ReviewRow: Sendable, Equatable {
    public var title: String
    public var body: String
    public var before: String
    public var after: String

    public init(title: String, body: String, before: String, after: String) {
        self.title = title
        self.body = body
        self.before = before
        self.after = after
    }
}

/// What setting up one port would change — one §S5 section.
public struct SetUpPortPlan: Sendable, Equatable {
    public var port: OperationPort
    /// The section header, e.g. "Back, far left".
    public var header: String
    /// The name the new service gets.
    public var serviceName: String
    /// Every kernel bridge the port has to leave, in the order found.
    public var bridgesToLeave: [String]
    /// The same bridges as System Settings names them.
    public var bridgeNames: [String]
    /// The four rows, in order.
    public var rows: [ReviewRow]
    /// Warning rows. Never blocking.
    public var warnings: [String]
    /// The `Show technical names` disclosure, one fact per line.
    public var technicalNames: [String]
    /// The refusal that replaces this section, when there is one.
    public var refusal: Refusal?
    /// The port is already configured, so the app offers Adopt and never
    /// set-up (UX_SPEC §S4, R27). Routing, not refusing.
    public var routesToAdopt: Bool

    public var canProceed: Bool { refusal == nil && !routesToAdopt }
}

/// The whole review screen.
public struct SetUpPortsPlan: Sendable, Equatable {
    public static let headline = "Here's what will change"
    public static let body =
        "Nothing has happened yet. Read this, then RDMALink will ask for a password once and make every change in one go."
    public static let footnote =
        "Your Wi-Fi, your Ethernet, and every other network service are untouched."
    public static let whatIWontTouchLabel = "What I Won't Touch"
    public static let whatIWontTouch = """
        Your other Thunderbolt ports. The Thunderbolt Bridge itself — RDMALink \
        never deletes or recreates a bridge, it only removes a member. Wi-Fi. \
        Ethernet. File sharing, the firewall, and everything else on this Mac. \
        The RDMA system setting, which is yours to switch.
        """

    public var ports: [SetUpPortPlan]
    /// A refusal about the whole Mac — R1, R4, R5, R14. It replaces the
    /// sections, and the default button is **removed**, never disabled.
    public var refusal: Refusal?

    /// Every refusal in the way, the whole-Mac one first.
    public var refusals: [Refusal] {
        (refusal.map { [$0] } ?? []) + ports.compactMap(\.refusal)
    }

    public var canProceed: Bool {
        refusal == nil && !ports.isEmpty && ports.allSatisfy(\.canProceed)
    }

    /// The default button, named for exactly what it will do. `nil` when there
    /// is nothing to press — §6.1 rule 6.
    public var defaultButtonTitle: String? {
        guard canProceed else { return nil }
        return ports.count == 1 ? "Set Up Port" : "Set Up \(ports.count) Ports"
    }
}

/// What one port came out of the burst as.
public struct SetUpPortResult: Sendable, Equatable {
    public var bsdName: String
    public var positionName: String
    public var serviceName: String
    /// The identifier of the service that was created, or `nil` in a dry run.
    public var createdServiceID: String?
    /// The bridges the port left, as System Settings names them.
    public var leftBridges: [String]
    /// What it took for the kernel to agree the port is out of every bridge.
    public var agreement: KernelAgreement
}

/// The port a multi-port burst stopped on, and why.
///
/// Its own changes were put back before this value existed; the ports before
/// it in ``SetUpPortsResult/ports`` were committed and verified and **stand**
/// (UX_SPEC §10 question 4, answered: per-port results, no rounding up).
public struct SetUpPortFailure: Sendable, Equatable {
    public var bsdName: String
    public var positionName: String
    /// R8, R9, R10 or R11 — about **this port**, never about the whole run.
    public var refusal: Refusal

    public init(bsdName: String, positionName: String, refusal: Refusal) {
        self.bsdName = bsdName
        self.positionName = positionName
        self.refusal = refusal
    }
}

/// The whole run.
public struct SetUpPortsResult: Sendable, Equatable {
    /// The ports that landed: committed, verified against the kernel, noted.
    public var ports: [SetUpPortResult]
    /// The port the burst stopped on, when it stopped on one. `nil` means
    /// every port asked for is in ``ports``.
    ///
    /// A run where **no** port landed never produces one of these: there is
    /// nothing to report per port, so the refusal is thrown as it always was.
    public var unfinished: SetUpPortFailure?
    /// How long the burst took, for "Done. That took 1.8 seconds."
    public var elapsed: TimeInterval
    public var wasDryRun: Bool

    public init(
        ports: [SetUpPortResult],
        unfinished: SetUpPortFailure? = nil,
        elapsed: TimeInterval,
        wasDryRun: Bool
    ) {
        self.ports = ports
        self.unfinished = unfinished
        self.elapsed = elapsed
        self.wasDryRun = wasDryRun
    }

    /// UX_SPEC §S6: the line under the last checkmark.
    public var completionLine: String { OperationTiming.completionLine(seconds: elapsed) }
}

/// Sets one or more Thunderbolt ports up for RDMA: out of every bridge, its
/// own service, IPv4 off and IPv6 link-local only.
///
/// One password, one burst. Every write happens inside the credential window
/// that opens when ``AuthorizedSession/begin(clientName:mode:)`` returns, and
/// nothing in here ever asks the user anything — there is no control the app
/// cannot honour once the burst has started (UX_SPEC §S6).
public struct SetUpPorts: Sendable {
    /// The ports to set up, in the order the user chose them.
    public let ports: [OperationPort]
    /// The plan the user actually read, when there was a review screen. The
    /// burst re-reads the world and compares: a cable that moved in between is
    /// R17, and nothing is written.
    public let reviewed: SetUpPortsPlan?

    public init(ports: [OperationPort], reviewed: SetUpPortsPlan? = nil) {
        self.ports = ports
        self.reviewed = reviewed
    }

    // MARK: - Preview

    /// What would change. Pure: it reads nothing and writes nothing.
    public func preview(world: ObservedWorld) -> SetUpPortsPlan {
        SetUpPortsPlan(ports: ports.map { plan(for: $0, world: world) },
                       refusal: wholeMacRefusal(world: world))
    }

    /// The refusals that are about this Mac rather than one port, in the order
    /// the spec raises them.
    func wholeMacRefusal(world: ObservedWorld) -> Refusal? {
        if let refusal = Refusals.oneCableOnly(world.context.observedPorts) { return refusal }
        if let refusal = Refusals.nothingMountedOverThunderbolt(world.mountedVolumes) {
            return refusal
        }
        if let refusal = Refusals.managementPathExists(
            in: world.snapshot,
            thunderboltPorts: world.context.thunderboltBSDNames,
            primaryInterfaces: world.context.primaryInterfaces) { return refusal }
        // R14 last of the four, and first of the writes: the gate that protects
        // every other promise comes before the password, not after.
        return world.notesAreWritable
    }

    func plan(for port: OperationPort, world: ObservedWorld) -> SetUpPortPlan {
        let bridges = world.bridges(containing: port.bsdName)
        let named = bridges.map(world.name(ofBridge:))
        let serviceName = StandalonePortSetup.serviceName(for: port.positionName)
        let onThePort = NetworkServices.services(for: port.bsdName, in: world.services)
        let existing = NetworkServices.classify(services: onThePort, bridges: bridges)

        var refusal: Refusal?
        var routesToAdopt = false
        // A bridge the configuration cannot see is a bridge RDMALink cannot
        // take the port out of, and it won't guess at one.
        refusal = Refusals.everyBridgeIsReadable(
            port.observed, kernelBridges: bridges,
            configuredBridges: world.bridges.map(\.bsdName))
        if refusal == nil {
            switch existing {
            case let .foreign(_, reason):
                refusal = Refusals.foreignService(port.observed, reason: reason)
            case .readyForRDMA, .nearMatch:
                routesToAdopt = true
            case .unconfigured:
                break
            }
        }

        return SetUpPortPlan(
            port: port,
            header: port.positionName,
            serviceName: serviceName,
            bridgesToLeave: bridges,
            bridgeNames: named,
            rows: Self.rows(serviceName: serviceName, bridgeNames: named),
            warnings: Self.warnings(port: port, rdma: world.rdma),
            technicalNames: Self.technicalNames(
                port: port, serviceName: serviceName, bridges: bridges,
                world: world),
            refusal: refusal,
            routesToAdopt: routesToAdopt)
    }

    /// UX_SPEC §S5's four rows, verbatim.
    static func rows(serviceName: String, bridgeNames: [String]) -> [ReviewRow] {
        [
            ReviewRow(
                title: "Save how to undo this",
                body: """
                Before anything else, RDMALink writes down exactly how this \
                port looks today. If it can't write that note, it won't change \
                a thing.
                """,
                before: "Nothing saved", after: "Saved"),
            bridgeRow(bridgeNames),
            ReviewRow(
                title: "Get its own network service",
                body: "A new service called \(serviceName). Nothing else on this Mac uses it.",
                before: "Doesn't exist", after: "Created"),
            ReviewRow(
                title: "Turn IPv4 off, IPv6 to link-local",
                body: "That's all RDMA needs, and it keeps this port off your ordinary network.",
                // The spec writes this chip as a literal rather than as the
                // port's own configuration: a port with no service of its own
                // has no IPv4 or IPv6 setting to read back.
                before: "IPv4 automatic, IPv6 automatic",
                after: "IPv4 off, IPv6 link-local only"),
        ]
    }

    /// Row 2, which has three forms: one bridge, two, or none.
    static func bridgeRow(_ names: [String]) -> ReviewRow {
        let title = "Leave the Thunderbolt Bridge"
        guard let first = names.first else {
            return ReviewRow(
                title: title,
                body: "This port isn't in any bridge, so there's nothing to remove.",
                before: "Standalone", after: "Standalone")
        }
        var body = """
            This port is a member of \(first). RDMALink removes just this port. \
            The bridge itself stays exactly as it is, with its other ports.
            """
        if names.count > 1 {
            body += " " + """
                It's also in an unused bridge, \(names[1]). RDMALink removes it \
                from that one too — a port has to be out of every bridge, even \
                one that isn't being used.
                """
        }
        return ReviewRow(title: title, body: body,
                         before: names.count > 1 ? "In two bridges" : "In the bridge",
                         after: "Standalone")
    }

    /// The warning rows. Never blocking — they say what will still be true
    /// afterwards, which is not the same as something being in the way.
    static func warnings(port: OperationPort, rdma: RDMAStatus) -> [String] {
        var found: [String] = []
        if rdma == .off || rdma == .unknown {
            found.append("""
                RDMA over Thunderbolt is still off. The port will be ready; \
                RDMA will start using it after you turn that on and restart.
                """)
        }
        switch port.link {
        case .empty:
            found.append("Nothing is plugged into this port yet. It'll be ready and waiting.")
        case .device:
            found.append("""
                There's a dock or a display in this port. It'll keep working \
                exactly as it does now — RDMA will use the port once a Mac is \
                on the other end.
                """)
        case .macLinked, .macLinkComingUp:
            break
        }
        return found
    }

    /// The `Show technical names` disclosure, one fact per line.
    static func technicalNames(
        port: OperationPort,
        serviceName: String,
        bridges: [String],
        world: ObservedWorld
    ) -> [String] {
        var lines = ["Interface \(port.bsdName)", "New service \(serviceName)"]
        for (index, bridge) in bridges.enumerated() {
            let before = world.snapshot[bridge]?.members ?? []
            let after = before.filter { $0 != port.bsdName }
            lines.append("\(index == 0 ? "Removing" : "Also removing") from \(bridge): "
                + "members \(before.joined(separator: ", ")) → \(after.joined(separator: ", "))")
        }
        lines.append("IPv4 configuration: Off")
        lines.append("IPv6 configuration: Link-local only")
        lines.append("""
            RDMALink records the service it creates by its identifier, not its \
            name, so renaming it later doesn't confuse anything.
            """)
        return lines
    }

    // MARK: - Perform

    /// Does every write, in one burst, right after the password.
    ///
    /// Order, and it is the whole point of the type: re-read the world, refuse
    /// if anything is in the way, take the lock, **write the undo note**, then
    /// per port take it out of every bridge, create its service, commit, apply
    /// and read the kernel back. Anything that fails after the first write is
    /// undone in reverse order before the user is told anything (R10); a
    /// rollback that cannot finish is R11, and the note is kept either way.
    ///
    /// The session is the caller's to ``AuthorizedSession/end()``.
    @discardableResult
    public func perform(
        session: AuthorizedSession,
        environment: OperationEnvironment,
        progress: @escaping OperationProgress = { _, _ in }
    ) throws -> SetUpPortsResult {
        try perform(
            writer: LiveNetworkWriter(session: session, runner: environment.runner),
            environment: environment, progress: progress)
    }

    /// The same burst, over the seam the tests drive.
    ///
    /// Two writers editing the network at once is how configurations get
    /// mangled, so the lock comes before the read the writes rest on — and
    /// again inside, where it is a no-op, so the seam holds the invariant on
    /// its own.
    @discardableResult
    func perform(
        writer: NetworkWriter,
        environment: OperationEnvironment,
        progress: OperationProgress
    ) throws -> SetUpPortsResult {
        try writer.lock()
        let world = try ObservedWorld.reread(
            ports: ports, writer: writer, archetype: environment.archetype,
            notesDirectory: environment.store.directory, runner: environment.runner)
        return try perform(writer: writer, world: world,
                           environment: environment, progress: progress)
    }

    /// The burst itself, against a world that has already been read.
    @discardableResult
    func perform(
        writer: NetworkWriter,
        world: ObservedWorld,
        environment: OperationEnvironment,
        progress: OperationProgress
    ) throws -> SetUpPortsResult {
        let clock = ContinuousClock()
        let started = clock.now
        try writer.lock()
        let plan = preview(world: world)
        if let refusal = plan.refusal { throw refusal }
        if let refusal = plan.ports.compactMap(\.refusal).first { throw refusal }
        if let changed = Self.whatMoved(from: reviewed, to: plan) {
            throw Refusals.topologyChanged(subjects: plan.ports.map(\.port.bsdName),
                                           detail: changed)
        }
        guard plan.canProceed else {
            // Every reason has its own refusal above; a port that routes to
            // Adopt is the one case left, and no screen offers a button to it.
            throw NetworkConfigurationError.missing("a port that can be set up")
        }

        var results: [SetUpPortResult] = []
        var unfinished: SetUpPortFailure?
        for portPlan in plan.ports {
            // A later port's failure rolls back **only that port**: the ports
            // before it were committed and read back from the kernel, and
            // undoing work that landed to report a failure that did not would
            // be the half-done state R10 promises there isn't.
            if !results.isEmpty, !writer.isDryRun,
                environment.remainingBudget <= environment.policy.budget {
                // Not enough of the credential left to write this port and
                // verify it, and discovering that at `commit` is how a port
                // ends up in neither place (R11). Nothing was written for it.
                unfinished = SetUpPortFailure(
                    bsdName: portPlan.port.bsdName,
                    positionName: portPlan.port.positionName,
                    refusal: Refusals.credentialExpired(port: portPlan.port.observed))
                break
            }
            do {
                results.append(try setUp(portPlan, writer: writer, world: world,
                                         environment: environment, progress: progress))
            } catch let refusal as Refusal {
                // Nothing landed at all: there is no per-port story to tell, so
                // the refusal is the whole answer and is thrown as it always was.
                guard !results.isEmpty else { throw refusal }
                unfinished = SetUpPortFailure(
                    bsdName: portPlan.port.bsdName,
                    positionName: portPlan.port.positionName,
                    refusal: refusal)
                break
            }
        }

        let elapsed = clock.now - started
        return SetUpPortsResult(
            ports: results,
            unfinished: unfinished,
            elapsed: Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18,
            wasDryRun: writer.isDryRun)
    }

    /// What the review screen's promise actually rests on, so R17 fires on a
    /// change that matters and stays quiet about one that does not.
    static func whatMoved(from reviewed: SetUpPortsPlan?, to now: SetUpPortsPlan) -> String? {
        guard let reviewed else { return nil }
        let before = fingerprint(reviewed)
        let after = fingerprint(now)
        guard before != after else { return nil }
        return "Then: \(before.joined(separator: " · ")). Now: \(after.joined(separator: " · "))."
    }

    static func fingerprint(_ plan: SetUpPortsPlan) -> [String] {
        plan.ports.map { port in
            "\(port.port.bsdName) \(String(describing: port.port.link)) "
                + "in \(port.bridgesToLeave.joined(separator: "+"))"
                + (port.routesToAdopt ? " already set up" : "")
        }
    }

    // MARK: - One port

    private func setUp(
        _ plan: SetUpPortPlan,
        writer: NetworkWriter,
        world: ObservedWorld,
        environment: OperationEnvironment,
        progress: OperationProgress
    ) throws -> SetUpPortResult {
        let port = plan.port
        // True once the burst has reached something the rest of the Mac can
        // see: a commit that landed, or a rollback that had to run. Every
        // member removal and every service creation before that lives in this
        // session's own `SCPreferences` and is discarded with it, which is
        // exactly what makes R9's and R12's "changed nothing at all" literally
        // true — and while it is true the note must not outlive the attempt,
        // because a leftover note claims a port is managed that nothing
        // touched: the hub would read `.drifted`, offer `Set It Up Again` over
        // an ordinary bridged port, and turn on a `Restore…` that throws.
        var changedSomething = false
        do {
            return try write(
                plan, writer: writer, world: world, environment: environment,
                progress: progress, changedSomething: &changedSomething)
        } catch {
            if !changedSomething, !writer.isDryRun {
                try? environment.store.delete(port: port.bsdName)
            }
            throw error
        }
    }

    private func write(
        _ plan: SetUpPortPlan,
        writer: NetworkWriter,
        world: ObservedWorld,
        environment: OperationEnvironment,
        progress: OperationProgress,
        changedSomething: inout Bool
    ) throws -> SetUpPortResult {
        let port = plan.port
        let recorder = BaselineRecorder.live(
            store: environment.store,
            notes: [port.bsdName: BaselineCapture.note(port: port, world: world)])

        // Step 1. The undo note is step 1 and not step 5: if it cannot be
        // written, nothing is changed at all (R14).
        progress(.saveUndoNote, .running)
        let token = try writeNote(recorder: recorder, port: port, writer: writer)
        progress(.saveUndoNote, .done)

        // Step 2. Out of every bridge, including one that is down.
        var left: [(membership: BridgeMembership, name: String)] = []
        for bridge in plan.bridgesToLeave {
            let membership = world.membership(ofBridge: bridge)
            let named = world.name(ofBridge: bridge)
            let step = OperationStep.leaveBridge(named: named)
            progress(step, .running)
            do {
                try writer.removeMember(port.bsdName, from: membership)
            } catch {
                // R9's body promises "it stopped and changed nothing at all",
                // which is only true while nothing has been written yet.
                if left.isEmpty, let refusal = Refusals.portStillBridged(
                    port.observed, in: world.snapshot,
                    bridgeNames: world.bridgeDisplayNames) {
                    throw refusal
                }
                changedSomething = true
                try rollBack(port: port, created: nil, left: left,
                             cause: "macOS didn't actually let go of the port",
                             serviceName: plan.serviceName,
                             writer: writer, environment: environment, progress: progress)
            }
            left.append((membership, named))
            progress(step, .done)
        }

        // Steps 3 and 4. One call makes the service and sets both protocols,
        // so the addresses row settles as soon as the service exists.
        progress(.createService(named: plan.serviceName), .running)
        let created: CreatedServiceRecord
        do {
            created = try writer.createService(on: port.bsdName, named: plan.serviceName)
        } catch {
            guard !left.isEmpty else { throw error }  // nothing was changed at all
            changedSomething = true
            try rollBack(port: port, created: nil, left: left,
                         cause: "The new service wouldn't create",
                         serviceName: plan.serviceName,
                         writer: writer, environment: environment, progress: progress)
        }
        progress(.createService(named: plan.serviceName), .done)
        progress(.setAddresses, .running)
        progress(.setAddresses, .done)

        // The created service goes into the note **before** the commit, so a
        // crash mid-burst still leaves something that can find it again.
        if !writer.isDryRun {
            do {
                try recorder.recordCreatedService(created, token)
            } catch {
                guard !left.isEmpty else { throw Refusals.baselineUnwritable(detail: "\(error)") }
                // §6.1 rule 7 wants the rollback stated first and the spec has
                // no sentence for "the note wouldn't take the service", so the
                // rollback runs and R14 is what the user is told.
                changedSomething = true
                try? rollBackQuietly(port: port, created: created, left: left,
                                     serviceName: plan.serviceName,
                                     writer: writer, progress: progress)
                throw Refusals.baselineUnwritable(detail: "\(error)")
            }
        }

        do {
            try writer.commitAndApply()
            changedSomething = changedSomething || !writer.isDryRun
        } catch let error as NetworkConfigurationError {
            // Another writer holding the configuration is R12, and nothing was
            // committed or pushed, so there is nothing to put back.
            if case .busy = error { throw Refusals.networkIsBusy(port: port.observed) }
            guard !left.isEmpty else { throw error }
            changedSomething = true
            try rollBack(port: port, created: created, left: left,
                         cause: "The new service wouldn't create",
                         serviceName: plan.serviceName,
                         writer: writer, environment: environment, progress: progress)
        }

        // Step 5. Never an assumption: a port must be out of every bridge, and
        // only the kernel can say so.
        progress(.checkOutOfEveryBridge, .running)
        var agreement = KernelAgreement(agreed: true, settledOnItsOwn: true,
                                        pushedConfiguration: false, settledAfterPush: false,
                                        reads: 0)
        if !writer.isDryRun {
            agreement = try KernelVerification.wait(
                writer: writer, policy: environment.policy,
                budget: environment.remainingBudget) { snapshot in
                    snapshot.bridges(containing: port.bsdName).isEmpty
                }
            guard agreement.agreed else {
                // Out of credential rather than out of patience: the honest
                // reason is R8's, and the port goes back either way.
                changedSomething = true
                try rollBack(port: port, created: created, left: left,
                             cause: "macOS didn't actually let go of the port",
                             serviceName: plan.serviceName,
                             expired: agreement.ranOutOfTime,
                             writer: writer, environment: environment, progress: progress)
            }
            // The log is a record, not a gate: a log that will not take a line
            // does not undo a port that is genuinely set up.
            try? environment.log.append(
                .setUp(port: port.bsdName, positionName: port.positionName))
        }
        progress(.checkOutOfEveryBridge, .done)

        return SetUpPortResult(
            bsdName: port.bsdName,
            positionName: port.positionName,
            serviceName: plan.serviceName,
            createdServiceID: writer.isDryRun ? nil : created.identifier,
            leftBridges: left.map(\.name),
            agreement: agreement)
    }

    /// Writes the note, or refuses. A dry run proves R14 rather than using it:
    /// a note left behind would claim a port is managed that nothing touched.
    private func writeNote(
        recorder: BaselineRecorder,
        port: OperationPort,
        writer: NetworkWriter
    ) throws -> BaselineToken {
        guard !writer.isDryRun else {
            if let refusal = recorder.checkWritable() { throw refusal }
            return BaselineToken(portBSDName: port.bsdName)
        }
        do {
            let token = try recorder.record(port.bsdName)
            guard token.portBSDName == port.bsdName else {
                throw Refusals.baselineUnwritable(
                    detail: "The note that came back is about \(token.portBSDName), "
                        + "not \(port.bsdName).")
            }
            return token
        } catch let refusal as Refusal {
            throw refusal
        } catch {
            throw Refusals.baselineUnwritable(detail: "\(error)")
        }
    }

    // MARK: - Rollback

    /// Puts everything back in reverse order, then says which of the two
    /// things happened: R10 when the port is where it was, R11 when it is not.
    ///
    /// The undo note is **kept** either way — R11's recovery is a hub row that
    /// clears when membership is seen again, and it needs the note to exist.
    private func rollBack(
        port: OperationPort,
        created: CreatedServiceRecord?,
        left: [(membership: BridgeMembership, name: String)],
        cause: String,
        serviceName: String,
        expired: Bool = false,
        writer: NetworkWriter,
        environment: OperationEnvironment,
        progress: OperationProgress
    ) throws -> Never {
        let first = left.first
        var membersNow: [String] = []
        var succeeded = false
        do {
            try undo(port: port, created: created, left: left, serviceName: serviceName,
                     writer: writer, progress: progress)
            if writer.isDryRun {
                succeeded = true
            } else {
                let agreement = try KernelVerification.wait(
                    writer: writer, policy: environment.policy,
                    budget: environment.remainingBudget) { snapshot in
                        let bridges = Set(snapshot.bridges(containing: port.bsdName))
                        return left.allSatisfy { bridges.contains($0.membership.bridgeName) }
                    }
                succeeded = agreement.agreed
            }
        } catch {
            succeeded = false
        }
        if !succeeded, let first {
            membersNow = ((try? writer.readKernel())?[first.membership.bridgeName]?.members) ?? []
        }
        if succeeded {
            // R8 and R10 both say the port was put back; they differ only in
            // why it had to be. Out of credential is R8's sentence, and it is
            // the true one whenever the wait ran out of wall clock.
            if expired { throw Refusals.credentialExpired(port: port.observed) }
            if let first {
                throw Refusals.rolledBack(port: port.observed, bridgeName: first.name,
                                          cause: cause)
            }
        }
        throw Refusals.rollbackFailed(
            port: port.observed,
            bridgeBSDName: first?.membership.bridgeName ?? "",
            bridgeDisplayName: first?.name,
            membersBefore: first?.membership.members ?? [],
            membersNow: membersNow)
    }

    /// The reverse-order undo itself: the service RDMALink just made goes
    /// first, then every bridge the port left, back to front.
    ///
    /// Each row is reported as it is reversed, so §S6's "checklist reverses
    /// with a returning symbol" and the ring re-opening its gaps are driven by
    /// what really happened rather than by a timer (§3.5).
    private func undo(
        port: OperationPort,
        created: CreatedServiceRecord?,
        left: [(membership: BridgeMembership, name: String)],
        serviceName: String,
        writer: NetworkWriter,
        progress: OperationProgress
    ) throws {
        if let created {
            // Named exactly as the checklist row that is being reversed, which
            // is the plan's name and not the record's — a row that cannot be
            // matched cannot be un-ticked.
            let step = OperationStep.createService(named: serviceName)
            _ = created
            progress(.setAddresses, .reversing)
            progress(step, .reversing)
            try writer.deleteService(identifier: created.identifier,
                                     expectedInterface: created.interfaceBSDName)
            progress(step, .pending)
            progress(.setAddresses, .pending)
        }
        for entry in left.reversed() {
            let step = OperationStep.leaveBridge(named: entry.name)
            progress(step, .reversing)
            try writer.addMember(port.bsdName, to: entry.membership,
                                 at: entry.membership.members.firstIndex(of: port.bsdName))
            progress(step, .pending)
        }
        try writer.commitAndApply()
    }

    private func rollBackQuietly(
        port: OperationPort,
        created: CreatedServiceRecord?,
        left: [(membership: BridgeMembership, name: String)],
        serviceName: String,
        writer: NetworkWriter,
        progress: OperationProgress
    ) throws {
        try undo(port: port, created: created, left: left, serviceName: serviceName,
                 writer: writer, progress: progress)
    }
}
