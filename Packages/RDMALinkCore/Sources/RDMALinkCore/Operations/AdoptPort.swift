import Foundation

/// One row of UX_SPEC §S9's findings list: a label and what was found.
public struct AdoptFinding: Sendable, Equatable {
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// What RDMALink found on a port somebody else configured.
public struct AdoptPortPlan: Sendable, Equatable {
    /// Which of §S9's three states this port is in.
    public enum Match: Sendable, Equatable {
        /// Exactly what RDMALink would have made. `Adopt…` is offered.
        case full
        /// Its own service, but something differs. **Never adjusted** —
        /// RDMALink did not create it and will not rewrite it.
        case near(differences: [ConfigurationDifference])
        /// Not a match at all. No `Adopt…` button is ever offered.
        case none
    }

    public var port: OperationPort
    public var match: Match
    public var headline: String
    public var body: String
    /// The four findings rows, in the spec's order.
    public var findings: [AdoptFinding]
    /// The steps to make a near match into a full one. RDMALink hands them
    /// over rather than applying them.
    public var steps: String?
    public var notes: [String]
    public var buttonTitles: [String]
    /// R31, when this Mac is not one RDMALink recognizes: the findings are
    /// still what was found, but nothing is offered and no note is written.
    public var refusal: Refusal?

    public var canAdopt: Bool { refusal == nil && match == .full }
}

/// Recognizes a port someone configured by hand and takes responsibility for
/// it **without touching it** (UX_SPEC §S9, §7.3).
///
/// Adopting changes nothing and needs no password: there is no session here on
/// purpose. RDMALink is only writing itself a note.
public struct AdoptPort: Sendable {
    public static let note = """
        Adopting changes nothing and needs no password. RDMALink is only \
        writing itself a note.
        """
    /// Names the two buttons it means by their own words, without their
    /// ellipses, as prose does (§1.3 rule 11).
    public static let honestyNote = """
        One thing to be straight about: RDMALink never saw this port before, so \
        it doesn't know which bridge it came from. There's no exact "put it \
        back" for an adopted port — Return to Bridge does the ordinary thing \
        instead, and Stop Managing leaves the port exactly as it is.
        """
    public static let watcherLine = """
        RDMALink keeps looking, and offers to adopt the port the moment it \
        matches.
        """

    public let port: OperationPort

    public init(port: OperationPort) { self.port = port }

    // MARK: - Preview

    /// What RDMALink found, and what it will offer. Pure: no writes, and no
    /// password anywhere in this path.
    ///
    /// UX_SPEC §6.2 R31 comes first, as it does in every operation: on a Mac
    /// neither rule in §4.7 recognizes the findings are reported as they are,
    /// with no button row, because a note is a write too.
    public func preview(world: ObservedWorld) -> AdoptPortPlan {
        var plan = found(world: world)
        if let refusal = Refusals.macRecognized(world.context.hardware) {
            plan.refusal = refusal
            plan.buttonTitles = []
        }
        return plan
    }

    /// Which of §S9's three states the port is in, on a Mac RDMALink knows.
    private func found(world: ObservedWorld) -> AdoptPortPlan {
        let bridges = world.bridges(containing: port.bsdName)
        let services = NetworkServices.services(for: port.bsdName, in: world.services)
        let configuration = NetworkServices.classify(services: services, bridges: bridges)
        let service = services.first
        let findings = Self.findings(service: service, bridges: bridges.map(world.name(ofBridge:)))

        switch configuration {
        case .readyForRDMA:
            return AdoptPortPlan(
                port: port, match: .full,
                headline: "This port is already set up",
                body: """
                    \(port.positionName) isn't in any bridge and already has its \
                    own service with IPv4 off and IPv6 link-local only. That's \
                    exactly what RDMALink would have made. Adopt it and RDMALink \
                    will keep an eye on it — without changing a thing.
                    """,
                findings: findings,
                steps: nil,
                notes: [Self.note, Self.honestyNote],
                buttonTitles: ["Adopt", "Cancel"])

        case let .nearMatch(_, differences):
            // §7.3: Adopt is for a port "out of every bridge, its own service".
            // A port that is still a bridge member is not that case, and the
            // near-match body opens by saying it is — so it is not offered
            // Adopt at all rather than shown a sentence that contradicts
            // itself in its own second clause (§1.3 rule 10).
            guard !differences.contains(where: \.isBridgeMembership),
                let clause = ConfigurationDifference.serviceClause(in: differences)
            else {
                return AdoptPortPlan(
                    port: port, match: .none,
                    headline: "This port is already set up",
                    body: "",
                    findings: findings,
                    steps: nil,
                    notes: [],
                    buttonTitles: [])
            }
            return AdoptPortPlan(
                port: port, match: .near(differences: differences),
                headline: "Nearly a match",
                body: """
                    \(port.positionName) is out of every bridge and has its own \
                    service, but \(clause). RDMALink didn't make this service, so \
                    it won't rewrite it — but here's exactly what to change, and \
                    RDMALink adopts the port the moment it matches.
                    """,
                findings: findings,
                steps: """
                    In System Settings, open Network, choose \
                    \(service?.name ?? port.positionName), then Details, then \
                    TCP/IP. Set Configure IPv6 to Link-local only. Set Configure \
                    IPv4 to Off.
                    """,
                notes: [Self.watcherLine],
                buttonTitles: ["Open Network Settings", "Copy These Steps", "Cancel"])

        case .unconfigured, .foreign:
            // Not a match at all: no `Adopt…` button is ever offered, and the
            // hub subtitle simply describes what it found.
            return AdoptPortPlan(
                port: port, match: .none,
                headline: "This port is already set up",
                body: "",
                findings: findings,
                steps: nil,
                notes: [],
                buttonTitles: [])
        }
    }

