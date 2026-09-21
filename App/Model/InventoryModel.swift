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
    /// and the last two are the only refusals that block the app at launch:
    /// R24 (no Thunderbolt hardware) and R25 (macOS older than 27).
    enum Phase: Sendable, Equatable {
        case probing
        case ready
        case noThunderboltHardware
        case unsupportedSystem
    }

    private(set) var phase: Phase = .probing

    /// Set when the first probe passes three seconds, so S0 swaps its body line.
    private(set) var isSlowProbe = false

    private(set) var hardware: HardwareModel?
    private(set) var ports: [PortSnapshot] = []
    private(set) var rdma: RDMAStatus = .unknown

    /// Why the last read refused, when it did. R24's `Copy Details` needs it,
    /// and it is the difference between "no Thunderbolt hardware" and "the
    /// read didn't answer" — which the app must never conflate.
    private(set) var lastReadFailure: String?

    /// Full probes that landed on "macOS reports no Thunderbolt controllers".
    /// R24 gains a second body line after three of them — user attempts, not
    /// ticks of the one-second diff, which never touches this.
    private(set) var noHardwareAttempts = 0

    /// The Mac's own sharing name, the first half of the window subtitle.
    private(set) var sharingName = ""

    /// True once this Mac has been restarted since RDMALink first saw the RDMA
    /// switch on. Until then "On after you restart" is the honest row; after it,
    /// a still-empty device list is R22 and says so.
    private(set) var hasRestartedSinceSwitchOn = false

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
        guard SystemRequirement.isSatisfied else {
            phase = .unsupportedSystem
            return
        }
        await refresh()
        while !Task.isCancelled {
            let watched = watchableNames
            guard !watched.isEmpty else {
                try? await Task.sleep(for: Self.retryInterval)
                await refreshPorts()
                continue
            }
            for await _ in LinkWatcher(bsdNames: watched).changes() {
                await refreshPorts()
                // A port appearing or leaving changes what there is to
                // subscribe to, so the stream is rebuilt rather than patched.
                if watchableNames != watched { break }
            }
        }
    }

    /// The full probe: hardware, ports, services, notes and the RDMA switch.
    /// This is what `Check Again` runs.
    func refresh() async {
        guard phase != .unsupportedSystem else { return }
        beginSlowProbeWatch()
        // §S0: the window subtitle appears "as soon as the model is known", and
        // the stage draws the right chassis from the first frame. Knowing the
        // model is three `sysctl` calls and one pass over the device tree
        // (§4.7's family-and-layout rule); the Thunderbolt, network and NVRAM
        // reads underneath are the slow part, so identity is published first
        // rather than held back until the whole probe lands.
        let identity = await Task.detached(priority: .userInitiated) { Probe.identity() }.value
        hardware = identity.hardware
        sharingName = identity.sharingName

        let snapshot = await Task.detached(priority: .userInitiated) { Probe.everything() }.value
        endSlowProbeWatch()

        hardware = snapshot.hardware
        sharingName = snapshot.sharingName
        applyRDMA(snapshot.rdma)
        apply(ports: snapshot.ports, failure: snapshot.failure, countsTowardR24: true)
    }

    /// The cheap re-read a link event wants: ports, their services and their
    /// notes. The RDMA switch needs a restart to change, so it is not worth an
    /// `ibv_devices` every second.
    private func refreshPorts() async {
        guard let archetype = hardware?.archetype else { return }
        let read = await Task.detached(priority: .utility) { Probe.ports(archetype: archetype) }.value
        apply(ports: read.ports, failure: read.failure, countsTowardR24: false)
    }

    /// - Parameter ports: `nil` when the read itself refused, which is not the
    ///   same fact as "this Mac has no Thunderbolt ports". R24 says macOS is
    ///   reporting no Thunderbolt controllers, and the app never states
    ///   something it has not observed (UX_SPEC §1.3 rule 10) — so a refused
    ///   read keeps the last hub it did observe and waits for the next tick.
    private func apply(ports: [PortSnapshot]?, failure: String?, countsTowardR24: Bool) {
        lastReadFailure = failure
        guard let ports else { return }
        self.ports = ports
        if ports.isEmpty {
            phase = .noThunderboltHardware
            if countsTowardR24 { noHardwareAttempts += 1 }
        } else {
            phase = .ready
            noHardwareAttempts = 0
        }
    }

    private func applyRDMA(_ status: RDMAStatus) {
        rdma = status
        hasRestartedSinceSwitchOn = RestartWatch.hasRestartedSinceSwitchOn(status)
    }

    /// The BSD names there is anything to subscribe to. USB-only receptacles
    /// have none, and `SCDynamicStore` has nothing to say about them.
    private var watchableNames: [String] {
        ports.map(\.port.bsdName).filter { !$0.isEmpty }
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

/// R25 — RDMALink needs macOS 27.
///
/// The deployment target already says 27.0, so in practice launchd refuses
/// first. The check stays because the spec asks for the screen, and because
/// "the detection itself isn't trustworthy on older systems" is a reason to
/// stop rather than to assume.
enum SystemRequirement {
    static let majorVersion = 27

    static var isSatisfied: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: majorVersion, minorVersion: 0, patchVersion: 0)
        )
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
        var ports: [PortSnapshot]?
        var rdma: RDMAStatus
        var sharingName: String
        var failure: String?
    }

    /// A port read, or the reason there wasn't one.
    struct PortRead: Sendable {
        var ports: [PortSnapshot]?
        var failure: String?
    }

    /// What this Mac is, without waiting for what is plugged into it.
    struct Identity: Sendable {
        var hardware: HardwareModel
        var sharingName: String
    }

    static func identity() -> Identity {
        if let fixture = SnapshotHook.fixture {
            return Identity(hardware: fixture.model, sharingName: sharingName())
        }
        return Identity(hardware: Inventory.readModel(), sharingName: sharingName())
    }

    static func everything() -> Snapshot {
        do {
            // Review hook only; see App/SnapshotHook.swift. A fixture stands
            // in for this Mac's identity and ports and nothing else.
            let inventory = try SnapshotHook.fixture?.inventory ?? Inventory.read()
            return Snapshot(
                hardware: inventory.model,
                ports: PortReading.join(inventory.ports),
                rdma: inventory.rdma,
                sharingName: sharingName(),
                failure: nil
            )
        } catch {
            // The registry or `ifconfig` refused. That is not "no Thunderbolt
            // hardware": the switch is left `unknown` and the ports unclaimed.
            return Snapshot(
                hardware: Inventory.readModel(), ports: nil, rdma: .unknown,
                sharingName: sharingName(), failure: "\(error)"
            )
        }
    }

    /// Receptacles with their kernel bridge membership, their services and the
    /// notes RDMALink has for them, in physical order. An empty result is R24;
    /// a `nil` one is a read that refused, and says nothing about the hardware
    /// either way.
    static func ports(archetype: Archetype) -> PortRead {
        do {
            let ports = try SnapshotHook.fixture?.inventory.ports
                ?? Inventory.readPorts(archetype: archetype)
            return PortRead(ports: PortReading.join(ports), failure: nil)
        } catch {
            return PortRead(ports: nil, failure: "\(error)")
        }
    }

    /// The sharing name from `Host`, which is what System Settings › General ›
    /// Sharing shows. It is the first half of the window subtitle and nothing
    /// else — in particular it never reaches the diagnostics file.
    private static func sharingName() -> String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }
}

