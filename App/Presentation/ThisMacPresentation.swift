//
//  ThisMacPresentation.swift
//
//  The three read-only rows of the hub's `This Mac` section, verbatim from
//  docs/UX_SPEC.md §S1.
//

import Foundation
import RDMALinkCore

/// What the RDMA switch is doing, once the boot this Mac is in has been taken
/// into account. `RDMAStatus.onAfterRestart` is one reading with two meanings
/// and this is where they are separated.
enum RDMASwitchState: Sendable, Equatable {
    /// Neither NVRAM route answered. The app says nothing rather than guessing.
    case unobserved
    case off
    case onAfterRestart
    /// R22: on, restarted since, and still no RDMA devices.
    case onWithoutDevices
    case on
}

/// The trailing control a `This Mac` row carries, when it carries one.
enum ThisMacRowAction: Sendable, Equatable {
    /// Opens System Settings › Privacy & Security › Developer Tools.
    case turnItOn
    /// Reveals R22 inline, under the section.
    case tellMeMore
}

/// One row of the `This Mac` section.
struct ThisMacRowModel: Sendable, Equatable, Identifiable {
    var id: String
    var text: LocalizedStringResource
    var action: ThisMacRowAction?
}

enum ThisMacPresentation {
    /// Separates "turned on, restart still owed" from R22's "restarted, and
    /// still no RDMA devices". Pure: the caller supplies the one fact that
    /// needs remembering across launches.
    static func switchState(
        _ status: RDMAStatus,
        hasRestartedSinceSwitchOn: Bool
    ) -> RDMASwitchState {
        switch status {
        case .unknown: .unobserved
        case .off: .off
        case .onAfterRestart: hasRestartedSinceSwitchOn ? .onWithoutDevices : .onAfterRestart
        case .on: .on
        }
    }

    /// The RDMA row, or `nil` while the switch has not been read. The app
    /// never states a status it has not observed (§1.3 rule 10), and the spec
    /// has no copy for "unknown".
    static func rdmaRow(_ state: RDMASwitchState) -> ThisMacRowModel? {
        switch state {
        case .unobserved:
            return nil
        case .off:
            return ThisMacRowModel(
                id: "rdma",
                text: "RDMA over Thunderbolt — Off. Turn it on to finish.",
                action: .turnItOn
            )
        case .onAfterRestart:
            return ThisMacRowModel(id: "rdma", text: "RDMA over Thunderbolt — On after you restart")
        case .onWithoutDevices:
            return ThisMacRowModel(
                id: "rdma",
                text: "RDMA over Thunderbolt — On, but no RDMA devices appeared",
                action: .tellMeMore
            )
        case .on:
            return ThisMacRowModel(id: "rdma", text: "RDMA over Thunderbolt — On")
        }
    }

    /// Bridge membership across every receptacle on this Mac.
    ///
    /// §S1 gives three sentences and this row prints one of those three. "Two
    /// bridges, one of them unused" needs to know a bridge is switched off,
    /// which `BridgeMembership.isUp` says, so it is printed exactly when it is
    /// true. Every other shape — three bridges, or two that are both up —
    /// falls back to the member count, which is true whatever the bridges are
    /// doing, rather than to a "\(n) bridges" sentence the spec never wrote.
    ///
    /// **Owed from the spec owner:** a singular of "Four ports are members".
    /// "One ports are members" is not a sentence, so the row inflects the one
    /// the spec gives rather than dropping the row on the commonest Mac there
    /// is.
    static func bridgeRow(_ ports: [PortSnapshot]) -> ThisMacRowModel {
        let bridges = distinctBridges(ports)
        let members = ports.count { !$0.bridges.isEmpty }
        let text: LocalizedStringResource

        if bridges.isEmpty {
            text = "Thunderbolt Bridge — Not in use"
        } else if bridges.count == 2, bridges.count(where: { !$0.isUp }) == 1 {
            text = "Thunderbolt Bridge — Two bridges, one of them unused"
        } else if members == 1 {
            text = "Thunderbolt Bridge — One port is a member"
        } else {
            text = "Thunderbolt Bridge — \(spelledOut(members)) ports are members"
        }
        return ThisMacRowModel(id: "bridge", text: text)
    }

    /// `Ports ready for RDMA — None yet` or the position names, in the physical
    /// order the rest of the app uses.
    static func readyRow(_ ports: [PortSnapshot]) -> ThisMacRowModel {
        let names = ports.ready.map(\.port.positionName)
        guard !names.isEmpty else {
            return ThisMacRowModel(id: "ready", text: "Ports ready for RDMA — None yet")
        }
        return ThisMacRowModel(
            id: "ready",
            text: "Ports ready for RDMA — \(names.formatted(.list(type: .and)))"
        )
    }

    /// Every kernel bridge any receptacle on this Mac belongs to, once each.
    static func distinctBridges(_ ports: [PortSnapshot]) -> [ThunderboltPort.BridgeMembership] {
        var seen: Set<String> = []
        var result: [ThunderboltPort.BridgeMembership] = []
        for bridge in ports.flatMap(\.bridges) where seen.insert(bridge.name).inserted {
            result.append(bridge)
        }
        return result
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
