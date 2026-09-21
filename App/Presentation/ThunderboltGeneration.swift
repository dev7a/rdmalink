//
//  ThunderboltGeneration.swift
//
//  Which Thunderbolt this Mac's ports are, which is the one fact R23 turns on.
//
//  CONTRACT NOTE — this belongs in Core. `HardwareModel` already carries the
//  chassis catalogue and is the only place in the app that knows what a
//  `hw.model` identifier means; a second table here is a mirror of it. The
//  proposed addition to ARCHITECTURE.md's Core contracts is:
//
//      public enum ThunderboltGeneration: Sendable { case four, five, unknown }
//      extension HardwareModel { public var thunderboltGeneration: ThunderboltGeneration }
//
//  Until that lands, this is the app's one table and it is deliberately short:
//  an identifier that is not listed reads `unknown`, and `unknown` never shows
//  R23. Telling somebody their Thunderbolt 5 Mac has nothing to configure would
//  be the worst wrong answer the app could give, so the table only ever speaks
//  where it is certain (UX_SPEC §1.3 rule 10).
//

import Foundation
import RDMALinkCore

enum ThunderboltGeneration: Sendable, Equatable {
    case four
    case five
    /// Not in the table. The app says nothing about the generation and the hub
    /// behaves normally.
    case unknown
}

extension HardwareModel {
    /// The generation of this Mac's Thunderbolt ports, as far as the catalogue
    /// will say.
    var thunderboltGeneration: ThunderboltGeneration {
        Self.thunderboltGenerations[identifier] ?? .unknown
    }

    /// True only when the catalogue has said so. R23 is a read-only mode, not
    /// a guess.
    var isThunderbolt4: Bool { thunderboltGeneration == .four }

    /// Keyed on the same identifiers `HardwareModel.catalog` lists, and on no
    /// others. Every row here is a machine whose published port spec is
    /// unambiguous; anything else is left out rather than guessed at.
    private static let thunderboltGenerations: [String: ThunderboltGeneration] = [
        // Mac Studio — both configurations ship Thunderbolt 5.
        "Mac15,14": .five,   // M3 Ultra, verified on this hardware
        "Mac16,9": .five,    // M4 Max
        // Mac mini — the base M4 is Thunderbolt 4, the M4 Pro is Thunderbolt 5.
        "Mac16,10": .four,   // M4
        "Mac16,11": .five,   // M4 Pro
        // MacBook Pro 14" — the base M4 is Thunderbolt 4.
        "Mac16,1": .four,    // M4
        // MacBook Pro 14"/16" — M4 Pro and M4 Max are Thunderbolt 5.
        "Mac16,5": .five,
        "Mac16,6": .five,
        "Mac16,7": .five,
        "Mac16,8": .five,
        // MacBook Pro 14" M5 Max — verified on the rig 2026-09-20:
        // `system_profiler SPThunderboltDataType` reports 80 Gb/s buses.
        "Mac17,7": .five,
    ]
}
