import Foundation
import RDMALinkCore

// The command-line companion: read-only diagnostics.
//
// Since ML3 the app is the only thing that writes. Every subcommand here reads
// this Mac and prints — the inventory, the refusals, the change log, or an
// operation's preview — and stops there. Nothing in this tool opens an
// authorized session, changes the network configuration, writes a note, or
// changes NVRAM.

let arguments = Array(CommandLine.arguments.dropFirst())
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
/// when the stored configuration said, whether the kernel is really running
/// it, and which of the two reads saw the membership at all.
func describe(_ bridge: ThunderboltPort.BridgeMembership) -> String {
    let named = bridge.displayName.map { " (\($0))" } ?? ""
    return "\(bridge.name)\(named) \(bridge.isUp ? "in use" : "not in use") "
        + "· seen by: \(bridge.source)"
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

/// Where the notes and the change log the tool reads live: the app's own
/// folder, or the one `RDMALINK_APPLICATION_SUPPORT` names — so a copy of a
/// note or a log can be shown to the tool instead of the real ones.
let applicationDirectory = ProcessInfo.processInfo.environment["RDMALINK_APPLICATION_SUPPORT"]
    .map { URL(fileURLWithPath: $0) } ?? BaselineStore.applicationDirectory
let notesStore = BaselineStore(
    directory: applicationDirectory.appending(path: BaselineStore.notesFolderName))
let changeLog = ChangeLog(url: applicationDirectory.appending(path: ChangeLog.fileName))

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
    // Which of UX_SPEC §4.7's two rules decided the archetype, or neither —
    // on an unrecognized Mac the ports below are numbered, not named.
    print("Recognized: \(model.recognition)")
    print("RDMA over Thunderbolt: \(describe(inventory.rdma))")
    // Bridge membership is two facts, not one: what the kernel is running and
    // what the saved network settings still hold. A port either read lists is
    // a port no service can be created on.
    let stored = inventory.storedBridges
    print("Bridges in the saved network settings (read from \(stored.source)): "
        + "\(stored.bridges.count)")
    for bridge in stored.bridges {
        print("  \(bridge.bsdName) · \(bridge.displayName ?? "no display name") "
            + "· members \(list(bridge.members))")
    }
    print("Ports (physical order, \(inventory.ports.count)):")
    for port in inventory.ports {
        print("  \(port.positionName)")
        print("    receptacle \(port.receptacle) · \(port.bsdName) "
            + "· \(port.face?.rawValue ?? "face unknown") "
            + "· \(port.isThunderbolt ? "Thunderbolt" : "USB only")")
        print("    link: \(describe(port.link))")
        print("    bridges: \(list(port.bridges.map(describe)))")
        print("    fe80: \(list(port.linkLocal))")
        // Thunderbolt domain identity, from private IOThunderboltFamily keys:
        // absent on a USB-only receptacle and on a Mac that does not publish
        // them. The peer domain is what the far end calls itself, so a peer
        // that is one of this Mac's own domains is a cable looped back.
        if port.isThunderbolt {
            print("    own domain: \(port.domainUUID ?? "not published")")
            print("    peer domains: \(list(port.peerDomainUUIDs))")
            print("    looped back to: \(port.loopedBackTo ?? "none")")
        }
    }
}

