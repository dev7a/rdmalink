import Foundation
import Testing
@testable import RDMALinkCore

/// UX_SPEC §6.2 R31: on a Mac neither rule in §4.7 recognizes, every
/// operation refuses **first** — before the note, before the bridge, before
/// any other refusal — and nothing that writes, notes included, runs. "The
/// app hiding the buttons is not the only guard."
@Suite("R31 — RDMALink doesn't recognize this Mac")
struct OperationsUnrecognizedMacTests {

    private static let readyService = NetworkServiceInfo(
        serviceID: "A", name: "Thunderbolt Bridge Free", interfaceBSDName: "en6",
        isEnabled: true, ipv4: Fixtures.ipv4Off, ipv6: Fixtures.ipv6LinkLocal)

    private static let thunderboltBridge = BridgeSPI.Membership(
        bsdName: "bridge0", displayName: "Thunderbolt Bridge", members: ["en5"])

    private static let volume = MountedVolume(
        name: "Archive", mountPoint: "/Volumes/Archive", source: "fe80::9%en6",
        portBSDName: "en6")

    /// The note RDMALink would have written when it set en6 up.
    private static let note = PortBaseline(
        bsdName: "en6", receptacle: 1, positionName: "Back, far left",
        bridges: [BridgeMembership(bridgeName: "bridge0", displayName: "Thunderbolt Bridge",
                                   members: ["en5", "en6"], isActive: true)],
        createdService: CreatedServiceRecord(
            identifier: "ABC", interfaceBSDName: "en6", name: "RDMA — Back, far left",
            isEnabled: true, ipv4: Fixtures.ipv4Off, ipv6: Fixtures.ipv6LinkLocal))

    // MARK: The refusal itself