/// Joins a Core port with the two things §S1's rows need on top of it: what
/// the stored network configuration says, and whether RDMALink has a note.
enum PortReading {
    static func join(_ ports: [ThunderboltPort]) -> [PortSnapshot] {
        // Nil when the stored configuration could not be opened at all, so the
        // rows fall back to what is plugged in rather than claiming a port is
        // unconfigured on the strength of a read that never happened.
        let services = try? NetworkServices.read()
        let store = NotesLocation.store
        let noted = Set((try? store.list()) ?? [])

        return ports.map { port in
            // A USB-only receptacle has no BSD name because it has no network
            // interface, so nothing that keys on `enN` — services, notes,
            // bridges — can say anything about it, and nothing here pretends to.
            guard port.isThunderbolt, !port.bsdName.isEmpty else {
                return PortSnapshot(port: port, bridges: [], configuration: nil, baseline: nil)
            }
            let onPort = services.map { NetworkServices.services(for: port.bsdName, in: $0) }
            return PortSnapshot(
                port: port,
                bridges: port.bridges,
                configuration: onPort.map {
                    NetworkServices.classify(services: $0, bridges: port.bridges.map(\.name))
                },
                baseline: noted.contains(port.bsdName)
                    ? try? store.load(port: port.bsdName)
                    : nil,
                serviceName: onPort?.first?.name
            )
        }
    }
}
