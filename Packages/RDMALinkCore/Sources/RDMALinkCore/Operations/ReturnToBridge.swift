import Foundation

/// What returning one standalone port to the Thunderbolt Bridge would do —
/// UX_SPEC §7.5 and §S10's foreign-port form.
public struct ReturnToBridgePlan: Sendable, Equatable {
    public var port: OperationPort
    public var headline: String
    public var body: String
    public var rows: [String]
    /// The bridge the port will join, as System Settings names it.
    public var bridgeName: String?
    /// Its kernel name.
    public var bridgeBSDName: String?
    /// The standalone service that has to go, when there is one. A bridge
    /// member cannot keep its own service, so there is no half-way option.
    public var serviceName: String?
    public var serviceID: String?
    public var refusal: Refusal?

    public var canProceed: Bool { refusal == nil && bridgeBSDName != nil }
    public var buttonTitle: String? { canProceed ? "Return to Bridge" : nil }
}

public struct ReturnToBridgeResult: Sendable, Equatable {
    public var bsdName: String
    public var positionName: String
    public var bridgeName: String
    public var deletedService: String?
    public var agreement: KernelAgreement
    public var elapsed: TimeInterval

    public var completionLine: String { OperationTiming.completionLine(seconds: elapsed) }
    /// UX_SPEC §S10's foreign-port success.
    public var successHeadline: String { "\(positionName) is in \(bridgeName)" }
    /// §S10's foreign-port success body, in its no-service form when no
    /// standalone service went: the sentence never claims a deletion that did
    /// not happen.
    public var successBody: String {
        guard deletedService != nil else {
            return """
                The port is a member of \(bridgeName) again. Set Up Again is \
                one click away if you change your mind.
                """
        }
        return """
            The port is a member of \(bridgeName) again and its standalone service \
            is gone. Set Up Again is one click away if you change your mind.
            """
    }
}

/// Puts any standalone port back into the Thunderbolt Bridge — whoever took it
/// out, and whether or not RDMALink has a note for it.
///
/// This is the ordinary thing rather than the remembered thing: RDMALink still
/// writes down what it found first, so the port can be set up again
/// afterwards, and it **never creates a bridge**.
public struct ReturnToBridge: Sendable {
    /// The name the spec gives the bridge this looks for first.
    public static let preferredBridgeName = "Thunderbolt Bridge"

    /// §S10's foreign-port question. Like Restore's it names no port — a
    /// position name at its head would read "Return Back, far right…" — and
    /// the body does.
    public static func headline(bridgeName: String = preferredBridgeName) -> String {
        "Return this port to \(bridgeName)?"
    }

    /// The same sheet while its checklist runs (§S10).
    public static func runningHeadline(bridgeName: String = preferredBridgeName) -> String {
        "Returning this port to \(bridgeName)"
    }

    public let port: OperationPort

    public init(port: OperationPort) { self.port = port }

    // MARK: - Preview

