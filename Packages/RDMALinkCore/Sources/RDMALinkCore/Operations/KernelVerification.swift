import Foundation

/// How long the kernel is given to agree, and how the wait is spent.
///
/// Bridge membership is realised outside `SCPreferencesCommitChanges`, so
/// there is a moment after a write in which the stored configuration and
/// `ifconfig` disagree. Nothing is ever reported as done on the strength of
/// the write alone (UX_SPEC §S6 step 5, §7.2 step 3).
public struct KernelWaitPolicy: Sendable {
    /// How long to wait before applying the configuration a second time, and
    /// again after it.
    ///
    /// Measured on the wall clock across the whole loop, **including** the
    /// `ifconfig` spawn each read costs — a window counted in sleeps alone is a
    /// floor, not a budget, and the credential does not care which.
    public var window: Duration
    /// How long between reads of `ifconfig`.
    public var interval: Duration
    /// The most wall-clock time one whole verification may take, both polls
    /// and the second apply included. Exceeding it is not an agreement:
    /// the caller rolls back and raises R8.
    public var budget: Duration
    /// How a wait is spent. Tests pass a closure that returns at once, so a
    /// kernel that catches up late can be exercised without taking the time.
    public var pause: @Sendable (Duration) -> Void

    public init(
        window: Duration,
        interval: Duration,
        budget: Duration? = nil,
        pause: @escaping @Sendable (Duration) -> Void
    ) {
        self.window = window
        self.interval = interval
        self.budget = budget ?? window + window
        self.pause = pause
    }

    /// Three seconds in 100 ms steps, capped at four seconds of wall clock.
    ///
    /// One port's verification therefore cannot eat more than four of the
    /// thirty seconds the credential lasts, whatever `ifconfig` does.
    public static let standard = KernelWaitPolicy(
        window: .seconds(3),
        interval: .milliseconds(100),
        budget: .seconds(4),
        pause: { duration in
            let parts = duration.components
            Thread.sleep(forTimeInterval:
                Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
        })
}

/// What it took for the kernel to agree — recorded so the hardware proof can
/// say which of the two waits was the one that mattered.
public struct KernelAgreement: Sendable, Equatable {
    /// Whether the kernel ended up agreeing at all.
    public var agreed: Bool
    /// The kernel caught up on its own, before the second apply.
    public var settledOnItsOwn: Bool
    /// The configuration was applied a second time, so configd ran its own
    /// bridge update again. The app cannot run that update itself.
    public var reappliedConfiguration: Bool
    /// The second apply was what made the difference.
    public var settledAfterReapply: Bool
    /// How many times `ifconfig` was read.
    public var reads: Int
    /// The wait ran out of wall clock rather than out of patience. The caller
    /// puts the port back and raises R8 rather than R10: the truthful reason
    /// is that the permission window, not the kernel, was the problem.
    public var ranOutOfTime: Bool

    public init(
        agreed: Bool,
        settledOnItsOwn: Bool,
        reappliedConfiguration: Bool,
        settledAfterReapply: Bool,
        reads: Int,
        ranOutOfTime: Bool = false
    ) {
        self.agreed = agreed
        self.settledOnItsOwn = settledOnItsOwn
        self.reappliedConfiguration = reappliedConfiguration
        self.settledAfterReapply = settledAfterReapply
        self.reads = reads
        self.ranOutOfTime = ranOutOfTime
    }
}

/// One round of verification: both places bridge membership is real, read at
/// the same moment.
///
/// A membership change is not done when `ifconfig` agrees and the preferences
/// still list the port — configd refuses to create a service on an interface a
/// stored bridge claims, so a half-agreed state is a state the next step would
/// fail in. Both reads therefore travel together and every predicate gets both.
struct VerificationReading: Sendable {
    /// What `ifconfig -a` says.
    var snapshot: InterfaceSnapshot
    /// What a fresh, unprivileged preferences handle says — the committed
    /// configuration.
    ///
    /// `nil` when it would not be read at all. Never flattened to `[]`: an
    /// unreadable configuration is not evidence that a removal landed, and
    /// every question below answers **no** while it is nil.
    var stored: [BridgeSPI.Membership]?