/// `status` — the RDMA switch on its own, which is the one thing the app
/// cannot change and has to hand off to System Settings for.
func runStatus() {
    let status = RDMAStatus.read()
    let model = Inventory.readModel()
    print("\(model.marketingName) · \(model.identifier) · \(model.chip) · \(model.archetype.rawValue)")
    print("Recognized: \(model.recognition)")
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
    // The other place membership is real, and the one the kernel cannot be
    // asked about.
    let stored = StoredBridges.read()
    print("stored bridges (read from \(stored.source)): \(stored.bridges.count)")
    for bridge in stored.bridges {
        print("  \(bridge.bsdName) · \(bridge.displayName ?? "no display name") "
            + "· members \(list(bridge.members))")
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
    // The stored configuration is the second place membership is real, and
    // R9 is measured against both.
    let stored = inventory.storedBridges
    print("Bridges in the saved network settings (read from \(stored.source)):")
    for bridge in stored.bridges {
        print("  \(bridge.bsdName) · \(bridge.displayName ?? "no display name") "
            + "· members \(list(bridge.members))")
    }
    print("")
    let bridgeNames = stored.bridges.reduce(into: [String: String]()) { names, bridge in
        names[bridge.bsdName] = bridge.displayName
    }

    // R31 first, as every operation asks it: on a Mac neither rule in UX_SPEC
    // §4.7 recognizes nothing below is offered, whatever it measures.
    report("R31", "This Mac is one RDMALink recognizes", Refusals.macRecognized(inventory.model))
    report("R2", "No cable comes back into this Mac", Refusals.loopedBackIntoThisMac(observed))
    report("R1", "Only one Mac is connected", Refusals.oneCableOnly(observed))
    report("R5", "Something other than Thunderbolt reaches this Mac", Refusals.managementPathExists(
        in: snapshot, thunderboltPorts: inventory.thunderboltBSDNames,
        primaryInterfaces: primary
    ))
    report("R14", "The undo note has somewhere to go", Refusals.baselineWritable(
        notesStore.directory
    ))

    print("")
    print("Per port:")
    // USB-only receptacles have no interface, no service and no bridge to
    // refuse anything about. Previewing one would be a plan for a hole that
    // cannot carry RDMA.
    for port in inventory.ports where port.isThunderbolt {
        let observedPort = port.observed
        print("  \(port.positionName) (\(port.bsdName))")
        print("    in bridges: kernel \(list(snapshot.bridges(containing: port.bsdName))) "
            + "· saved settings \(list(stored.names(containing: port.bsdName)))")
        report("R9", "Out of every bridge", Refusals.portStillBridged(
            observedPort, in: snapshot, storedBridges: stored.bridges,
            bridgeNames: bridgeNames
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
            storedBridges: stored.bridges, bridgeNames: bridgeNames)
        print("    offers: \(describe(plan))")
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

func show(_ refusal: Refusal) {
    print("  \(refusal.code.rawValue)  \(refusal.headline)")
    for line in refusal.body.split(separator: "\n", omittingEmptySubsequences: false) {
        print("      \(line)")
    }
    if let detail = refusal.detail { print("      detail: \(detail)") }
}

/// This Mac as the operations see it, with R14 measured against the notes
/// folder the tool is using.
func observe(_ ports: [OperationPort], _ inventory: Inventory) throws -> ObservedWorld {
    try ObservedWorld.read(ports: ports, hardware: inventory.model,
                           notesDirectory: notesStore.directory)
}

/// `setup <bsd…>` — UX_SPEC §S5's review. The preview only: the burst that
/// follows it is the app's, not the tool's.
func runSetUp(_ names: [String]) throws {
    guard !names.isEmpty else { fail("usage: rdmalink setup <bsd> [<bsd>…]") }
    let inventory = try Inventory.read()
    let ports = names.map { operationPort($0, in: inventory) }
    let world = try observe(ports, inventory)
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
}

/// `restore <bsd>` — UX_SPEC §S10.
func runRestore(_ bsdName: String?) throws {
    guard let bsdName else { fail("usage: rdmalink restore <bsd>") }
    let inventory = try Inventory.read()
    let port = operationPort(bsdName, in: inventory)
    let world = try observe([port], inventory)
    let note = try? notesStore.load(port: bsdName)
    let operation = RestorePort(port: port)
    let plan = operation.preview(note: note, world: world)

    print(plan.headline)
    // What the note on disk says, so a note written by an earlier build is
    // shown to load — and a return record shown to be one.
    if let note {
        let returned = note.returnedToBridge.map { "yes, \($0.name) (\($0.bsdName))" } ?? "no"
        print("  note: recorded \(note.recordedAt.formatted(.iso8601)) on \(note.systemBuild) · "
            + "bridges \(list(note.bridges.map(\.bridgeName))) · "
            + "created service \(note.createdServiceIdentifier ?? "none") · "
            + (note.isAdopted ? "adopted · " : "")
            + "return record: \(returned)")
    }
    // A return record is not one Restore… lists (§7.5 step 5); the sheet
    // never reaches this preview for one, so the tool prints §6.2 R30 and
    // then, in its own technical words, what the note is and which actions
    // apply, and stops.
    if let returned = plan.returnedToBridge, let note {
        if let refusal = plan.refusal {
            print("")
            print("In the way:")
            show(refusal)
        }
        print("")
        print("Refusing: \(bsdName)'s note is a return record, not an undo note — Return to "
            + "Bridge put the port in \(returned.name) (\(returned.bsdName)) on "
            + "\(note.recordedAt.formatted(.iso8601)) and kept the note so the port can be "
            + "set up again. There is nothing to restore. Set It Up Again or Forget This "
            + "Port apply in the app; `rdmalink setup \(bsdName)` and "
            + "`rdmalink stop-managing \(bsdName)` preview them.")
        return
    }
    if !plan.body.isEmpty { print(plan.body) }
    for row in plan.rows { print("  · \(row)") }
    for note in plan.notes { print("  \(note)") }
    if let refusal = plan.refusal {
        print("")
        print("In the way:")
        show(refusal)
        if plan.mayRemoveServiceOnly { print("  offer: Remove My Service Only") }
    }
    // §7.3: an adopted note is the same answer in R30's other form, and the
    // tool says in its own words which action is left.
    if let note, note.isAdopted {
        print("")
        print("Refusing: \(bsdName)'s note is an adoption record, not an undo note — RDMALink "
            + "adopted the port as it found it on \(note.recordedAt.formatted(.iso8601)) and "
            + "never saw which bridge it came from. There is nothing to restore; the port keeps "
            + "its setup. Stop Managing applies in the app; `rdmalink stop-managing "
            + "\(bsdName)` previews it.")
        return
    }
}

/// `restore-all` — every port with a note, one after the other.
func runRestoreAll() throws {
    let inventory = try Inventory.read()
    let store = notesStore
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
    // Each port's restore would refuse with R31 before reading its note
    // (§6.2 R31), so the run is said to be in the way here, once.
    if let refusal = Refusals.macRecognized(inventory.model) {
        print("")
        print("In the way:")
        show(refusal)
    }
}

/// `return-to-bridge <bsd>` — UX_SPEC §7.5.
func runReturnToBridge(_ bsdName: String?) throws {
    guard let bsdName else { fail("usage: rdmalink return-to-bridge <bsd>") }
    let inventory = try Inventory.read()
    let port = operationPort(bsdName, in: inventory)
    let world = try observe([port], inventory)
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
}

/// `changes` — the change log as §S11 reads it: every entry, newest first,
/// each with the note a later entry left on it. Read-only.
func runChanges() throws {
    let log = changeLog
    let entries = try log.entries()
    guard !entries.isEmpty else {
        print("Nothing yet. When RDMALink changes something, it'll be listed here with a way back.")
        return
    }
    for entry in entries.reversed() {
        print("\(entry.date.formatted(.iso8601)) — \(entry.positionName) (\(entry.port)) "
            + "· \(entry.kind.rawValue)")
        print("  \(entry.sentence)")
        if let later = ChangeLog.answer(to: entry, in: entries) {
            print("  \(ChangeLog.note(for: entry, answeredBy: later))")
        }
    }
    let unreadable = try log.unreadableLines()
    if unreadable > 0 { print("(\(unreadable) line\(unreadable == 1 ? "" : "s") could not be read)") }
}

/// `adopt <bsd>` — UX_SPEC §S9's preview. Adopting itself is the app's; the
/// tool prints what it would find and stops.
func runAdopt(_ bsdName: String?) throws {
    guard let bsdName else { fail("usage: rdmalink adopt <bsd>") }
    let inventory = try Inventory.read()
    let port = operationPort(bsdName, in: inventory)
    let world = try observe([port], inventory)
    let operation = AdoptPort(port: port)
    let plan = operation.preview(world: world)

    print(plan.headline)
    if !plan.body.isEmpty { print(plan.body) }
    for finding in plan.findings { print("  \(finding.label) — \(finding.value)") }
    if let steps = plan.steps { print("  steps: \(steps)") }
    for note in plan.notes { print("  \(note)") }
    if let refusal = plan.refusal {
        print("")
        print("In the way:")
        show(refusal)
    }
    print("buttons: \(list(plan.buttonTitles))")
}

/// `stop-managing <bsd>` — what forgetting the note would say. The app forgets
/// it; the tool prints and stops.
func runStopManaging(_ bsdName: String?) throws {
    guard let bsdName else { fail("usage: rdmalink stop-managing <bsd>") }
    let inventory = try Inventory.read()
    let port = operationPort(bsdName, in: inventory)
    let operation = StopManaging(port: port)
    print(operation.headline)
    print(operation.body)
    // Forgetting a note is a write, and `perform` refuses it first with R31
    // (§6.2 R31); the preview says so in the same words.
    if let refusal = Refusals.macRecognized(inventory.model) {
        print("")
        print("In the way:")
        show(refusal)
    }
}

func printUsage() {
    print("""
    rdmalink \(RDMALinkCore.version) — read-only diagnostics for RDMALink

    This tool only reads. Since ML3 the app is the only thing that changes this
    Mac: nothing here asks for a password, edits the network configuration, or
    writes a note.

      inventory      this Mac, its RDMA switch, and every Thunderbolt port
      status         the RDMA over Thunderbolt switch on its own
      bridge-probe   which private SCBridgeInterface symbols resolve here
      refusals       every refusal evaluated against this Mac right now
      changes        the change log, newest first

    Operation previews. Each prints what the app would do, or what is in the
    way, and stops there.

      setup <bsd…>            take the ports out of every bridge and give each
                              its own service
      restore <bsd>           put a port back the way it was found
      restore-all             every port with an undo note, one at a time
      return-to-bridge <bsd>  put any standalone port back in Thunderbolt Bridge
      adopt <bsd>             keep an eye on a port set up by hand
      stop-managing <bsd>     forget the note, change nothing

    RDMALINK_APPLICATION_SUPPORT=<dir> reads the notes and the change log under
    <dir> instead of the app's own folder.
    """)
}

do {
    switch command {
    case "inventory": try runInventory()
    case "status": runStatus()
    case "bridge-probe": runBridgeProbe()
    case "refusals": try runRefusals()
    case "setup": try runSetUp(positional.dropFirst().map { $0 })
    case "restore": try runRestore(positional.dropFirst().first)
    case "restore-all": try runRestoreAll()
    case "return-to-bridge": try runReturnToBridge(positional.dropFirst().first)
    case "changes": try runChanges()
    case "adopt": try runAdopt(positional.dropFirst().first)
    case "stop-managing": try runStopManaging(positional.dropFirst().first)
    case nil, "help", "-h": printUsage()
    case let other?: fail("unknown subcommand: \(other)")
    }
} catch {
    fail("\(error)")
}
