import Foundation
import Testing
@testable import RDMALinkCore

@Suite("Returning a standalone port to the bridge")
struct OperationsReturnToBridgeTests {

    private static let foreign = NetworkServiceInfo(
        serviceID: "FOREIGN", name: "Thunderbolt 6", interfaceBSDName: "en6",
        isEnabled: true, ipv4: Fixtures.ipv4Off, ipv6: Fixtures.ipv6LinkLocal)

    private static let soleBridge = BridgeSPI.Membership(
        bsdName: "bridge0", displayName: nil, members: ["en5"])
    private static let thunderboltBridge = BridgeSPI.Membership(
        bsdName: "bridge0", displayName: "Thunderbolt Bridge", members: ["en5"])
    private static let otherBridge = BridgeSPI.Membership(
        bsdName: "bridge4", displayName: "Docker", members: ["en9"])

    @Test("No bridge at all: nothing is written, and RDMALink never makes one")
    func refusesWithNoBridge() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let world = Fixtures.world(ifconfig: Fixtures.standalone,
                                   services: [Self.foreign], bridges: [])
        let plan = ReturnToBridge(port: Fixtures.port).preview(world: world)
        #expect(plan.refusal?.code == .noBridgeToReturnTo)
        #expect(plan.refusal?.headline == "There's no Thunderbolt Bridge to return it to")
        #expect(plan.buttonTitle == nil)

        let writer = FakeWriter()
        #expect {
            try ReturnToBridge(port: Fixtures.port).perform(
                writer: writer, world: world,
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { ($0 as? Refusal)?.code == .noBridgeToReturnTo }
        #expect(writer.calls == [.lock], "no write of any kind")
    }

    @Test("One bridge: that is the one, whatever it is called")
    func choosesTheOnlyBridge() throws {
        let plan = ReturnToBridge(port: Fixtures.port).preview(
            world: Fixtures.world(ifconfig: Fixtures.standalone,
                                  services: [Self.foreign], bridges: [Self.soleBridge]))
        #expect(plan.bridgeBSDName == "bridge0")
        #expect(plan.bridgeName == "bridge0")
        #expect(plan.buttonTitle == "Return to Bridge")
    }

