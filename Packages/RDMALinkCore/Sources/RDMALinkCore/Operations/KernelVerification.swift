import Foundation

/// How long the kernel is given to agree, and how the wait is spent.
///
/// Bridge membership is realised outside `SCPreferencesCommitChanges`, so
/// there is a moment after a write in which the stored configuration and
/// `ifconfig` disagree. Nothing is ever reported as done on the strength of
/// the write alone (UX_SPEC §S6 step 5, §7.2 step 3).
public struct KernelWaitPolicy: Sendable {
    /// How long to wait before pushing the configuration, and again after it.
    ///
    /// Measured on the wall clock across the whole loop, **including** the
    /// `ifconfig` spawn each read costs — a window counted in sleeps alone is a
    /// floor, not a budget, and the credential does not care which.
    public var window: Duration
    /// How long between reads of `ifconfig`.
    public var interval: Duration
    /// The most wall-clock time one whole verification may take, both polls
    /// and the configuration push included. Exceeding it is not an agreement:
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
    /// The kernel caught up on its own, before anything was pushed.
    public var settledOnItsOwn: Bool
    /// `_SCBridgeInterfaceUpdateConfiguration` was called.
    public var pushedConfiguration: Bool
    /// The push was what made the difference.
    public var settledAfterPush: Bool
    /// How many times `ifconfig` was read.
    public var reads: Int
    /// The wait ran out of wall clock rather than out of patience. The caller
    /// puts the port back and raises R8 rather than R10: the truthful reason
    /// is that the permission window, not the kernel, was the problem.
    public var ranOutOfTime: Bool

    public init(
        agreed: Bool,
        settledOnItsOwn: Bool,
        pushedConfiguration: Bool,
        settledAfterPush: Bool,
        reads: Int,
        ranOutOfTime: Bool = false
    ) {
        self.agreed = agreed
        self.settledOnItsOwn = settledOnItsOwn
        self.pushedConfiguration = pushedConfiguration
        self.settledAfterPush = settledAfterPush
        self.reads = reads
        self.ranOutOfTime = ranOutOfTime
    }
}

enum KernelVerification {
    /// Reads the kernel until it says what the write asked for.
    ///
    /// Waits out the window first, then — only if the kernel still disagrees —
    /// pushes the bridge configuration **once** and waits again. Which of the
    /// two got there is reported rather than assumed, because on this hardware
    /// it is not yet known which one is really needed.
    static func wait(
        writer: NetworkWriter,
        policy: KernelWaitPolicy,
        budget: Duration? = nil,
        until predicate: (InterfaceSnapshot) -> Bool
    ) throws -> KernelAgreement {
        var reads = 0
        var ranOutOfTime = false
        let clock = ContinuousClock()
        let started = clock.now
        // Whichever runs out first: this verification's own cap, or what is
        // left of the burst's.
        let cap = min(policy.budget, budget ?? policy.budget)

        /// Reads the kernel until it agrees, the window closes, or the wall
        /// clock runs out — and the read itself is inside the measurement,
        /// because a `posix_spawn` of `ifconfig` costs real credential time.
        func poll() throws -> Bool {
            var waited = Duration.zero
            while true {
                reads += 1
                if predicate(try writer.readKernel()) { return true }
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
                                   pushedConfiguration: false, settledAfterPush: false,
                                   reads: reads)
        }
        guard !ranOutOfTime, writer.canPushBridgeConfiguration else {
            return KernelAgreement(agreed: false, settledOnItsOwn: false,
                                   pushedConfiguration: false, settledAfterPush: false,
                                   reads: reads, ranOutOfTime: ranOutOfTime)
        }
        try writer.pushBridgeConfiguration()
        let settled = try poll()
        return KernelAgreement(agreed: settled, settledOnItsOwn: false,
                               pushedConfiguration: true, settledAfterPush: settled,
                               reads: reads, ranOutOfTime: !settled && ranOutOfTime)
    }
}
