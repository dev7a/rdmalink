import Foundation

/// S4b's two timers, as a pure function of elapsed time (UX_SPEC §S4b).
///
/// The watch itself is the app's — it needs the live port reads — but the two
/// deadlines are the only numbers in the spec's one permitted timer, and a
/// deadline that is never reached is worse than no deadline at all. Keeping
/// them here means they can be driven past with a value rather than with a
/// minute of real time.
public enum IdentifyClock {
    /// "Still waiting for it to come back. Take your time."
    public static let nudgeAfter: Duration = .seconds(30)
    /// "RDMALink didn't see anything change."
    public static let timeoutAfter: Duration = .seconds(60)

    /// What the clock says, given what has happened so far.
    public enum Tick: Sendable, Equatable {
        /// Nothing to change on screen.
        case keepWatching
        /// An unplug has been waiting thirty seconds for its cable to return.
        case nudge
        /// Sixty seconds of watching, and nothing moved.
        case timedOut
    }

    /// - Parameters:
    ///   - watchingFor: how long the watch has been running.
    ///   - unpluggedFor: how long an unplug has been waiting for its replug,
    ///     or `nil` when no unplug has landed. An unplug is already a usable
    ///     answer, so the sixty-second timeout stops applying once one has.
    public static func tick(watchingFor: Duration, unpluggedFor: Duration?) -> Tick {
        if let unpluggedFor {
            return unpluggedFor >= nudgeAfter ? .nudge : .keepWatching
        }
        return watchingFor >= timeoutAfter ? .timedOut : .keepWatching
    }
}
