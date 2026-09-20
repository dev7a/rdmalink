//
//  PortPresentation.swift
//
//  Every string and symbol a port row draws, derived from one
//  `ThunderboltPort`. Pure, value-typed and free of SwiftUI layout, so the
//  row view stays a renderer and the copy stays checkable against
//  docs/UX_SPEC.md §S1 and §3.3.
//

import Foundation
import RDMALinkCore

struct PortRowPresentation: Sendable, Identifiable {
    let id: String
    /// SF Symbol from UX_SPEC §3.3.
    let symbol: String
    /// USB-only receptacles draw their symbol in `.tertiary` (§3.3).
    let usesTertiarySymbol: Bool
    /// The physical position name, already localized by Core (§4.7).
    let positionName: String
    let state: LocalizedStringResource
    /// `nil` on USB-only receptacles, which are in no bridge by definition.
    let membership: LocalizedStringResource?
    /// The BSD name, shown only when `Show technical names` is on.
    let technicalName: String
    let accessibilityLabel: String

    init(port: ThunderboltPort) {
        let state = Self.state(of: port)
        let membership = Self.membership(of: port)
        self.id = port.id
        self.symbol = Self.symbol(of: port)
        self.usesTertiarySymbol = !port.isThunderbolt
        self.positionName = port.positionName
        self.state = state
        self.membership = membership
        self.technicalName = port.bsdName
        self.accessibilityLabel = Self.accessibilityLabel(
            of: port, state: state, membership: membership
        )
    }

    private static func symbol(of port: ThunderboltPort) -> String {
        guard port.isThunderbolt else { return "cable.connector.horizontal" }
        switch port.link {
        case .empty: return "circle.dashed"
        case .device: return "cable.connector"
        case .macLinkComingUp: return "bolt.horizontal.circle"
        case .macLinked: return "bolt.horizontal.circle.fill"
        }
    }

    private static func state(of port: ThunderboltPort) -> LocalizedStringResource {
        guard port.isThunderbolt else { return "USB only — this one isn't Thunderbolt" }
        switch port.link {
        case .empty: return "Nothing plugged in"
        case .device: return "A device is connected — not a Mac"
        case .macLinkComingUp: return "Another Mac is here. The link is still coming up."
        case .macLinked: return "Linked to another Mac"
        }
    }

    /// §S1 gives "In the Thunderbolt Bridge", "Not in any bridge" and
    /// "In two bridges, including one that isn't in use".
    ///
    /// The third is not used verbatim: `ThunderboltPort.bridges` carries BSD
    /// names only, so nothing here has observed that any bridge is unused, and
    /// the count is whatever the kernel reports — three bridges are no harder
    /// to make in Manage Virtual Interfaces than two. Stating "two", or
    /// "one that isn't in use", would be a claim the app has not observed
    /// (§1.3 rule 10). Carrying each bridge's liveness through from Core is a
    /// change to the `ThunderboltPort.bridges` contract and is owed the spec
    /// owner; until then the count is stated and nothing else is.
    private static func membership(of port: ThunderboltPort) -> LocalizedStringResource? {
        guard port.isThunderbolt else { return nil }
        let count = Set(port.bridges).count
        switch count {
        case 0: return "Not in any bridge"
        case 1: return "In the Thunderbolt Bridge"
        default:
            let spelled = ThisMacPresentation.spelledOut(count, capitalized: false)
            return "In \(spelled) bridges"
        }
    }

    private static func accessibilityLabel(
        of port: ThunderboltPort,
        state: LocalizedStringResource,
        membership: LocalizedStringResource?
    ) -> String {
        let stateText = String(localized: state)
        guard let membership else {
            let usb: String.LocalizationValue = "\(port.positionName). USB port. \(stateText)."
            return String(localized: usb)
        }
        let membershipText = String(localized: membership)
        let thunderbolt: String.LocalizationValue =
            "\(port.positionName). Thunderbolt port. \(stateText). \(membershipText)."
        return String(localized: thunderbolt)
    }
}

/// One face of the Mac and the receptacles on it, in physical order.
struct PortGroup: Sendable, Identifiable {
    let id: String
    let header: LocalizedStringResource
    let ports: [ThunderboltPort]
}

enum PortGrouping {
    /// Groups by face without reordering: faces come out in the order their
    /// first port appears, and ports keep the order Core reported (§2.3).
    static func groups(for ports: [ThunderboltPort]) -> [PortGroup] {
        var order: [PortFace?] = []
        var buckets: [PortFace?: [ThunderboltPort]] = [:]
        for port in ports {
            if buckets[port.face] == nil { order.append(port.face) }
            buckets[port.face, default: []].append(port)
        }
        return order.map { face in
            PortGroup(
                id: face?.rawValue ?? "unspecified",
                header: header(for: face),
                ports: buckets[face] ?? []
            )
        }
    }

    private static func header(for face: PortFace?) -> LocalizedStringResource {
        switch face {
        case .back: "Back"
        case .front: "Front"
        case .left: "Left side"
        case .right: "Right side"
        case nil: "Thunderbolt ports"
        }
    }
}
