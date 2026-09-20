//
//  Diagnostics.swift
//
//  One payload, two doors: `Copy Details` on a refusal and `Save a Diagnostics
//  File…` in Settings. UX_SPEC §6.1 rule 8 says they are the same text.
//
//  What it contains: the technical names regardless of the "Show technical
//  names" toggle, the model, the chip, the macOS build, the ports, the RDMA
//  status and the failing step with its underlying reason — and nothing else.
//
//  What it deliberately leaves out: this Mac's sharing name. It is often a
//  person's name, §S12 promises "no personal information", and nothing in a
//  diagnostic needs it. The `fe80::` addresses stay in, because they are the
//  one technical string the app shows in full to everybody anyway (§1.3 rule 6)
//  and they are what a reader has to match against the other Mac.
//
//  Not localized: this is a payload for a bug report, not interface copy.
//

import Foundation
import RDMALinkCore

enum Diagnostics {
    static func text(
        hardware: HardwareModel?,
        ports: [PortSnapshot],
        rdma: RDMAStatus,
        switchState: RDMASwitchState,
        failingStep: String?,
        underlyingReason: String?,
        date: Date = Date()
    ) -> String {
        var lines: [String] = []
        lines.append("RDMALink \(appVersion) diagnostics")
        lines.append("Recorded: \(date.formatted(.iso8601))")
        lines.append("")
        if let hardware {
            lines.append("Model: \(hardware.marketingName) (\(hardware.identifier))")
            lines.append("Chip: \(hardware.chip)")
            lines.append("Chassis: \(hardware.archetype.rawValue)")
            // UX_SPEC §4.7 has two ways to recognize a Mac; a bug report has
            // to say which one fired, or that neither did.
            lines.append("Recognized: \(hardware.recognition)")
            lines.append("Thunderbolt: \(generation(hardware))")
        } else {
            lines.append("Model: not read")
        }
        lines.append("macOS build: \(SystemBuild.current)")
        lines.append("RDMA over Thunderbolt: \(rdmaDescription(rdma, state: switchState))")
        lines.append("")
        lines.append("Ports (\(ports.count)), in physical order:")
        if ports.isEmpty {
            lines.append("  none reported")
        } else {
            lines.append(contentsOf: ports.map(describe))
        }
        if let failingStep {
            lines.append("")
            lines.append("Failing step: \(failingStep)")
        }
        if let underlyingReason {
            lines.append("Reason: \(underlyingReason)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A full reading, taken on the spot.
    ///
    /// Settings is a separate window with no probe behind it, so
    /// `Save a Diagnostics File…` reads this Mac once, at the moment the user
    /// asks for it. Blocking: call it off the main actor.
    static func live(date: Date = Date()) -> String {
        do {
            let inventory = try Inventory.read()
            return text(
                hardware: inventory.model,
                ports: PortReading.join(inventory.ports),
                rdma: inventory.rdma,
                switchState: ThisMacPresentation.switchState(
                    inventory.rdma,
                    hasRestartedSinceSwitchOn: RestartWatch.hasRestartedSinceSwitchOn(inventory.rdma)
                ),
                failingStep: nil,
                underlyingReason: nil,
                date: date
            )
        } catch {
            return text(
                hardware: Inventory.readModel(),
                ports: [],
                rdma: .unknown,
                switchState: .unobserved,
                failingStep: "reading this Mac",
                underlyingReason: "\(error)",
                date: date
            )
        }
    }

    private static func describe(_ snapshot: PortSnapshot) -> String {
        let port = snapshot.port
        var fields = [
            // A USB-only receptacle has no interface name; its catalogue id is
            // the only handle there is.
            port.bsdName.isEmpty ? port.id : port.bsdName,
            "receptacle \(port.receptacle)",
            port.positionName,
            port.isThunderbolt ? "thunderbolt" : "usb-only",
            link(port.link),
        ]
        fields.append(
            snapshot.bridges.isEmpty
                ? "bridges: none"
                : "bridges: " + snapshot.bridges
                    .map { "\($0.name)\($0.isUp ? "" : " (down)")" }
                    .joined(separator: ", ")
        )
        if let address = snapshot.linkLocalAddress { fields.append(address) }
        if let serviceName = snapshot.serviceName, !serviceName.isEmpty {
            fields.append("service: \(serviceName)")
        }
        fields.append("configuration: \(configuration(snapshot.configuration))")
        fields.append("note: \(note(snapshot.baseline))")
        return "  " + fields.joined(separator: " | ")
    }

    private static func link(_ state: LinkState) -> String {
        switch state {
        case .empty: "empty"
        case .device: "device attached"
        case .macLinkComingUp: "mac, link coming up"
        case .macLinked: "mac linked"
        }
    }

    private static func configuration(_ value: PortConfiguration?) -> String {
        guard let value else { return "not read" }
        switch value {
        case .unconfigured: return "unconfigured"
        case .readyForRDMA(let serviceID): return "ready for rdma (\(serviceID))"
        case .nearMatch(let serviceID, let differences):
            return "near match (\(serviceID)): \(differences.map(difference).joined(separator: ", "))"
        case .foreign(let serviceID, let reason):
            return "foreign (\(serviceID)): \(reason)"
        }
    }

    private static func difference(_ value: ConfigurationDifference) -> String {
        switch value {
        case .stillInBridge(let name): "still in \(name)"
        case .serviceDisabled: "service disabled"
        case .ipv4NotOff(let method): "ipv4 \(method ?? "unset")"
        case .ipv6NotLinkLocal(let method): "ipv6 \(method ?? "unset")"
        case .ipv6Disabled: "ipv6 disabled"
        case .severalServices(let count): "\(count) services on the interface"
        }
    }

    private static func note(_ baseline: PortBaseline?) -> String {
        guard let baseline else { return "none" }
        return baseline.isAdopted ? "adopted \(baseline.recordedAt.formatted(.iso8601))"
                                  : "set up \(baseline.recordedAt.formatted(.iso8601))"
    }

    private static func rdmaDescription(_ status: RDMAStatus, state: RDMASwitchState) -> String {
        switch state {
        case .unobserved: "not read"
        case .off: "off"
        case .onAfterRestart: "on in nvram, restart owed"
        case .onWithoutDevices: "on in nvram, restarted, no rdma devices"
        case .on: "on, devices: " + status.devices.joined(separator: ", ")
        }
    }

    private static func generation(_ hardware: HardwareModel) -> String {
        switch hardware.thunderboltGeneration {
        case .four: "4"
        case .five: "5"
        case .unknown: "not in the catalogue"
        }
    }

    /// `CFBundleShortVersionString`, so a pasted payload names the build it
    /// came from.
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// The default file name `Save a Diagnostics File…` offers.
    static func suggestedFileName(date: Date = Date()) -> String {
        let stamp = date.formatted(.iso8601.year().month().day())
        return "RDMALink diagnostics \(stamp).txt"
    }
}
