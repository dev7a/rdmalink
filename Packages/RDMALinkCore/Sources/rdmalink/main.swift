import Foundation
import RDMALinkCore

// The command-line companion: read-only diagnostics, the ML0 spikes, and the
// ML2 operations.
//
// Every subcommand prints its preview and stops there. The three that can
// change this Mac — `setup`, `restore`, `restore-all` and `return-to-bridge` —
// need **both** `--write` and `--i-understand` before they reach a `perform`,
// and they print what they are about to do first. `adopt` and `stop-managing`
// write only RDMALink's own note and never touch the network. Nothing here
// changes NVRAM.

let arguments = Array(CommandLine.arguments.dropFirst())
let flags = Set(arguments.filter { $0.hasPrefix("--") })
/// Everything that is not a flag: the subcommand, then its arguments.
let positional = arguments.filter { !$0.hasPrefix("-") }
let command = positional.first

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

/// One bridge a port is in: the kernel name, what System Settings calls it
/// when the SPI said, and whether the kernel is really running it.
func describe(_ bridge: ThunderboltPort.BridgeMembership) -> String {
    let named = bridge.displayName.map { " (\($0))" } ?? ""
    return "\(bridge.name)\(named) \(bridge.isUp ? "in use" : "not in use")"
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
        print("    bridges: \(list(port.bridges.map(describe)))")
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
    // USB-only receptacles have no interface, no service and no bridge to
    // refuse anything about. Previewing one would be a plan for a hole that
    // cannot carry RDMA.
    for port in inventory.ports where port.isThunderbolt {
        let observedPort = port.observed
        print("  \(port.positionName) (\(port.bsdName))")
        report("R9", "Out of every bridge", Refusals.portStillBridged(
            observedPort, in: snapshot, bridgeNames: bridgeNames
        ), indent: "    ")
        let configuration = NetworkServices.classify(
            services: NetworkServices.services(for: port.bsdName, in: services),
            bridges: port.bridges.map(\.name)
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

/// The port this Mac actually has, by BSD name.
func operationPort(_ bsdName: String, in inventory: Inventory) -> OperationPort {
    guard let port = inventory.ports.first(where: { $0.bsdName == bsdName }) else {
        fail("no port named \(bsdName) on this Mac — run `rdmalink inventory`")
    }
    guard port.isThunderbolt else {
        fail("\(bsdName) is a USB-only receptacle, so there is nothing to configure")
    }
    return OperationPort(port)
}

/// Every write in this tool is behind both flags and prints what it is about
/// to do first. Without them, only the preview runs.
func confirmedWrite(_ what: String) -> Bool {
    guard flags.contains("--write") else { return false }
    guard flags.contains("--i-understand") else {
        print("")
        print("Refusing: `--write` also needs `--i-understand`.")
        exit(2)
    }
    print("")
    print("WARNING: this changes this Mac's network configuration: \(what)")
    print("macOS will ask for an administrator name and password.")
    return true
}

func show(_ refusal: Refusal) {
    print("  \(refusal.code.rawValue)  \(refusal.headline)")
    for line in refusal.body.split(separator: "\n", omittingEmptySubsequences: false) {
        print("      \(line)")
    }
    if let detail = refusal.detail { print("      detail: \(detail)") }
}

/// Prints every checklist row as the burst reports it. A function rather than
/// a stored closure: a top-level `let` in `main.swift` is main-actor isolated,
/// and the burst runs wherever it is called from.
func checklist(_ step: OperationStep, _ state: StepState) {
    switch state {
    case .pending: print("  ·  \(step.pending)")
    case .running: print("  …  \(step.running)")
    case .done: print("  ✓  \(step.done)")
    // §S6's rollback: the checklist reverses with a returning symbol.
    case .reversing: print("  ↩  \(step.pending)")
    }
}

func environment(_ inventory: Inventory) -> OperationEnvironment {
    OperationEnvironment(archetype: inventory.model.archetype)
}

/// `setup <bsd…>` — UX_SPEC §S5's review, and §S6's burst behind the flags.
func runSetUp(_ names: [String]) throws {
    guard !names.isEmpty else { fail("usage: rdmalink setup <bsd> [<bsd>…]") }
    let inventory = try Inventory.read()
    let ports = names.map { operationPort($0, in: inventory) }
    let world = try ObservedWorld.read(ports: ports, archetype: inventory.model.archetype)
    let operation = SetUpPorts(ports: ports)
    let plan = operation.preview(world: world)

    print(SetUpPortsPlan.headline)
    print(SetUpPortsPlan.body)
    if let refusal = plan.refusal {
        print("")
        print("In the way:")
        show(refusal)
    }
    for port in plan.ports {
        print("")
        print("\(port.header)  (\(port.port.bsdName))")
        if let refusal = port.refusal { show(refusal); continue }
        if port.routesToAdopt {
            print("  already set up — this port routes to Adopt, never to set-up")
        }
        for row in port.rows {
            print("  \(row.title): \(row.before) → \(row.after)")
            print("      \(row.body)")
        }
        for warning in port.warnings { print("  warning: \(warning)") }
        print("  technical names:")
        for line in port.technicalNames { print("      \(line)") }
    }
    print("")
    print("button: \(plan.defaultButtonTitle ?? "none — nothing to press")")
    print(SetUpPortsPlan.footnote)

    guard plan.canProceed else { return }
    guard confirmedWrite("takes \(names.joined(separator: ", ")) out of every bridge "
        + "and gives each its own service") else { return }
    let session = try AuthorizedSession.begin(mode: .live)
    defer { session.end() }
    let result = try operation.perform(session: session, environment: environment(inventory),
                                       progress: checklist)
    print(result.completionLine)
    for port in result.ports {
        print("  \(port.positionName): service \(port.createdServiceID ?? "none") · "
            + "left \(list(port.leftBridges)) · "
            + "kernel settled \(port.agreement.settledOnItsOwn ? "on its own" : "after the push") "
            + "in \(port.agreement.reads) reads")
    }
}

/// `restore <bsd>` — UX_SPEC §S10.
func runRestore(_ bsdName: String?) throws {
    guard let bsdName else { fail("usage: rdmalink restore <bsd>") }
    let inventory = try Inventory.read()
    let port = operationPort(bsdName, in: inventory)
    let world = try ObservedWorld.read(ports: [port], archetype: inventory.model.archetype)
    let note = try? BaselineStore().load(port: bsdName)
    let operation = RestorePort(port: port)
    let plan = operation.preview(note: note, world: world)

    print(plan.headline)
    print(plan.body)
    for row in plan.rows { print("  · \(row)") }
    for note in plan.notes { print("  \(note)") }
    if let refusal = plan.refusal {
        print("")
        print("In the way:")
        show(refusal)
        if plan.mayRemoveServiceOnly { print("  offer: Remove My Service Only") }
    }

    guard plan.canProceed else { return }
    guard confirmedWrite("deletes the service RDMALink made on \(bsdName) and puts the "
        + "port back in \(list(plan.bridgesToRejoin))") else { return }
    let session = try AuthorizedSession.begin(mode: .live)
    defer { session.end() }
    let result = try operation.perform(session: session, environment: environment(inventory),
                                       progress: checklist)
    print(result.successHeadline)
    print(result.successBody(bridgeName: plan.bridgesToRejoin.first ?? "Thunderbolt Bridge"))
    print(result.completionLine)
}

/// `restore-all` — every port with a note, one after the other.
func runRestoreAll() throws {
    let inventory = try Inventory.read()
    let store = BaselineStore()
    let names = try store.list()
    guard !names.isEmpty else {
        print("Nothing yet. When RDMALink changes something, it'll be listed here with a way back.")
        return
    }
    // §7.3: an adopted port's only actions are Return to Bridge and Stop
    // Managing — "there's no 'put it back' for an adopted port" — so a restore
    // of every note skips them exactly as the app's own Restore All does,
    // rather than silently un-adopting a port under a summary that says it was
    // put back.
    var skipped: [String] = []
    let ports = names.compactMap { name -> OperationPort? in
        guard let port = inventory.ports.first(where: { $0.bsdName == name }) else { return nil }
        if let note = try? store.load(port: name), RestorePort.describesNothingToUndo(note) {
            skipped.append(port.positionName)
            return nil
        }
        return OperationPort(port)
    }
    for name in skipped { print("  (skipped \(name): its note records nothing to put back)") }
    guard !ports.isEmpty else { return }
    let operation = RestoreAll(ports: ports)
    print(operation.headline)
    print(operation.body)
    for port in ports { print("  · \(port.positionName) (\(port.bsdName))") }

    guard confirmedWrite("puts \(list(ports.map(\.bsdName))) back the way they were")
    else { return }
    let session = try AuthorizedSession.begin(mode: .live)
    defer { session.end() }
    let outcome = operation.perform(session: session, environment: environment(inventory),
                                    progress: checklist)
    for result in outcome.results { print("  done: \(result.positionName)") }
    for problem in outcome.unfinished {
        if let refusal = problem.refusal {
            show(refusal)
        } else {
            // §6.1's shared line for a failure with no number of its own.
            print("  Nothing has been changed.")
            if let details = problem.details { print("      \(details)") }
        }
    }
    if let summary = outcome.summary { print(summary) }
}

/// `return-to-bridge <bsd>` — UX_SPEC §7.5.
func runReturnToBridge(_ bsdName: String?) throws {
    guard let bsdName else { fail("usage: rdmalink return-to-bridge <bsd>") }
    let inventory = try Inventory.read()
    let port = operationPort(bsdName, in: inventory)
    let world = try ObservedWorld.read(ports: [port], archetype: inventory.model.archetype)
    let operation = ReturnToBridge(port: port)
    let plan = operation.preview(world: world)

    print(plan.headline)
    if !plan.body.isEmpty { print(plan.body) }
    for row in plan.rows { print("  · \(row)") }
    if let refusal = plan.refusal {
        print("")
        print("In the way:")
        show(refusal)
    }

    guard plan.canProceed, let bridge = plan.bridgeName else { return }
    guard confirmedWrite("adds \(bsdName) to \(bridge) and deletes its standalone service")
    else { return }
    let session = try AuthorizedSession.begin(mode: .live)
    defer { session.end() }
    let result = try operation.perform(session: session, environment: environment(inventory),
                                       progress: checklist)
    print(result.successHeadline)
    print(result.successBody)
    print(result.completionLine)
}

/// `adopt <bsd>` — UX_SPEC §S9. Writes a note and nothing else.
func runAdopt(_ bsdName: String?) throws {
    guard let bsdName else { fail("usage: rdmalink adopt <bsd>") }
    let inventory = try Inventory.read()
    let port = operationPort(bsdName, in: inventory)
    let world = try ObservedWorld.read(ports: [port], archetype: inventory.model.archetype)
    let operation = AdoptPort(port: port)
    let plan = operation.preview(world: world)

    print(plan.headline)
    if !plan.body.isEmpty { print(plan.body) }
    for finding in plan.findings { print("  \(finding.label) — \(finding.value)") }
    if let steps = plan.steps { print("  steps: \(steps)") }
    for note in plan.notes { print("  \(note)") }
    print("buttons: \(list(plan.buttonTitles))")

    guard plan.canAdopt else { return }
    // Adopting changes nothing on the system and needs no password, so it is
    // behind `--write` for the note alone.
    guard flags.contains("--write") else { return }
    print(try operation.perform(world: world, environment: environment(inventory)))
}

/// `stop-managing <bsd>` — forgets the note and changes nothing else.
func runStopManaging(_ bsdName: String?) throws {
    guard let bsdName else { fail("usage: rdmalink stop-managing <bsd>") }
    let inventory = try Inventory.read()
    let port = operationPort(bsdName, in: inventory)
    let operation = StopManaging(port: port)
    print(operation.headline)
    print(operation.body)
    guard flags.contains("--write") else { return }
    print(try operation.perform(environment: environment(inventory)))
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

    Operations. Each prints its preview and stops there; the ones that change
    the network need both --write and --i-understand.

      setup <bsd…>            take the ports out of every bridge and give each
                              its own service
      restore <bsd>           put a port back the way it was found
      restore-all             every port with an undo note, one at a time
      return-to-bridge <bsd>  put any standalone port back in Thunderbolt Bridge
      adopt <bsd>             keep an eye on a port set up by hand (no password)
      stop-managing <bsd>     forget the note, change nothing (no password)
    """)
}

do {
    switch command {
    case "inventory": try runInventory()
    case "status": runStatus()
    case "bridge-probe": runBridgeProbe()
    case "refusals": try runRefusals()
    case "spike-auth": runAuthorizationSpike(confirmed: flags.contains("--i-understand"))
    case "setup": try runSetUp(positional.dropFirst().map { $0 })
    case "restore": try runRestore(positional.dropFirst().first)
    case "restore-all": try runRestoreAll()
    case "return-to-bridge": try runReturnToBridge(positional.dropFirst().first)
    case "adopt": try runAdopt(positional.dropFirst().first)
    case "stop-managing": try runStopManaging(positional.dropFirst().first)
    case nil, "help", "-h": printUsage()
    case let other?: fail("unknown subcommand: \(other)")
    }
} catch {
    fail("\(error)")
}
