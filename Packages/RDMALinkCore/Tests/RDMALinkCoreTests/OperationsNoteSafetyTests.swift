import Foundation
import Testing

@testable import RDMALinkCore

/// The undo note is the thing every other promise rests on, so nothing may
/// overwrite one, delete one over a change it did not make, or take a password
/// to put back something the note never recorded.
@Suite("What may and may not happen to an undo note")
struct OperationsNoteSafetyTests {

    private static let recordedAt = Date(timeIntervalSince1970: 1_756_909_260)

    private static let created = CreatedServiceRecord(
        identifier: "ABC", interfaceBSDName: "en6", name: "RDMA — Back, far left",
        isEnabled: true, ipv4: Fixtures.ipv4Off, ipv6: Fixtures.ipv6LinkLocal)

    /// A note for a port RDMALink set up **while it was already standalone**:
    /// no bridge history, but a service that is squarely RDMALink's own.
    private static func standaloneNote() -> PortBaseline {
        PortBaseline(
            bsdName: "en6", receptacle: 1, positionName: "Back, far left",
            bridges: [], createdService: created, recordedAt: recordedAt)
    }

    private static func adoptedNote() -> PortBaseline {
        PortBaseline.adopted(
            bsdName: "en6", receptacle: 1, positionName: "Back, far left",
            existingService: ServiceRecord(identifier: "ABC", name: "Thunderbolt 6",
                                           orderIndex: 0),
            ipv4: Fixtures.ipv4Off, ipv6: Fixtures.ipv6LinkLocal, recordedAt: recordedAt)
    }

    private static let service = NetworkServiceInfo(
        serviceID: "ABC", name: "RDMA — Back, far left", interfaceBSDName: "en6",
        isEnabled: true, ipv4: Fixtures.ipv4Off, ipv6: Fixtures.ipv6LinkLocal)

    private static let thunderboltBridge = BridgeSPI.Membership(
        bsdName: "bridge0", displayName: "Thunderbolt Bridge", members: ["en5"])

    // MARK: - Restore

    @Test("A note that records nothing to undo is refused before any password")
    func refusesANoteWithNothingInIt() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let note = PortBaseline(
            bsdName: "en6", receptacle: 1, positionName: "Back, far left",
            bridges: [], recordedAt: Self.recordedAt)
        try store.save(note)