    /// Every bridge either read puts this port in, kernel first.
    func bridges(containing bsdName: String) -> [String] {
        let kernel = snapshot.bridges(containing: bsdName)
        let saved = StoredBridges.names(in: stored ?? [], containing: bsdName)
        return kernel + saved.filter { !kernel.contains($0) }
    }

    /// True when both reads answered and neither lists this port in a bridge.
    func isOutOfEveryBridge(_ bsdName: String) -> Bool {
        guard stored != nil else { return false }
        return bridges(containing: bsdName).isEmpty
    }

    /// True when **both** reads list this port in every one of `bridgeNames`.
    func isMember(_ bsdName: String, ofAll bridgeNames: [String]) -> Bool {
        guard let stored else { return false }
        let kernel = Set(snapshot.bridges(containing: bsdName))
        let saved = Set(StoredBridges.names(in: stored, containing: bsdName))
        return bridgeNames.allSatisfy { kernel.contains($0) && saved.contains($0) }
    }
}

enum KernelVerification {
    /// Reads the kernel **and** the stored configuration until they both say
    /// what the write asked for.
    ///
    /// Waits out the window first, then — only if they still disagree — applies
    /// the configuration a second time, **once**, and waits again. configd runs
    /// its own `_SCBridgeInterfaceUpdateConfiguration` on every apply and the
    /// app cannot run it itself (it needs root), so a second apply is the
    /// retry. Which of the two got there is reported rather than assumed.
    static func wait(
        writer: NetworkWriter,
        policy: KernelWaitPolicy,
        budget: Duration? = nil,
        until predicate: (VerificationReading) -> Bool
    ) throws -> KernelAgreement {
        var reads = 0
        var ranOutOfTime = false
        let clock = ContinuousClock()
        let started = clock.now
        // Whichever runs out first: this verification's own cap, or what is
        // left of the burst's.
        let cap = min(policy.budget, budget ?? policy.budget)

        /// Reads both sources until they agree, the window closes, or the wall
        /// clock runs out — and the reads themselves are inside the
        /// measurement, because a `posix_spawn` of `ifconfig` costs real
        /// credential time.
        func poll() throws -> Bool {
            var waited = Duration.zero
            while true {
                reads += 1
                let reading = VerificationReading(
                    snapshot: try writer.readKernel(),
                    stored: try? writer.readStoredBridges())
                if predicate(reading) { return true }
                if clock.now - started >= cap {
                    ranOutOfTime = true
                    return false
                }
                if waited >= policy.window { return false }
                policy.pause(policy.interval)
                waited += policy.interval
            }
        }

        if try poll() {
            return KernelAgreement(agreed: true, settledOnItsOwn: true,
                                   reappliedConfiguration: false, settledAfterReapply: false,
                                   reads: reads)
        }
        guard !ranOutOfTime, writer.canReapplyConfiguration else {
            return KernelAgreement(agreed: false, settledOnItsOwn: false,
                                   reappliedConfiguration: false, settledAfterReapply: false,
                                   reads: reads, ranOutOfTime: ranOutOfTime)
        }
        // A second apply that fails is not a reason to abandon the operation
        // mid-verification with a raw error: it is recorded as "could not ask
        // again", and the caller takes its rollback or keep-the-note path.
        do {
            try writer.reapplyConfiguration()
        } catch {
            return KernelAgreement(agreed: false, settledOnItsOwn: false,
                                   reappliedConfiguration: false, settledAfterReapply: false,
                                   reads: reads, ranOutOfTime: false)
        }
        let settled = try poll()
        return KernelAgreement(agreed: settled, settledOnItsOwn: false,
                               reappliedConfiguration: true, settledAfterReapply: settled,
                               reads: reads, ranOutOfTime: !settled && ranOutOfTime)
    }
}
