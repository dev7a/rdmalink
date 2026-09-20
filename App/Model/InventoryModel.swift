//
//  InventoryModel.swift
//
//  The window's one source of truth about this Mac. It reads RDMALinkCore on
//  a background task, never on the main actor, and re-reads on Check Again and
//  on every wake-up the Core link watcher sends.
//

import Foundation
import Observation
import RDMALinkCore

@MainActor
@Observable
final class InventoryModel {
    /// What the working area is showing. `probing` is S0, `ready` is the hub,
    /// `noThunderboltHardware` is refusal R24.
    enum Phase: Sendable, Equatable {
        case probing
        case ready
        case noThunderboltHardware
    }

    private(set) var phase: Phase = .probing

    /// Set when the first probe passes three seconds, so S0 swaps its body line.
    private(set) var isSlowProbe = false

    private(set) var hardware: HardwareModel?
    private(set) var ports: [ThunderboltPort] = []
    private(set) var rdma: RDMAStatus = .unknown

    /// Why the last read refused, when it did. R24's `Copy Details` needs it,
    /// and it is the difference between "no Thunderbolt hardware" and "the
    /// read didn't answer" — which the app must never conflate.
    private(set) var lastReadFailure: String?

    /// The Mac's own sharing name, the first half of the window subtitle.
    private(set) var sharingName = ""

    private var slowProbeTimer: Task<Void, Never>?

    /// `Studio — Mac Studio (M3 Ultra)`, or empty until the model is known.
    var windowSubtitle: String {
        guard let hardware else { return "" }
        let subtitle: String.LocalizationValue =
            "\(sharingName) — \(hardware.marketingName) (\(hardware.chip))"
        return String(localized: subtitle)
    }

    /// How long to wait before looking again when there is nothing to watch.
    /// UX_SPEC §7 promises "a quiet one-second state diff runs underneath".
    private static let retryInterval = Duration.seconds(1)

    /// One full read, then one port read per link change for as long as the
    /// window lives. Cancelling the calling task unsubscribes the watcher.
    ///
    /// Nothing ends this loop but cancellation. An empty port list is a state
    /// to look again from, not a reason to stop: `.task` runs this once per
    /// view lifetime, so returning here would leave the window with no live
    /// updates for good and `Check Again` could not bring them back.
    func start() async {
        await refresh()
        while !Task.isCancelled {
            let watched = ports.map(\.bsdName)
            guard !watched.isEmpty else {
                try? await Task.sleep(for: Self.retryInterval)
                await refreshPorts()
                continue
            }
            for await _ in LinkWatcher(bsdNames: watched).changes() {
                await refreshPorts()
                // A port appearing or leaving changes what there is to
                // subscribe to, so the stream is rebuilt rather than patched.
                if ports.map(\.bsdName) != watched { break }
            }
        }
    }

    /// The full probe: hardware, ports, and the RDMA switch. `Check Again`.
    func refresh() async {
        beginSlowProbeWatch()
        let snapshot = await Task.detached(priority: .userInitiated) { Probe.everything() }.value
        endSlowProbeWatch()

        hardware = snapshot.hardware
        rdma = snapshot.rdma
        sharingName = snapshot.sharingName
        apply(ports: snapshot.ports, failure: snapshot.failure)
    }

    /// The cheap re-read a link event wants: ports only. The RDMA switch needs
    /// a restart to change, so it is not worth an `ibv_devices` every second.
    private func refreshPorts() async {
        guard let archetype = hardware?.archetype else { return }
        let read = await Task.detached(priority: .utility) { Probe.ports(archetype: archetype) }.value
        apply(ports: read.ports, failure: read.failure)
    }

    /// - Parameter ports: `nil` when the read itself refused, which is not the
    ///   same fact as "this Mac has no Thunderbolt ports". R24 says macOS is
    ///   reporting no Thunderbolt controllers, and the app never states
    ///   something it has not observed (UX_SPEC §1.3 rule 10) — so a refused
    ///   read keeps the last hub it did observe and waits for the next tick.
    private func apply(ports: [ThunderboltPort]?, failure: String?) {
        lastReadFailure = failure
        guard let ports else { return }
        self.ports = ports
        phase = ports.isEmpty ? .noThunderboltHardware : .ready
    }

    private func beginSlowProbeWatch() {
        slowProbeTimer?.cancel()
        slowProbeTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.isSlowProbe = true
        }
    }

    private func endSlowProbeWatch() {
        slowProbeTimer?.cancel()
        slowProbeTimer = nil
        isSlowProbe = false
    }
}

/// The read side of RDMALinkCore, off the main actor.
///
/// Every read goes through Core's `Inventory` aggregate, which is where the
/// hardware read and the `ifconfig` read meet. The app does no merging of its
/// own; it only decides what to show when a read refuses.
private enum Probe {
    /// `ports` is `nil` when the read refused, and `[]` only when macOS really
    /// did report no Thunderbolt-IP ports. Core's `Inventory.read()` throws
    /// rather than degrading precisely so this distinction survives; erasing it
    /// here would show a healthy Mac the R24 hardware refusal.
    struct Snapshot: Sendable {
        var hardware: HardwareModel
        var ports: [ThunderboltPort]?
        var rdma: RDMAStatus
        var sharingName: String
        var failure: String?
    }

    /// A port read, or the reason there wasn't one.
    struct PortRead: Sendable {
        var ports: [ThunderboltPort]?
        var failure: String?
    }

    static func everything() -> Snapshot {
        do {
            let inventory = try Inventory.read()
            return Snapshot(
                hardware: inventory.model,
                ports: inventory.ports,
                rdma: inventory.rdma,
                sharingName: sharingName(),
                failure: nil
            )
        } catch {
            // The registry or `ifconfig` refused. That is not "no Thunderbolt
            // hardware": the switch is left `unknown` and the ports unclaimed.
            return Snapshot(
                hardware: HardwareModel.read(), ports: nil, rdma: .unknown,
                sharingName: sharingName(), failure: "\(error)"
            )
        }
    }

    /// Receptacles with their kernel bridge membership and link-local
    /// addresses, in physical order. An empty result is R24; a `nil` one is a
    /// read that refused, and says nothing about the hardware either way.
    static func ports(archetype: Archetype) -> PortRead {
        do {
            return PortRead(ports: try Inventory.readPorts(archetype: archetype), failure: nil)
        } catch {
            return PortRead(ports: nil, failure: "\(error)")
        }
    }

    private static func sharingName() -> String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }
}