    @Test("The refusal carries §6.2's own words, and nothing else")
    func refusesWithTheSpecsWords() throws {
        let refusal = try #require(Refusals.macRecognized(Fixtures.unrecognized))
        #expect(refusal.code == .macNotRecognized)
        #expect(refusal.code.rawValue == "R31")
        #expect(refusal.headline == "RDMALink doesn't recognize this Mac")
        #expect(refusal.body == "RDMALink only draws, and only changes, Macs it knows — and this "
            + "isn't one of them. So there's no picture, and nothing here will be changed. The "
            + "ports below are listed the way macOS reports them, and everything you see is real.")
        #expect(refusal.detail == nil)
        #expect(refusal.subjects.isEmpty)
    }

    @Test("A Mac recognized by either rule in §4.7 passes")
    func acceptsARecognizedMac() {
        #expect(Refusals.macRecognized(Fixtures.studio) == nil)
        let byLayout = HardwareModel(
            identifier: "Mac99,99", marketingName: "MacBook Pro", chip: "M9 Max",
            archetype: .notebook, recognition: .familyAndLayout)
        #expect(Refusals.macRecognized(byLayout) == nil)
    }

    // MARK: Set-up

    @Test("Set-up refuses with R31 ahead of every other whole-Mac refusal")
    func setUpRefusesFirst() throws {
        // Everything else in the way at once: a volume mounted over the link
        // (R4), no route but Thunderbolt (R5) and no room for a note (R14).
        func world(_ hardware: HardwareModel) -> ObservedWorld {
            Fixtures.world(ifconfig: Fixtures.inOneBridge, primary: ["en6"],
                           mounted: [Self.volume],
                           notesAreWritable: Refusals.baselineUnwritable(), hardware: hardware)
        }
        let plan = SetUpPorts(ports: [Fixtures.port]).preview(world: world(Fixtures.unrecognized))
        #expect(plan.refusal?.code == .macNotRecognized)
        #expect(plan.refusals.first?.code == .macNotRecognized)
        #expect(!plan.canProceed)
        #expect(plan.defaultButtonTitle == nil)
        // The same Mac, recognized: the ordinary order stands, R4 first.
        #expect(SetUpPorts(ports: [Fixtures.port]).preview(world: world(Fixtures.studio))
            .refusal?.code == .volumeMounted)
    }

    @Test("Set-up on a Mac with nothing else in the way still refuses, and writes nothing")
    func setUpWritesNothing() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.standalone) }
        let world = Fixtures.world(ifconfig: Fixtures.inOneBridge, hardware: Fixtures.unrecognized)
        #expect(SetUpPorts(ports: [Fixtures.port]).preview(world: world).ports.first?.refusal == nil,
                "the per-port plan is untouched: the whole-Mac refusal is the answer")
        #expect {
            try SetUpPorts(ports: [Fixtures.port]).perform(
                writer: writer, world: world,
                environment: Fixtures.environment(store: store, hardware: Fixtures.unrecognized),
                progress: { _, _ in })
        } throws: { ($0 as? Refusal)?.code == .macNotRecognized }
        #expect(writer.calls == [.lock], "no write of any kind")
        #expect((try? store.load(port: "en6")) == nil, "and no note")
    }

    // MARK: Restore

    @Test("Restore refuses with R31 before it reads the note — a missing note is not R19 here")
    func restoreRefusesBeforeTheNote() throws {
        let unrecognized = Fixtures.world(ifconfig: Fixtures.standalone,
                                          bridges: [Self.thunderboltBridge],
                                          hardware: Fixtures.unrecognized)
        #expect(RestorePort(port: Fixtures.port).preview(note: nil, world: unrecognized)
            .refusal?.code == .macNotRecognized)
        #expect(RestorePort(port: Fixtures.port).preview(note: Self.note, world: unrecognized)
            .refusal?.code == .macNotRecognized)
        #expect(RestorePort(port: Fixtures.port).preview(note: Self.note, world: unrecognized)
            .buttonTitle == nil)
        // Recognized, the note decides as it always did.
        let recognized = Fixtures.world(ifconfig: Fixtures.standalone,
                                        bridges: [Self.thunderboltBridge])
        #expect(RestorePort(port: Fixtures.port).preview(note: nil, world: recognized)
            .refusal?.code == .undoNoteMissing)
        #expect(RestorePort(port: Fixtures.port).preview(note: Self.note, world: recognized)
            .refusal == nil)
    }

    @Test("Restore performs nothing, and the note it did not read stays where it is")
    func restoreWritesNothing() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(Self.note)
        let writer = FakeWriter()
        writer.presentServiceIDs = ["ABC"]
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        #expect {
            try RestorePort(port: Fixtures.port).perform(
                writer: writer,
                world: Fixtures.world(ifconfig: Fixtures.standalone,
                                      services: [Self.readyService],
                                      bridges: [Self.thunderboltBridge],
                                      hardware: Fixtures.unrecognized),
                environment: Fixtures.environment(store: store, hardware: Fixtures.unrecognized),
                progress: { _, _ in })
        } throws: { ($0 as? Refusal)?.code == .macNotRecognized }
        #expect(writer.calls == [.lock])
        #expect(writer.presentServiceIDs == ["ABC"], "the service RDMALink made is still there")
        #expect((try? store.load(port: "en6")) != nil, "and so is the note")
    }

    // MARK: Return to Bridge

    @Test("Return to Bridge refuses with R31 even with a Thunderbolt Bridge to return to")
    func returnToBridgeRefuses() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let world = Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.readyService],
                                   bridges: [Self.thunderboltBridge],
                                   hardware: Fixtures.unrecognized)
        let plan = ReturnToBridge(port: Fixtures.port).preview(world: world)
        #expect(plan.refusal?.code == .macNotRecognized)
        #expect(plan.bridgeBSDName == nil, "no bridge is even chosen")
        #expect(plan.buttonTitle == nil)
        // Recognized, the same world offers the return.
        #expect(ReturnToBridge(port: Fixtures.port).preview(
            world: Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.readyService],
                                  bridges: [Self.thunderboltBridge])).buttonTitle
            == "Return to Bridge")

        let writer = FakeWriter()
        writer.presentServiceIDs = ["A"]
        #expect {
            try ReturnToBridge(port: Fixtures.port).perform(
                writer: writer, world: world,
                environment: Fixtures.environment(store: store, hardware: Fixtures.unrecognized),
                progress: { _, _ in })
        } throws: { ($0 as? Refusal)?.code == .macNotRecognized }
        #expect(writer.calls == [.lock])
        #expect((try? store.load(port: "en6")) == nil, "no return record was written")
    }

    // MARK: Adopt, and letting go

    @Test("Adopt reports what it found, offers nothing, and writes no note")
    func adoptRefuses() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let world = Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.readyService],
                                   hardware: Fixtures.unrecognized)
        let plan = AdoptPort(port: Fixtures.port).preview(world: world)
        #expect(plan.match == .full, "the findings are still what was found")
        #expect(plan.refusal?.code == .macNotRecognized)
        #expect(plan.buttonTitles.isEmpty)
        #expect(!plan.canAdopt)
        #expect {
            try AdoptPort(port: Fixtures.port).perform(
                world: world,
                environment: Fixtures.environment(store: store, hardware: Fixtures.unrecognized))
        } throws: { ($0 as? Refusal)?.code == .macNotRecognized }
        #expect((try? store.load(port: "en6")) == nil)
        // Recognized, the same port is adopted as before.
        #expect(AdoptPort(port: Fixtures.port).preview(
            world: Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.readyService]))
            .canAdopt)
    }

    @Test("Stop Managing refuses with R31 and the note stays: forgetting is a write too")
    func stopManagingRefuses() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(PortBaseline.adopted(bsdName: "en6", receptacle: 1,
                                            positionName: "Back, far left"))
        let environment = Fixtures.environment(store: store, hardware: Fixtures.unrecognized)
        #expect {
            try StopManaging(port: Fixtures.port).perform(environment: environment)
        } throws: { ($0 as? Refusal)?.code == .macNotRecognized }
        #expect((try? store.load(port: "en6")) != nil)
        #expect(try environment.log.entries().isEmpty, "and nothing was logged")
    }

    // MARK: The catalogue

    @Test("No chassis is ever built for an unrecognized Mac")
    func noChassisForUnknown() {
        #expect(ReceptacleCatalogue.chassis(for: .unknown) == nil)
        for archetype in Archetype.allCases {
            #expect(ReceptacleCatalogue.chassis(for: archetype)?.archetype != .unknown)
        }
    }
}