    /// §S9's four findings rows.
    static func findings(service: NetworkServiceInfo?, bridges: [String]) -> [AdoptFinding] {
        [
            AdoptFinding(label: "Service", value: service?.name ?? "None"),
            AdoptFinding(label: "IPv4", value: describe(service?.ipv4, isIPv4: true)),
            AdoptFinding(label: "IPv6", value: describe(service?.ipv6, isIPv4: false)),
            AdoptFinding(label: "Bridge membership",
                         value: bridges.isEmpty ? "None" : englishList(bridges)),
        ]
    }

    /// The spec names three values — `Off`, `Link-local only` and `Automatic`.
    /// Anything else is reported in macOS's own word rather than guessed at.
    static func describe(_ configuration: ProtocolConfiguration?, isIPv4: Bool) -> String {
        if isIPv4, NetworkServices.isOff(configuration) { return "Off" }
        guard let configuration, configuration.isEnabled else { return "Off" }
        guard let method = configuration.configMethod else { return "Automatic" }
        if method == NetworkServices.linkLocalMethod { return "Link-local only" }
        if NetworkServices.offMethods.contains(method) { return "Off" }
        return method
    }

    // MARK: - Perform

    /// Writes the note. **No password, no writes to the network.**
    ///
    /// - Returns: §S9's confirmation line.
    @discardableResult
    public func perform(world: ObservedWorld, environment: OperationEnvironment) throws -> String {
        let plan = preview(world: world)
        if let refusal = plan.refusal { throw refusal }
        guard plan.canAdopt else {
            // A near match is never adjusted and never adopted; the app keeps
            // watching instead.
            throw NetworkConfigurationError.missing(
                "a port that matches what RDMALink would have made: \(port.bsdName)")
        }
        if let refusal = world.notesAreWritable { throw refusal }
        try environment.store.save(BaselineCapture.note(port: port, world: world, isAdopted: true))
        try? environment.log.append(
            .adopted(port: port.bsdName, positionName: port.positionName))
        return "Adopted. \(port.positionName) is in RDMALink's care now."
    }
}

/// Forgets RDMALink's note for a port and changes nothing on the system
/// (UX_SPEC §S10's stop-managing form, §7.3) — an adopted port's, a return
/// record's, or a drifted port's (§S1).
public struct StopManaging: Sendable {
    public let port: OperationPort
    /// The note that would be forgotten, as it was read when the form opened.
    /// Only what it records is asked of it: whether it is a way back.
    public let note: PortBaseline?

    public init(port: OperationPort, note: PortBaseline? = nil) {
        self.port = port
        self.note = note
    }

    /// True when the note records the bridges the port came from — a
    /// drifted port's. Forgetting it forgets the only way back, so the form
    /// says so and has no default (§S10, §2.6).
    public var forgetsTheWayBack: Bool { note?.bridges.isEmpty == false }

    /// §S10's stop-managing question. It names no port, as Restore's and
    /// Return to Bridge's don't: the camera has already turned to it, and the
    /// body names it.
    public static let headline = "Stop managing this port?"
    /// The same sheet while the note is being forgotten (§S10).
    public static let runningHeadline = "Forgetting this port's note"
    public var body: String {
        guard forgetsTheWayBack else {
            return """
                Stopping just means RDMALink forgets its note for \
                \(port.positionName). The port and its settings stay exactly as \
                they are.
                """
        }
        return """
            Stopping just means RDMALink forgets its note for \
            \(port.positionName). The port and its settings stay exactly as they \
            are. RDMALink won't be able to put it back afterwards.
            """
    }
    public var buttonTitle: String { "Stop Managing" }

    /// Deletes the note. Nothing else, anywhere.
    ///
    /// Reads no world, so R31 is asked of the environment: a note is a write,
    /// and RDMALink writes nothing on a Mac it does not recognize (§6.2 R31).
    ///
    /// - Returns: the confirmation line, which says exactly that.
    @discardableResult
    public func perform(environment: OperationEnvironment, now: Date = Date()) throws -> String {
        if let refusal = Refusals.macRecognized(environment.hardware) { throw refusal }
        try environment.store.delete(port: port.bsdName)
        try? environment.log.append(ChangeEntry(
            date: now, port: port.bsdName, positionName: port.positionName,
            kind: .stoppedManaging,
            sentence: ChangeSentence.stoppedLookingAfter(moment: Moment.text(now))))
        return """
            Done. \(port.positionName) is exactly as it was a moment ago — \
            RDMALink is simply no longer keeping an eye on it.
            """
    }
}