    /// What would happen. Pure.
    public func preview(world: ObservedWorld) -> ReturnToBridgePlan {
        var plan = ReturnToBridgePlan(
            port: port,
            headline: Self.headline(),
            body: "",
            rows: [],
            bridgeName: nil,
            bridgeBSDName: nil,
            serviceName: nil,
            serviceID: nil,
            refusal: nil)

        let service = NetworkServices.services(for: port.bsdName, in: world.services).first
        plan.serviceName = service?.name
        plan.serviceID = service?.serviceID

        // UX_SPEC §6.2 R31 before everything: no bridge is chosen and no row
        // is written for a Mac neither rule in §4.7 recognizes.
        if let refusal = Refusals.macRecognized(world.context.hardware) {
            plan.refusal = refusal
            return plan
        }
        guard let bridge = Self.chooseBridge(world: world) else {
            // RDMALink never creates one, so there is nothing to offer but the
            // hand-off. Nothing is written.
            plan.refusal = Refusals.noBridgeToReturnTo(port: port.observed)
            return plan
        }
        plan.bridgeBSDName = bridge.bsdName
        let named = bridge.displayName ?? bridge.bsdName
        plan.bridgeName = named
        plan.headline = Self.headline(bridgeName: named)
        // §S10's foreign-port form, and its no-service form when the port was
        // taken out of the bridge by hand and left bare: the delete row and
        // every sentence about a service are omitted, not blanked (§7.5 step 2).
        if let service {
            plan.body = """
                RDMALink didn't set up \(port.positionName), so it can't put \
                things back exactly as they were — but it can do the ordinary \
                thing: add the port to \(named) and remove the standalone service \
                it has now. It writes down what it found first, so you can set the \
                port up again afterwards.
                """
            plan.rows = [
                "Add the port to \(named)",
                """
                Delete the service \(service.name) — RDMALink didn't make this one, \
                and a bridge member can't keep its own service
                """,
                "Check that it really is in the bridge",
                "Leave every other setting alone",
            ]
        } else {
            plan.body = """
                RDMALink didn't set up \(port.positionName), so it can't put \
                things back exactly as they were — but it can do the ordinary \
                thing: add the port to \(named). It writes down what it found \
                first, so you can set the port up again afterwards.
                """
            plan.rows = [
                "Add the port to \(named)",
                "Check that it really is in the bridge",
                "Leave every other setting alone",
            ]
        }
        if let refusal = Refusals.nothingMountedOverThunderbolt(world.mountedVolumes) {
            plan.refusal = refusal
        } else if !world.bridges(containing: port.bsdName).isEmpty {
            // Already a member: there is nothing to return.
            plan.refusal = Refusals.topologyChanged(
                subjects: [port.bsdName],
                detail: "\(port.bsdName) is already a member of "
                    + englishList(world.bridges(containing: port.bsdName)) + ".")
        }
        return plan
    }

    /// The bridge to join: the one named `Thunderbolt Bridge`, else the only
    /// bridge there is. Anything else is not a choice RDMALink will make.
    static func chooseBridge(world: ObservedWorld) -> BridgeSPI.Membership? {
        let bridges = world.bridges
        if let named = bridges.first(where: { $0.displayName == preferredBridgeName }) {
            return named
        }
        return bridges.count == 1 ? bridges[0] : nil
    }

    // MARK: - Perform

    @discardableResult
    public func perform(
        session: AuthorizedSession,
        environment: OperationEnvironment,
        progress: @escaping OperationProgress = { _, _ in }
    ) throws -> ReturnToBridgeResult {
        try perform(writer: LiveNetworkWriter(session: session, runner: environment.runner),
                    environment: environment, progress: progress)
    }

    @discardableResult
    func perform(
        writer: NetworkWriter,
        environment: OperationEnvironment,
        progress: OperationProgress
    ) throws -> ReturnToBridgeResult {
        try writer.lock()
        let world = try ObservedWorld.reread(
            ports: [port], writer: writer, hardware: environment.hardware,
            notesDirectory: environment.store.directory, runner: environment.runner)
        return try perform(writer: writer, world: world,
                           environment: environment, progress: progress)
    }

