//
//  OperationHost.swift
//
//  The one place in the app where an authorized session is opened, and the one
//  place a write to the network can begin.
//
//  `docs/ARCHITECTURE.md`: the credential `AuthorizationCopyRights` hands back
//  is non-shared and lasts about thirty seconds, so every write of one
//  operation happens in a single burst right after the prompt. RDMALinkCore's
//  operations are therefore **synchronous** — the burst never awaits anything
//  and never pauses for the user — and this runs one off the main actor, on a
//  thread of its own, so the window keeps drawing the checklist while it
//  happens.
//
//  Nothing here decides *what* is written. It takes the credential, hands the
//  session to the operation, and destroys the credential whichever way the
//  operation ended.
//

import Foundation
import RDMALinkCore

enum OperationHost {

    /// Takes the credential, runs the whole burst, destroys the credential.
    ///
    /// The session is created, used and ended inside one detached task, which
    /// is what keeps a type that owns an `AuthorizationRef` and an open
    /// `SCPreferences` on one thread.
    ///
    /// From the moment the credential is in hand until the session ends the
    /// burst holds `BurstGate` open, so quitting waits for the last write to
    /// land (§S6, §S10). While only the password dialog is up it does not:
    /// nothing has been written, and quitting cancels as it always did.
    static func burst<T: Sendable>(
        _ body: @escaping @Sendable (AuthorizedSession) throws -> T
    ) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            try burstSynchronously(body)
        }.value
    }

    /// The same burst, for a caller that is already off the main actor and on
    /// a thread of its own — S6 drives its checklist from a detached task, so
    /// it opens the session there rather than nesting another one.
    static func burstSynchronously<T>(
        _ body: (AuthorizedSession) throws -> T
    ) throws -> T {
        let session = try AuthorizedSession.begin()
        BurstGate.shared.begin()
        defer {
            session.end()
            BurstGate.shared.end()
        }
        return try body(session)
    }

    /// Work that writes only RDMALink's own note and log — adopting a port and
    /// letting one go. No credential is taken, because none is needed (§7.3).
    static func withoutACredential<T: Sendable>(
        _ body: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try body() }.value
    }
}

extension HubActionsModel {
    /// What every operation needs that is not the world and not the port —
    /// once this Mac is known, which every sheet that asks already is.
    var environment: OperationEnvironment? {
        hardware.map(NotesLocation.environment(hardware:))
    }
}
