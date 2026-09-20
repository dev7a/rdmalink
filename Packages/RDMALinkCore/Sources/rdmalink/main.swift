import Foundation
import RDMALinkCore

// The command-line companion: read-only diagnostics and the ML0 spikes.
//
// Everything here reads. The one subcommand that takes an authorization
// credential — `spike-auth` — is behind an explicit `--i-understand` flag and
// prints what it is about to do first. No subcommand writes network
// configuration, NVRAM or bridge membership; the Core types that can do that
// are never reached from this file.

let arguments = Array(CommandLine.arguments.dropFirst())
let flags = Set(arguments.filter { $0.hasPrefix("--") })
let command = arguments.first { !$0.hasPrefix("-") }

/// One refusal line, plus the spec's own words when it is not satisfied.
func report(_ code: String, _ rule: String, _ refusal: Refusal?, indent: String = "") {
    guard let refusal else {
        print("\(indent)\(code)  satisfied      \(rule)")
        return
    }
    print("\(indent)\(code)  UNSATISFIED    \(refusal.headline)")
    for line in refusal.body.split(separator: "\n", omittingEmptySubsequences: false) {
        print("\(indent)      \(line)")
    }
    if let detail = refusal.detail { print("\(indent)      detail: \(detail)") }
    if !refusal.subjects.isEmpty { print("\(indent)      subjects: \(list(refusal.subjects))") }
}

func describe(_ status: RDMAStatus) -> String {
    switch status {
    case .unknown: "unknown — neither NVRAM nor ibv_devices answered"
    case .off: "off"
    case .onAfterRestart: "on after you restart"
    case let .on(devices): "on · \(devices.count) device\(devices.count == 1 ? "" : "s")"
    }
}

func describe(_ link: LinkState) -> String {
    switch link {
    case .empty: "nothing plugged in"
    case .device: "a device is connected — not a Mac"
    case .macLinkComingUp: "another Mac is here, the link is still coming up"
    case .macLinked: "linked to another Mac"
    }
}

func describe(_ configuration: PortConfiguration) -> String {
    switch configuration {
    case let .unconfigured(bridges):
        bridges.isEmpty ? "no service" : "no service, in \(list(bridges))"
    case let .readyForRDMA(serviceID):
        "ready for RDMA · service \(serviceID)"
    case let .nearMatch(serviceID, differences):
        "near match · service \(serviceID) · "
            + differences.map { String(describing: $0) }.joined(separator: ", ")
    case let .foreign(serviceID, reason):
        "foreign · service \(serviceID) · \(reason)"
    }
}

func describe(_ plan: StandalonePortPlan) -> String {
    switch plan.outcome {
    case .setUp: "set-up"
    case let .adopt(serviceID): "adopt (S9) · service \(serviceID)"
    case .refused: "nothing — \(plan.refusal?.code.rawValue ?? "refused")"
    }
}

func list(_ values: [String]) -> String {
    values.isEmpty ? "none" : values.joined(separator: ", ")
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("rdmalink: \(message)\n".utf8))
    exit(1)
}

/// `inventory` — the whole read: model, RDMA switch, and every receptacle with
/// its position, link state, bridge membership and link-local addresses.
func runInventory() throws {
    let inventory = try Inventory.read()
    let model = inventory.model
    print("\(model.marketingName) · \(model.identifier) · \(model.chip) · \(model.archetype.rawValue)")
    if !model.isRecognized {
        print("  (unrecognized model: ports are numbered, not named)")
    }
    print("RDMA over Thunderbolt: \(describe(inventory.rdma))")
    print("Ports (physical order, \(inventory.ports.count)):")
    for port in inventory.ports {
        print("  \(port.positionName)")
        print("    receptacle \(port.receptacle) · \(port.bsdName) "
            + "· \(port.face?.rawValue ?? "face unknown") "
            + "· \(port.isThunderbolt ? "Thunderbolt" : "USB only")")
        print("    link: \(describe(port.link))")
        print("    bridges: \(list(port.bridges))")
        print("    fe80: \(list(port.linkLocal))")
    }
}

/// `status` — the RDMA switch on its own, which is the one thing the app
/// cannot change and has to hand off to System Settings for.
func runStatus() {
    let status = RDMAStatus.read()
    print("RDMA over Thunderbolt: \(describe(status))")
    print("devices: \(list(status.devices))")
    print("settings link: \(RDMAStatus.developerToolsSettingsLink)")
}

/// `bridge-probe` — which of the private `SCBridgeInterface*` symbols this
/// build of macOS actually resolves. The app decides here whether it can edit
/// bridge membership itself or has to hand off to System Settings.
func runBridgeProbe() {
    let availability = BridgeSPI.availability
    print("SCBridgeInterface SPI: \(availability.resolved.count) of "
        + "\(BridgeSPI.symbolNames.count) symbols resolved")
    for name in BridgeSPI.symbolNames.sorted() {
        let mark = availability.resolved.contains(name) ? "resolved" : "MISSING "
        print("  \(mark)  \(name)")
    }
    print("complete: \(availability.isComplete)")
    print("can edit membership: \(availability.canEditMembership)")
    print("can update configuration: \(availability.canUpdateConfiguration)")
    print("can read active bridges: \(availability.canReadActiveBridges)")
    do {
        let bridges = try BridgeSPI.activeBridges()
        print("live kernel bridges: \(bridges.count)")
        for bridge in bridges {
            print("  \(bridge.bsdName) · \(bridge.displayName ?? "no display name") "
                + "· members \(list(bridge.members))")
        }
    } catch {
        print("live kernel bridges: unavailable — \(error)")
    }
}

