//
//  BurstGate.swift
//
//  UX_SPEC §S6 and §S10: a write is never cut off. While a burst runs —
//  S6's set-up, or a Restore, Return to Bridge or Restore All checklist —
//  quitting waits until the last write lands, and then quits.
//
//  The burst is synchronous and runs on a thread of its own (OperationHost),
//  and macOS asks whether to quit on the main thread, so the count lives
//  behind a lock rather than on an actor: the answer has to be right at the
//  moment it is asked, not one hop later. `OperationHost` opens the gate the
//  moment the credential is in hand — before any write — and closes it when
//  the session ends, however the burst ended.
//
//  While only macOS's password dialog is up the gate is shut: nothing has been
//  written, so quitting then cancels the run as it always did.
//
//  Why `.terminateLater` and not a refusal: the burst is bounded (Core gives
//  itself twenty seconds of a thirty-second credential), the checklist is
//  already on screen as the feedback, and a quit that is refused outright is a
//  control that looks live and does nothing. AppKit runs the run loop in its
//  modal-panel mode until the reply, and the main queue is serviced in that
//  mode, so the reply this posts — and the checklist's own updates — still
//  arrive. **Verified by reasoning and by script/test_presentation.sh's
//  state-machine test only; never by running a write.**
//

import AppKit
import Synchronization

final class BurstGate: Sendable {
    /// The one the app's bursts report to (`OperationHost`), and the one
    /// the app delegate asks.
    static let shared = BurstGate()

    private struct State {
        /// Bursts under way. More than one is possible in principle — a
        /// sheet's and S6's never overlap on screen, but the gate does not
        /// rely on that.
        var running = 0
        /// A quit was asked for while one ran, and has been told "later".
        var owesReply = false
    }

    private let state = Mutex(State())
    /// How the owed answer is delivered. The app's is AppKit's own; a test
    /// hands in its own and counts.
    private let reply: @Sendable (Bool) -> Void

    init(reply: @escaping @Sendable (Bool) -> Void = BurstGate.replyToAppKit) {
        self.reply = reply
    }

    /// AppKit wants the answer on the main thread. The main actor runs on the
    /// main queue, which AppKit keeps servicing while it waits for this.
    static let replyToAppKit: @Sendable (Bool) -> Void = { shouldTerminate in
        Task { @MainActor in
            NSApplication.shared.reply(toApplicationShouldTerminate: shouldTerminate)
        }
    }

    /// The credential is in hand and the burst is about to write. Any thread.
    func begin() {
        state.withLock { $0.running += 1 }
    }

    /// The session has ended — every write landed, or was put back, or the
    /// burst threw. Any thread. A quit that was waiting on it goes ahead.
    func end() {
        let quitNow = state.withLock { state -> Bool in
            state.running = max(state.running - 1, 0)
            guard state.running == 0, state.owesReply else { return false }
            state.owesReply = false
            return true
        }
        if quitNow { reply(true) }
    }

    /// Whether a burst is writing right now.
    var isRunning: Bool { state.withLock { $0.running > 0 } }

    /// `NSApplicationDelegate.applicationShouldTerminate(_:)`'s answer: now,
    /// or later — once the last burst lands, when `end()` replies.
    func terminateReply() -> NSApplication.TerminateReply {
        state.withLock { state in
            guard state.running > 0 else { return .terminateNow }
            state.owesReply = true
            return .terminateLater
        }
    }
}

/// The app delegate SwiftUI adapts (RDMALinkApp): it answers one question.
final class RDMALinkAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        BurstGate.shared.terminateReply()
    }
}