    @Test("Two bridges: the one named Thunderbolt Bridge wins")
    func choosesTheNamedBridge() throws {
        let plan = ReturnToBridge(port: Fixtures.port).preview(
            world: Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.foreign],
                                  bridges: [Self.otherBridge, Self.thunderboltBridge]))
        #expect(plan.bridgeBSDName == "bridge0")
        #expect(plan.bridgeName == "Thunderbolt Bridge")
    }

    @Test("Two bridges and neither is the Thunderbolt one: RDMALink won't choose")
    func refusesAnAmbiguousChoice() throws {
        let plan = ReturnToBridge(port: Fixtures.port).preview(
            world: Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.foreign],
                                  bridges: [Self.soleBridge, Self.otherBridge]))
        #expect(plan.refusal?.code == .noBridgeToReturnTo)
        #expect(plan.bridgeBSDName == nil)
    }

    @Test("The note is written first, then the service goes, then the member joins")
    func runsInTheSpecOrder() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.presentServiceIDs = ["FOREIGN"]
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        var noteWasThere = false
        writer.intercept = { call in
            if case .deleteService = call {
                noteWasThere = (try? store.load(port: "en6")) != nil
            }
            return nil
        }
        let log = ProgressLog()
        let result = try ReturnToBridge(port: Fixtures.port).perform(
            writer: writer,
            world: Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.foreign],
                                  bridges: [Self.thunderboltBridge]),
            environment: Fixtures.environment(store: store), progress: log.record)

        #expect(noteWasThere, "§7.5 step 1: the note comes first")
        #expect(writer.calls == [
            .lock,
            .deleteService(identifier: "FOREIGN", expecting: "en6"),
            .addMember(port: "en6", bridge: "bridge0", position: nil),
            .commitAndApply,
        ])
        #expect(result.deletedService == "Thunderbolt 6")
        #expect(result.successHeadline == "Back, far left is in Thunderbolt Bridge")
        #expect(result.successBody.contains("Set It Up Again is one click away"))

        // The note records what was found, so the port can be set up again.
        let note = try store.load(port: "en6")
        #expect(note.existingService?.identifier == "FOREIGN")
        #expect(note.bridges.isEmpty)
    }

    @Test("The sheet says what §S10's foreign-port form says")
    func showsTheForeignSheet() throws {
        let plan = ReturnToBridge(port: Fixtures.port).preview(
            world: Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.foreign],
                                  bridges: [Self.thunderboltBridge]))
        #expect(plan.headline == "Return Back, far left to Thunderbolt Bridge?")
        #expect(plan.body.contains("it can do the ordinary thing"))
        #expect(plan.rows[0] == "Add the port to Thunderbolt Bridge")
        #expect(plan.rows[1] == """
            Delete the service Thunderbolt 6 — RDMALink didn't make this one, \
            and a bridge member can't keep its own service
            """)
        #expect(plan.rows[2] == "Check that it really is in the bridge")
        #expect(plan.rows[3] == "Leave every other setting alone")
    }

    @Test("R20: the note is kept when the bridge doesn't list it")
    func keepsTheNoteOnAMiss() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.presentServiceIDs = ["FOREIGN"]
        writer.canReapplyConfiguration = false
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.standalone) }
        #expect {
            try ReturnToBridge(port: Fixtures.port).perform(
                writer: writer,
                world: Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.foreign],
                                      bridges: [Self.thunderboltBridge]),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { ($0 as? Refusal)?.code == .notBackInBridge }
        #expect((try? store.load(port: "en6")) != nil)
    }
}

@Suite("Adopting a port, and letting one go")
struct OperationsAdoptTests {

    private static let readyService = NetworkServiceInfo(
        serviceID: "A", name: "Thunderbolt Bridge Free", interfaceBSDName: "en6",
        isEnabled: true, ipv4: Fixtures.ipv4Off, ipv6: Fixtures.ipv6LinkLocal)

    private static let nearService = NetworkServiceInfo(
        serviceID: "A", name: "Thunderbolt Bridge Free", interfaceBSDName: "en6",
        isEnabled: true, ipv4: Fixtures.ipv4Off, ipv6: Fixtures.ipv6Automatic)

    @Test("A full match is offered Adopt, with the spec's findings")
    func recognisesAFullMatch() throws {
        let plan = AdoptPort(port: Fixtures.port).preview(
            world: Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.readyService]))
        #expect(plan.match == .full)
        #expect(plan.headline == "This port is already set up")
        #expect(plan.findings == [
            AdoptFinding(label: "Service", value: "Thunderbolt Bridge Free"),
            AdoptFinding(label: "IPv4", value: "Off"),
            AdoptFinding(label: "IPv6", value: "Link-local only"),
            AdoptFinding(label: "Bridge membership", value: "None"),
        ])
        #expect(plan.buttonTitles == ["Adopt", "Leave As Is"])
        #expect(plan.notes.contains(AdoptPort.honestyNote))
    }

    @Test("Adopting writes a note, needs no password, and changes nothing")
    func adoptsWithoutTouchingAnything() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let world = Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.readyService])
        let confirmation = try AdoptPort(port: Fixtures.port).perform(
            world: world, environment: Fixtures.environment(store: store))

        #expect(confirmation == "Adopted. Back, far left is in RDMALink's care now.")
        let note = try store.load(port: "en6")
        #expect(note.isAdopted)
        #expect(note.bridges.isEmpty, "RDMALink never saw which bridge it came from")
        #expect(note.createdService == nil, "it didn't create one")
        #expect(note.existingService?.identifier == "A")
    }

    @Test("A near match is never adjusted, and never adopted")
    func refusesToRewriteANearMatch() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let world = Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.nearService])
        let plan = AdoptPort(port: Fixtures.port).preview(world: world)
        #expect(plan.headline == "Nearly a match")
        #expect(!plan.canAdopt)
        #expect(plan.findings.contains(AdoptFinding(label: "IPv6", value: "Automatic")))
        #expect(plan.steps?.contains("Set Configure IPv6 to Link-local only") == true)
        #expect(plan.notes == [AdoptPort.watcherLine])
        #expect(throws: (any Error).self) {
            try AdoptPort(port: Fixtures.port).perform(
                world: world, environment: Fixtures.environment(store: store))
        }
        #expect((try? store.load(port: "en6")) == nil)
    }

    @Test("A port still in a bridge is not a match at all, and gets no button")
    func offersNothingForAPortInABridge() throws {
        let plan = AdoptPort(port: Fixtures.port).preview(
            world: Fixtures.world(ifconfig: Fixtures.inOneBridge, services: [Self.readyService]))
        #expect(plan.match != .full)
        #expect(plan.buttonTitles.isEmpty || plan.canAdopt == false)
    }

    @Test("Stop Managing forgets the note and says exactly that")
    func stopsManaging() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(PortBaseline.adopted(bsdName: "en6", receptacle: 1,
                                            positionName: "Back, far left"))
        let operation = StopManaging(port: Fixtures.port)
        #expect(operation.headline == "Stop looking after Back, far left?")
        let confirmation = try operation.perform(environment: Fixtures.environment(store: store))
        #expect(confirmation == """
            Done. Back, far left is exactly as it was a moment ago — RDMALink \
            is simply no longer keeping an eye on it.
            """)
        #expect((try? store.load(port: "en6")) == nil)
    }
}

@Suite("What is mounted over the link")
struct OperationsMountedVolumeTests {

    private static let mountOutput = """
        /dev/disk3s5 on / (apfs, sealed, local, read-only, journaled)
        //guest@[fe80::6%25en6]/Vault on /Volumes/Vault (smbfs, nodev, nosuid, mounted by alessandro)
        //guest@10.0.0.4/Backup on /Volumes/Backup (smbfs, nodev, nosuid)
        //guest@[fe80::6]/Music on Mac on /Volumes/Music on Mac (smbfs, nodev)
        """

    @Test("A share reached down the port's own link is found by its scope")
    func findsAVolumeByScope() {
        let volumes = MountedVolumes.parse(Self.mountOutput, ports: [Fixtures.port])
        #expect(volumes.map(\.name) == ["Vault", "Music on Mac"])
        #expect(volumes[0].mountPoint == "/Volumes/Vault")
        #expect(volumes[0].portBSDName == "en6")
    }

    @Test("A share on the ordinary network is left alone")
    func ignoresOtherVolumes() {
        let volumes = MountedVolumes.parse(Self.mountOutput, ports: [Fixtures.port])
        #expect(!volumes.contains { $0.name == "Backup" })
        #expect(!volumes.contains { $0.mountPoint == "/" })
    }

    @Test("A port with no addresses and another name matches nothing")
    func matchesNothingForAnotherPort() {
        let other = OperationPort(bsdName: "en7", receptacle: 2,
                                  positionName: "Back, far right")
        #expect(MountedVolumes.parse(Self.mountOutput, ports: [other]).isEmpty)
    }

    @Test("R4 names one volume in the body and the rest in the detail")
    func writesTheSpecCopy() throws {
        let one = [MountedVolume(name: "Vault", mountPoint: "/Volumes/Vault",
                                 source: "s", portBSDName: "en6")]
        let single = try #require(Refusals.nothingMountedOverThunderbolt(one))
        #expect(single.headline == "Something is still using this link")
        #expect(single.body == """
            The volume Vault is mounted over Thunderbolt. Eject it in Finder so \
            nothing gets interrupted, then we'll carry on.
            """)
        #expect(single.detail == nil)

        let two = one + [MountedVolume(name: "Scratch", mountPoint: "/Volumes/Scratch",
                                       source: "s", portBSDName: "en6")]
        let several = try #require(Refusals.nothingMountedOverThunderbolt(two))
        #expect(several.detail == "Vault and Scratch are mounted over Thunderbolt.")
        #expect(Refusals.nothingMountedOverThunderbolt([]) == nil)
    }
}