        let world = Fixtures.world(ifconfig: Fixtures.standalone,
                                   bridges: [Self.thunderboltBridge])
        #expect(RestorePort.describesNothingToUndo(note))
        #expect(RestorePort(port: Fixtures.port).preview(note: note, world: world)
            .refusal?.code == .undoNoteMissing)

        let writer = FakeWriter()
        #expect {
            try RestorePort(port: Fixtures.port).perform(
                writer: writer, world: world,
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { ($0 as? Refusal)?.code == .undoNoteMissing }
        #expect(writer.calls == [.lock], "no write, and no note deleted")
        #expect((try? store.load(port: "en6")) != nil)
    }

    @Test("An adopted note is never restored: §7.3 has no put-it-back for one")
    func refusesAnAdoptedNote() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(Self.adoptedNote())
        let writer = FakeWriter()
        #expect {
            try RestorePort(port: Fixtures.port).perform(
                writer: writer,
                world: Fixtures.world(ifconfig: Fixtures.standalone,
                                      services: [Self.service],
                                      bridges: [Self.thunderboltBridge]),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { ($0 as? Refusal)?.code == .undoNoteMissing }
        #expect(writer.calls == [.lock])
        #expect((try? store.load(port: "en6")) != nil, "the note is the user's, not ours")
    }

    @Test("A port set up while already standalone restores to standalone, and says so")
    func restoresAStandalonePort() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(Self.standaloneNote())
        let writer = FakeWriter()
        writer.presentServiceIDs = ["ABC"]
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.standalone) }

        let result = try RestorePort(port: Fixtures.port).perform(
            writer: writer,
            world: Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.service],
                                  bridges: [Self.thunderboltBridge]),
            environment: Fixtures.environment(store: store), progress: { _, _ in })

        #expect(writer.calls == [
            .lock,
            .deleteService(identifier: "ABC", expecting: "en6"),
            .commitAndApply,
        ])
        #expect(result.rejoinedBridges.isEmpty)
        // No bridge was joined, so no bridge is claimed.
        #expect(result.successBody(bridgeName: "") ==
            "The service is gone and the port is standalone. Nothing else on this Mac was touched.")
        #expect((try? store.load(port: "en6")) == nil)
    }

    // MARK: - Return to Bridge

    @Test("Return to Bridge never writes over the note of a port RDMALink set up")
    func refusesToOverwriteAManagedNote() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(Self.standaloneNote())
        let writer = FakeWriter()

        #expect(throws: (any Error).self) {
            try ReturnToBridge(port: Fixtures.port).perform(
                writer: writer,
                world: Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.service],
                                      bridges: [Self.thunderboltBridge]),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        }
        #expect(writer.calls == [.lock], "nothing is written")

        let note = try store.load(port: "en6")
        #expect(note.createdService?.identifier == "ABC",
                "the note that records how the port really was is still the one on disk")
    }

    @Test("An adopted note is Return to Bridge's to replace: §7.3 sends it here")
    func returnsAnAdoptedPort() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(Self.adoptedNote())
        let writer = FakeWriter()
        writer.presentServiceIDs = ["ABC"]
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }

        let result = try ReturnToBridge(port: Fixtures.port).perform(
            writer: writer,
            world: Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.service],
                                  bridges: [Self.thunderboltBridge]),
            environment: Fixtures.environment(store: store), progress: { _, _ in })
        #expect(result.bridgeName == "Thunderbolt Bridge")
    }

    // MARK: - Restore All's sentence

    @Test("Restore All counts its ports rather than always saying two")
    func countsItsPorts() {
        let one = RestoreAll(ports: [Fixtures.port]).body
        #expect(one.contains("One port will return"))
        #expect(one.contains("its service will be deleted"))
        #expect(one.contains("One password covers it."))

        var second = Fixtures.port
        second.bsdName = "en7"
        let two = RestoreAll(ports: [Fixtures.port, second]).body
        #expect(two.contains("Two ports will return"))
        #expect(two.contains("their services will be deleted"))
        #expect(two.contains("One password covers both."))

        var third = Fixtures.port
        third.bsdName = "en8"
        let three = RestoreAll(ports: [Fixtures.port, second, third]).body
        #expect(three.contains("Three ports will return"))
        #expect(three.contains("One password covers all of them."))
    }

    // MARK: - Adopt

    @Test("A port still in a bridge is never offered Adopt, whatever else matches")
    func neverAdoptsABridgedPort() {
        let world = Fixtures.world(
            ifconfig: Fixtures.inOneBridge,
            services: [NetworkServiceInfo(
                serviceID: "S", name: "Thunderbolt 6", interfaceBSDName: "en6",
                isEnabled: true, ipv4: Fixtures.ipv4Off, ipv6: Fixtures.ipv6Automatic)],
            bridges: [Self.thunderboltBridge])
        let plan = AdoptPort(port: Fixtures.port).preview(world: world)
        #expect(plan.match == .none)
        #expect(plan.canAdopt == false)
        #expect(plan.buttonTitles.isEmpty)
        #expect(plan.body.isEmpty, "the near-match body claims the port is out of every bridge")
    }

    @Test("The near-match body names what was actually found")
    func namesTheDifferenceItFound() {
        let world = Fixtures.world(
            ifconfig: Fixtures.standalone,
            services: [NetworkServiceInfo(
                serviceID: "S", name: "Thunderbolt 6", interfaceBSDName: "en6",
                isEnabled: true, ipv4: Fixtures.ipv4Manual, ipv6: Fixtures.ipv6LinkLocal)],
            bridges: [Self.thunderboltBridge])
        // A fixed IPv4 address is R16's, not a near match, so the difference
        // that reaches the body is the one below it.
        let disabled = Fixtures.world(
            ifconfig: Fixtures.standalone,
            services: [NetworkServiceInfo(
                serviceID: "S", name: "Thunderbolt 6", interfaceBSDName: "en6",
                isEnabled: false, ipv4: Fixtures.ipv4Off, ipv6: Fixtures.ipv6LinkLocal)],
            bridges: [Self.thunderboltBridge])
        #expect(AdoptPort(port: Fixtures.port).preview(world: world).match == .none)
        let plan = AdoptPort(port: Fixtures.port).preview(world: disabled)
        #expect(plan.headline == "Nearly a match")
        #expect(plan.body.contains("the service is switched off"))
    }

    @Test("Bridge membership is never the clause the near-match body names")
    func bridgeMembershipIsNotAServiceDifference() {
        let differences: [ConfigurationDifference] = [
            .stillInBridge("Thunderbolt Bridge"), .ipv6Disabled,
        ]
        #expect(ConfigurationDifference.serviceClause(in: differences)
            == "IPv6 is turned off rather than Link-local only")
        #expect(ConfigurationDifference.serviceClause(in: [.stillInBridge("bridge0")]) == nil)
    }
}