/// `refusals` — every refusal this Mac can be measured against right now, each
/// with whether it is satisfied. Pure functions over observed state, exactly as
/// the app evaluates them; nothing here is a simulation.
func runRefusals() throws {
    let inventory = try Inventory.read()
    let snapshot = try InterfaceSnapshot.read()
    let services = try NetworkServices.read()
    let observed = inventory.observedPorts
    let primary = NetworkGlobals.primaryInterfaces()
    let context = inventory.preflightContext(primaryInterfaces: primary)
    print("macOS says the default route is on: \(list(primary))")
    print("")
    let bridgeNames = (try? BridgeSPI.activeBridges())?
        .reduce(into: [String: String]()) { names, bridge in
            names[bridge.bsdName] = bridge.displayName
        } ?? [:]

    report("R1", "Only one Mac is connected", Refusals.oneCableOnly(observed))
    report("R5", "Something other than Thunderbolt reaches this Mac", Refusals.managementPathExists(
        in: snapshot, thunderboltPorts: inventory.thunderboltBSDNames,
        primaryInterfaces: primary
    ))
    report("R14", "The undo note has somewhere to go", Refusals.baselineWritable(
        BaselineStore.defaultDirectory
    ))

    print("")
    print("Per port:")
    for port in inventory.ports {
        let observedPort = port.observed
        print("  \(port.positionName) (\(port.bsdName))")
        report("R9", "Out of every bridge", Refusals.portStillBridged(
            observedPort, in: snapshot, bridgeNames: bridgeNames
        ), indent: "    ")
        let configuration = NetworkServices.classify(
            services: NetworkServices.services(for: port.bsdName, in: services),
            bridges: port.bridges
        )
        if case let .foreign(_, reason) = configuration {
            report("R16", "No setup RDMALink didn't make",
                   Refusals.foreignService(observedPort, reason: reason), indent: "    ")
        } else {
            report("R16", "No setup RDMALink didn't make", nil, indent: "    ")
        }
        print("    configuration: \(describe(configuration))")
        // What the review screen would offer for this port. A port that already
        // carries a service routes to Adopt (UX_SPEC §S4, R27) and never shows
        // a set-up button — there is no path that rewrites a service RDMALink
        // did not create.
        let plan = StandalonePortSetup(port: observedPort).preview(
            snapshot: snapshot, services: services, context: context,
            bridgeNames: bridgeNames)
        print("    offers: \(describe(plan))")
    }
}

/// `spike-auth` — the ML0 authorization spike: take the credential, open the
/// preferences session in dry run, report, and put it back without committing
/// anything. It puts up the system password dialog, so it refuses to run
/// without `--i-understand`.
func runAuthorizationSpike(confirmed: Bool) {
    print("WARNING: this opens the macOS administrator password prompt.")
    print("It takes the \(AuthorizedSession.right) credential, opens the")
    print("preferences session in dry run, and commits nothing.")
    guard confirmed else {
        print("")
        print("Refusing: re-run as `rdmalink spike-auth --i-understand` if that is what you want.")
        exit(2)
    }
    do {
        let session = try AuthorizedSession.begin(mode: .dryRun)
        defer { session.end() }
        print("credential granted · mode \(session.mode)")
        let services = try session.services()
        print("services visible through the authorized session: \(services.count)")
        do {
            try session.lock()
            print("preferences lock: taken")
            session.unlock()
            print("preferences lock: released")
        } catch {
            print("preferences lock: refused — \(error)")
        }
        print("committed: \(session.didCommit)  (dry run never commits)")
    } catch {
        fail("authorization spike failed: \(error)")
    }
}

func printUsage() {
    print("""
    rdmalink \(RDMALinkCore.version) — read-only diagnostics for RDMALink

      inventory      this Mac, its RDMA switch, and every Thunderbolt port
      status         the RDMA over Thunderbolt switch on its own
      bridge-probe   which private SCBridgeInterface symbols resolve here
      refusals       every refusal evaluated against this Mac right now
      spike-auth     the authorization spike (prompts for a password;
                     needs --i-understand)
    """)
}

do {
    switch command {
    case "inventory": try runInventory()
    case "status": runStatus()
    case "bridge-probe": runBridgeProbe()
    case "refusals": try runRefusals()
    case "spike-auth": runAuthorizationSpike(confirmed: flags.contains("--i-understand"))
    case nil, "help", "-h": printUsage()
    case let other?: fail("unknown subcommand: \(other)")
    }
} catch {
    fail("\(error)")
}
