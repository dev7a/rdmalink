//
//  ReadyReport.swift
//
//  S7 — Ready (UX_SPEC §S7). The payoff: the `fe80::` address, an honest
//  picture of what is and isn't finished, and a pointer at the other Mac.
//
//  The address is shown in full, always, whatever the "Show technical names"
//  toggle says — §1.3 rule 6's first deliberate exception, because it is the
//  payoff and tools need every character of it.
//

import Foundation
import RDMALinkCore

/// One status row under the value block.
struct ReadyStatusRow: Sendable, Equatable, Identifiable {
    /// Whether the row carries `Turn It On…`.
    enum Action: Sendable, Equatable { case turnItOn }

    var id: String
    var symbol: String
    var isAttention: Bool
    var text: LocalizedStringResource
    var action: Action?
}

/// One configured port's value block. Several ports stack.
struct ReadyValueBlock: Sendable, Equatable, Identifiable {
    var id: String
    var positionName: String
    /// `fe80::a2d1:73b4:9e0c:5f16%en6`, scope suffix included, never truncated.
    var address: String?

    static let label: LocalizedStringResource = "Address for this link"
}

/// S7, ready to draw.
struct ReadyReport: Sendable, Equatable {
    static let footnote: LocalizedStringResource =
        "The part after the % is this port's system name. The tools that take an address need the whole thing, so copy it as it is."

    var headline: LocalizedStringResource
    var body: LocalizedStringResource
    var blocks: [ReadyValueBlock]
    var statusRows: [ReadyStatusRow]

    init(ports: [PortSnapshot], switchState: RDMASwitchState, otherMacIsSetUp: Bool = false) {
        let first = ports.first
        let position = first?.port.positionName ?? ""
        let hasAddress = first?.linkLocalAddress != nil
        let link = first?.port.link ?? .empty

        if hasAddress {
            self.headline = "\(position) is ready"
            self.body = "The port has left the Thunderbolt Bridge and has its own link-local address. It'll carry RDMA as soon as the other Mac is set up the same way."
        } else if link == .macLinkComingUp {
            self.headline = "\(position) is ready"
            self.body = "Another Mac is here and the link is still coming up. The address usually takes a few seconds."
        } else {
            self.headline = "\(position) is ready and waiting"
            self.body = "There's no address yet — one appears the moment another Mac is connected to this port. Leave this window open and you'll see it arrive."
        }

        self.blocks = ports.map {
            ReadyValueBlock(
                id: $0.port.bsdName,
                positionName: $0.port.positionName,
                address: $0.linkLocalAddress)
        }
        self.statusRows = Self.statusRows(switchState: switchState, otherMacIsSetUp: otherMacIsSetUp)
    }

    private static func statusRows(
        switchState: RDMASwitchState, otherMacIsSetUp: Bool
    ) -> [ReadyStatusRow] {
        var rows: [ReadyStatusRow] = []
        switch switchState {
        case .on:
            rows.append(
                ReadyStatusRow(
                    id: "rdma", symbol: "checkmark.circle.fill", isAttention: false,
                    text: "RDMA over Thunderbolt — On"))
            rows.append(
                ReadyStatusRow(
                    id: "device", symbol: "checkmark.circle.fill", isAttention: false,
                    text: "RDMA device — Ready"))
        case .off:
            rows.append(
                ReadyStatusRow(
                    id: "rdma", symbol: "exclamationmark.circle", isAttention: true,
                    text: "RDMA over Thunderbolt — Off. Turn it on and restart to finish.",
                    action: .turnItOn))
        case .onAfterRestart, .onWithoutDevices:
            rows.append(
                ReadyStatusRow(
                    id: "device", symbol: "exclamationmark.circle", isAttention: true,
                    text: "RDMA device — Not here yet. It usually appears after a restart."))
        case .unobserved:
            // §1.3 rule 10: the switch has not been read, so the app says
            // nothing about it rather than guessing at a status row.
            break
        }
        if !otherMacIsSetUp {
            rows.append(
                ReadyStatusRow(
                    id: "other-mac", symbol: "circle.dashed", isAttention: false,
                    text: "The other Mac — Not set up yet"))
        }
        return rows
    }
}