    /// R12: two things writing network settings at once is how configurations
    /// get mangled, and nothing was committed.
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
    ) throws -> ReturnToBridgeResult {
        let clock = ContinuousClock()
        let started = clock.now
        try writer.lock()
        let plan = preview(world: world)
        if let refusal = plan.refusal { throw refusal }
        guard let bridgeBSDName = plan.bridgeBSDName, let bridgeName = plan.bridgeName else {
            throw Refusals.noBridgeToReturnTo(port: port.observed)
        }
        if let refusal = world.notesAreWritable { throw refusal }

        // Defence in depth for the one note this operation must never write
        // over. A port RDMALink set up has a note recording the bridges it
        // came from and the service RDMALink made; writing a fresh note here
        // would replace that history with `bridges: []` and join the port to
        // whatever bridge this Mac happens to have — which is not where it
        // came from, and afterwards there would be nothing left to restore
        // from. The way back for such a port is `Restore…`, and the row and
        // the Port menu both offer only that (§S1, §7.2).
        if let existing = try? environment.store.load(port: port.bsdName),
            !existing.isAdopted, existing.createdService != nil {
            throw NetworkConfigurationError.missing(
                "a port RDMALink did not set up: \(port.bsdName) has an undo note "
                    + "recording how it was before RDMALink changed it, and Restore "
                    + "is the way back")
        }

        // Step 1. The note first, recording the standalone service it found
        // and the bridge it is about to join — without it, nothing is changed
        // (§7.5 step 1, R14). The bridge is what makes it a return record.
        progress(.saveUndoNote, .running)
        let returnedTo = BridgeReturn(
            bsdName: bridgeBSDName,
            displayName: world.bridgeDisplayNames[bridgeBSDName])
        let recorder = BaselineRecorder.live(
            store: environment.store,
            notes: [port.bsdName: BaselineCapture.note(port: port, world: world,
                                                       returnedTo: returnedTo)])
        do {
            _ = try recorder.record(port.bsdName)
        } catch let refusal as Refusal {
            throw refusal
        } catch {
            throw Refusals.baselineUnwritable(detail: "\(error)")
        }
        progress(.saveUndoNote, .done)

        // Step 2. The standalone service goes, and only when it is on this port.
        var deleted: String?
        if let serviceID = plan.serviceID {
            let step = OperationStep.deleteForeignService(named: plan.serviceName ?? "")
            progress(step, .running)
            if try writer.deleteService(identifier: serviceID, expectedInterface: port.bsdName) {
                deleted = plan.serviceName
                // In a commit of its own, and the port given time to go
                // quiet: written into the same apply, the membership lands
                // while IPv6 is still being torn down and the kernel refuses
                // it (see `BridgeRejoin`).
                try commitOrBusy(writer)
                _ = try KernelVerification.waitUntilQuiet(
                    port.bsdName, writer: writer, policy: environment.policy)
            }
            progress(step, .done)
        }

        // Step 3. Joined to the bridge that already exists. Never created.
        // The record the SPI is checked against lists this port too, so the
        // retry's own removal resolves the same bridge.
        var membership = world.membership(ofBridge: bridgeBSDName)
        if !membership.members.contains(port.bsdName) { membership.members.append(port.bsdName) }
        progress(.joinBridge(named: bridgeName), .running)
        let rewroteAtAddTime = try BridgeRejoin.add(port.bsdName, to: membership, at: nil,
                                                    writer: writer, policy: environment.policy)
        try commitOrBusy(writer)
        progress(.joinBridge(named: bridgeName), .done)

        // Step 4. Read back from the kernel before the sheet says it is in.
        progress(.checkInBridge, .running)
        // Both sources: the kernel bridging it, and the preferences listing
        // it — the same two the set-up path has to see cleared.
        let agreement = try KernelVerification.wait(
            writer: writer, policy: environment.policy,
            retry: {
                try BridgeRejoin.toggle(port.bsdName, in: membership, at: nil,
                                        writer: writer, policy: environment.policy)
                try writer.commitAndApply()
            }) { reading in
                reading.isMember(port.bsdName, ofAll: [bridgeBSDName])
            }
            .foldingRewrite(atAddTime: rewroteAtAddTime)
        guard agreement.agreed else {
            // On a miss the note is kept and R20 applies (§7.5 step 4),
            // saying a service went only when one did.
            throw Refusals.notBackInBridge(
                port: port.observed, bridgeName: bridgeName, removedService: deleted != nil)
        }
        // Step 5. The change log records the return (§S11), saying that a
        // service went only when one did.
        try? environment.log.append(.returned(
            port: port.bsdName, positionName: port.positionName,
            bridgeName: bridgeName, removedService: deleted != nil))
        progress(.checkInBridge, .done)

        let elapsed = clock.now - started
        return ReturnToBridgeResult(
            bsdName: port.bsdName,
            positionName: port.positionName,
            bridgeName: bridgeName,
            deletedService: deleted,
            agreement: agreement,
            elapsed: Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18)
    }
}
