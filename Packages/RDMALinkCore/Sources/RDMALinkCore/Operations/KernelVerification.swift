import Foundation

/// How long the kernel is given to agree, and how the wait is spent.
///
/// Bridge membership is realised outside `SCPreferencesCommitChanges`, so
/// there is a moment after a write in which the stored configuration and
/// `ifconfig` disagree. Nothing is ever reported as done on the strength of
/// the write alone (UX_SPEC §S6 step 5, §7.2 step 3).
public struct KernelWaitPolicy: Sendable {
    /// How long to wait before the membership is rewritten, and again after
    /// it; also how long a port is given to go quiet before it rejoins.
    ///
    /// Measured on the wall clock across the whole loop, **including** the
    /// `ifconfig` spawn each read costs — a window counted in sleeps alone is a
    /// floor, not a budget, and the credential does not care which.
    public var window: Duration
    /// How long between reads of `ifconfig`.
    public var interval: Duration
    /// The most wall-clock time one whole verification may take, both polls
    /// and the retry included. Exceeding it is not an agreement:
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
    /// The kernel followed the first apply; nothing had to be retried.
    public var settledOnItsOwn: Bool
    /// The stored membership was rewritten — taken out and put back, each in
    /// a commit of its own — because the kernel had not followed the first
    /// apply. A commit that changes nothing makes configd attempt nothing, so
    /// this is the only retry there is (measured 2026-09-20).
    public var retriedMembership: Bool
    /// The retry was what made the difference.
    public var settledAfterRetry: Bool
    /// How many times `ifconfig` was read.
    public var reads: Int
    /// The wait ran out of wall clock rather than out of patience. The caller
    /// puts the port back and raises R8 rather than R10: the truthful reason
    /// is that the permission window, not the kernel, was the problem.
    public var ranOutOfTime: Bool

    public init(
        agreed: Bool,
        settledOnItsOwn: Bool,
        retriedMembership: Bool,
        settledAfterRetry: Bool,
        reads: Int,
        ranOutOfTime: Bool = false
    ) {
        self.agreed = agreed
        self.settledOnItsOwn = settledOnItsOwn
        self.retriedMembership = retriedMembership
        self.settledAfterRetry = settledAfterRetry
        self.reads = reads
        self.ranOutOfTime = ranOutOfTime
    }

    /// This agreement with a membership rewrite that happened **at add time**
    /// folded in (``BridgeRejoin/add(_:to:at:writer:policy:)``).
    ///
    /// The stored list already had the port, so it was taken out and put back
    /// before the verification began. A kernel that then agreed on the first
    /// read did not settle on its own: the retry is what it followed, and the
    /// "kernel settled …" line has to say so.
    func foldingRewrite(atAddTime rewritten: Bool) -> KernelAgreement {
        guard rewritten else { return self }
        var folded = self
        folded.settledOnItsOwn = false
        folded.retriedMembership = true
        folded.settledAfterRetry = agreed
        return folded
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
    /// Waits out the window first, then — only if they still disagree and the
    /// caller has a `retry` — runs it **once** and waits again. The app cannot
    /// run configd's `_SCBridgeInterfaceUpdateConfiguration` itself (it needs
    /// root), and a bare second apply makes configd attempt nothing, so the
    /// retry is the caller's: for a membership, take it out and put it back in
    /// commits of their own. Which of the two got there is reported rather
    /// than assumed.
    static func wait(
        writer: NetworkWriter,
        policy: KernelWaitPolicy,
        budget: Duration? = nil,
        retry: (() throws -> Void)? = nil,
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
                                   retriedMembership: false, settledAfterRetry: false,
                                   reads: reads)
        }
        guard !ranOutOfTime, let retry else {
            return KernelAgreement(agreed: false, settledOnItsOwn: false,
                                   retriedMembership: false, settledAfterRetry: false,
                                   reads: reads, ranOutOfTime: ranOutOfTime)
        }
        // A retry that fails is not a reason to abandon the operation
        // mid-verification with a raw error: it is recorded as attempted, and
        // the caller takes its rollback or keep-the-note path.
        do {
            try retry()
        } catch {
            return KernelAgreement(agreed: false, settledOnItsOwn: false,
                                   retriedMembership: true, settledAfterRetry: false,
                                   reads: reads, ranOutOfTime: false)
        }
        let settled = try poll()
        return KernelAgreement(agreed: settled, settledOnItsOwn: false,
                               retriedMembership: true, settledAfterRetry: settled,
                               reads: reads, ranOutOfTime: !settled && ranOutOfTime)
    }

    /// Waits for a port to have no IP configuration left on it: not up, and
    /// no addresses of either family.
    ///
    /// configd attempts a bridge add a few milliseconds after an apply, while
    /// IPConfiguration may still be tearing the port's IPv6 down — on
    /// 2026-09-20 the add came 8 ms after the apply and the IPv6 detach 40 ms
    /// after it — and the kernel refuses a member that still has IP attached
    /// ("Operation not supported on socket"). So a service is deleted in a
    /// commit of its own and the port is given until the window closes to go
    /// quiet before it rejoins. Returns whether it did; the caller carries on
    /// either way, and the read-back afterwards is what decides.
    static func waitUntilQuiet(
        _ bsdName: String,
        writer: NetworkWriter,
        policy: KernelWaitPolicy
    ) throws -> Bool {
        var waited = Duration.zero
        while true {
            if let state = try writer.readKernel()[bsdName] {
                if !state.isUp, state.addresses.isEmpty, state.linkLocalAddresses.isEmpty {
                    return true
                }
            } else {
                return true
            }
            if waited >= policy.window { return false }
            policy.pause(policy.interval)
            waited += policy.interval
        }
    }
}
