//
//  ThisMacPresentation.swift
//
//  The three read-only rows of the hub's `This Mac` section, verbatim from
//  docs/UX_SPEC.md §S1.
//

import Foundation
import RDMALinkCore

enum ThisMacPresentation {
    /// The RDMA row, or `nil` while the switch has not been read. The app
    /// never states a status it has not observed (§1.3 rule 10), and the spec
    /// has no copy for "unknown".
    static func rdmaRow(_ status: RDMAStatus) -> LocalizedStringResource? {
        switch status {
        case .unknown:
            return nil
        case .off:
            return "RDMA over Thunderbolt — Off. Turn it on to finish."
        case .onAfterRestart:
            return "RDMA over Thunderbolt — On after you restart"
        case .on(let devices):
            return devices.isEmpty
                ? "RDMA over Thunderbolt — On, but no RDMA devices appeared"
                : "RDMA over Thunderbolt — On"
        }
    }

    /// Bridge membership across every receptacle on this Mac.
    ///
    /// §S1's "Two bridges, one of them unused" is deliberately not used
    /// verbatim. `ThunderboltPort.bridges` carries BSD names only — Core's
    /// merge drops `InterfaceState.isUp`/`isActive` — so the app has observed
    /// no bridge to be unused, and the count is whatever the kernel reports,
    /// which can be three. Both halves of that sentence would be claims the app
    /// has not made (§1.3 rule 10), so the count is stated and nothing else is.
    /// Carrying liveness through is a change to the `ThunderboltPort.bridges`
    /// contract and is owed the spec owner.
    static func bridgeRow(_ ports: [ThunderboltPort]) -> LocalizedStringResource {
        let bridges = Set(ports.flatMap(\.bridges))
        let members = ports.count { !$0.bridges.isEmpty }
        if bridges.count >= 2 {
            return "Thunderbolt Bridge — \(spelledOut(bridges.count)) bridges"
        }
        if members == 0 {
            return "Thunderbolt Bridge — Not in use"
        }
        if members == 1 {
            // Extrapolated: §S1 gives the plural and the empty case only, and
            // "One ports are members" is not a sentence.
            return "Thunderbolt Bridge — One port is a member"
        }
        return "Thunderbolt Bridge — \(spelledOut(members)) ports are members"
    }

    /// `Four`, `Six` — the spec writes these counts in words (§S1).
    static func spelledOut(_ count: Int, capitalized: Bool = true) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = .current
        guard let words = formatter.string(from: NSNumber(value: count)) else {
            return count.formatted()
        }
        guard capitalized else { return words }
        return words.prefix(1).localizedUppercase + words.dropFirst()
    }
}
