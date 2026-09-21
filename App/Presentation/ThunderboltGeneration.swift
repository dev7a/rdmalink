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

    /// Keyed on identifiers `HardwareModel.catalog` lists, and on no others.
    /// Every row is transcribed from the port sentence of Apple's "Identify
    /// your … model" page for that identifier (the URLs are on the catalogue),
    /// which names the generation per Model Identifier — "three Thunderbolt 5
    /// ports". A machine whose page does not say is left out rather than
    /// guessed at: the Mac mini (2024) page lists `Mac16,10` and `Mac16,11`
    /// together and never says which is the Thunderbolt 4 M4 and which the
    /// Thunderbolt 5 M4 Pro, so neither is here until one is read on hardware.
    private static let thunderboltGenerations: [String: ThunderboltGeneration] = [
        // Mac Studio (2025) — "Front ports: Two Thunderbolt 5 ports" on the
        // M3 Ultra, and the M4 Max carries the same back four.
        "Mac15,14": .five,   // M3 Ultra, verified on this hardware
        "Mac16,9": .five,    // M4 Max
        // MacBook Pro (14-inch, 2024) M4 — "three Thunderbolt 4 ports".
        "Mac16,1": .four,
        // MacBook Pro (14-inch and 16-inch, 2024) M4 Pro / M4 Max — "three
        // Thunderbolt 5 ports".
        "Mac16,6": .five,
        "Mac16,8": .five,
        "Mac16,5": .five,
        "Mac16,7": .five,
        // MacBook Pro (14-inch, M5), 2025 — "three Thunderbolt 4 ports".
        "Mac17,2": .four,
        // MacBook Pro (14-inch and 16-inch, M5 Pro or M5 Max), 2026 — "three
        // Thunderbolt 5 ports". `Mac17,7` verified on the rig 2026-09-20:
        // `system_profiler SPThunderboltDataType` reports 80 Gb/s buses.
        "Mac17,7": .five,
        "Mac17,9": .five,
        "Mac17,6": .five,
        "Mac17,8": .five,
    ]
}
