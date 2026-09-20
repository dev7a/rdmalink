import Foundation
import Testing
@testable import RDMALinkCore

@Suite("Putting a port back")
struct OperationsRestoreTests {

    private static let recordedAt = Date(timeIntervalSince1970: 1_756_909_260)

    /// The note RDMALink would have written when it set en6 up.
    private static func note(
        serviceID: String = "ABC",
        bridges: [BridgeMembership] = [
            BridgeMembership(bridgeName: "bridge0", serviceIdentifier: "BR0",
                             displayName: "Thunderbolt Bridge",
                             members: ["en5", "en6"], isActive: true),
        ]
    ) -> PortBaseline {
        PortBaseline(
            bsdName: "en6", receptacle: 1, positionName: "Back, far left",
            bridges: bridges,
            createdService: CreatedServiceRecord(
                identifier: serviceID, interfaceBSDName: "en6",
                name: "RDMA — Back, far left", isEnabled: true,
                ipv4: Fixtures.ipv4Off, ipv6: Fixtures.ipv6LinkLocal),
            recordedAt: recordedAt)
    }

    private static func service(id: String, name: String) -> NetworkServiceInfo {
        NetworkServiceInfo(serviceID: id, name: name, interfaceBSDName: "en6",
                           isEnabled: true, ipv4: Fixtures.ipv4Off,
                           ipv6: Fixtures.ipv6LinkLocal)
    }

    @Test("The service is matched by identifier, even after it has been renamed")
    func matchesByIdentifier() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(Self.note())
        let writer = FakeWriter()
        writer.presentServiceIDs = ["ABC"]
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }

        let result = try RestorePort(port: Fixtures.port).perform(
            writer: writer,
            world: Fixtures.world(ifconfig: Fixtures.standalone,
                                  services: [Self.service(id: "ABC", name: "Renamed by hand")],
                                  bridges: [BridgeSPI.Membership(
                                    bsdName: "bridge0", displayName: "Thunderbolt Bridge",
                                    members: ["en5"])]),
            environment: Fixtures.environment(store: store), progress: { _, _ in })

        #expect(writer.calls == [
            .lock,
            .deleteService(identifier: "ABC", expecting: "en6"),
            .addMember(port: "en6", bridge: "bridge0", position: 1),
            .commitAndApply,
        ])
        #expect(result.serviceWasAlreadyGone == false)
        #expect(result.rejoinedBridges == ["Thunderbolt Bridge"])
        #expect(result.noteWasDeleted)
        #expect((try? store.load(port: "en6")) == nil, "the note goes only after verification")
    }

    @Test("A service that only shares the name is never the one that is deleted")
    func neverMatchesByName() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(Self.note(serviceID: "ABC"))
        let writer = FakeWriter()
        writer.presentServiceIDs = ["XYZ"]  // somebody else's, same name
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }

        let result = try RestorePort(port: Fixtures.port).perform(
            writer: writer,
            world: Fixtures.world(
                ifconfig: Fixtures.standalone,
                services: [Self.service(id: "XYZ", name: "RDMA — Back, far left")],
                bridges: [BridgeSPI.Membership(bsdName: "bridge0",
                                               displayName: "Thunderbolt Bridge",
                                               members: ["en5"])]),
            environment: Fixtures.environment(store: store), progress: { _, _ in })

        #expect(result.serviceWasAlreadyGone, "RDMALink's own service is gone")
        #expect(writer.presentServiceIDs.contains("XYZ"), "somebody else's is untouched")
    }

    @Test("R19: no note means RDMALink won't guess")
    func refusesWithoutANote() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        #expect {
            try RestorePort(port: Fixtures.port).perform(
                writer: writer, world: Fixtures.world(ifconfig: Fixtures.standalone),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { error in
            let refusal = error as? Refusal
            return refusal?.code == .undoNoteMissing
                && refusal?.headline == "I can't remember how this looked"
        }
        #expect(writer.calls == [.lock])
    }

    @Test("R20: the note is kept when the bridge doesn't have it back")
    func keepsTheNoteWhenMembershipDoesNotReturn() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(Self.note())
        let writer = FakeWriter()
        writer.presentServiceIDs = ["ABC"]
        writer.canReapplyConfiguration = false
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.standalone) }  // never comes back

        #expect {
            try RestorePort(port: Fixtures.port).perform(
                writer: writer,
                world: Fixtures.world(ifconfig: Fixtures.standalone,
                                      services: [Self.service(id: "ABC", name: "RDMA — Back, far left")],
                                      bridges: [BridgeSPI.Membership(
                                        bsdName: "bridge0", displayName: "Thunderbolt Bridge",
                                        members: ["en5"])]),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { error in
            let refusal = error as? Refusal
            return refusal?.code == .notBackInBridge
                && refusal?.headline == "Not quite back yet"
        }
        #expect((try? store.load(port: "en6")) != nil, "the note is deliberately kept")
    }

    @Test("A stored list that already has the port back is not an error")
    func toleratesAMembershipAlreadyStored() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(Self.note())
        let writer = FakeWriter()
        writer.presentServiceIDs = ["ABC"]
        // An earlier restore committed the membership and the kernel did not
        // follow (R20); this time the kernel has it, and the stored list —
        // mirrored from `inOneBridge` — lists en6 already.
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        let result = try RestorePort(port: Fixtures.port).perform(
            writer: writer,
            world: Fixtures.world(ifconfig: Fixtures.inOneBridge,
                                  services: [Self.service(id: "ABC", name: "RDMA — Back, far left")]),
            environment: Fixtures.environment(store: store), progress: { _, _ in })
        #expect(result.rejoinedBridges == ["Thunderbolt Bridge"])
        #expect(writer.calls.contains(.addMember(port: "en6", bridge: "bridge0", position: 1)))
        #expect((try? store.load(port: "en6")) == nil, "verified, so the note is gone")
    }

    @Test("R21: a bridge that has gone is offered Remove My Service Only")
    func offersServiceOnlyWhenTheBridgeIsGone() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let note = Self.note(bridges: [
            BridgeMembership(bridgeName: "bridge7", serviceIdentifier: "BR7",
                             displayName: "Thunderbolt Bridge", members: ["en5", "en6"],
                             isActive: true),
        ])
        try store.save(note)
        let world = Fixtures.world(
            ifconfig: Fixtures.standalone,
            services: [Self.service(id: "ABC", name: "RDMA — Back, far left")],
            bridges: [BridgeSPI.Membership(bsdName: "bridge0", displayName: "Thunderbolt Bridge",
                                           members: ["en5"])])

        let plan = RestorePort(port: Fixtures.port).preview(note: note, world: world)
        #expect(plan.refusal?.code == .originalBridgeGone)
        #expect(plan.mayRemoveServiceOnly)
        #expect(!plan.canProceed)

        // Taking the offer deletes RDMALink's own service and keeps the note.
        let writer = FakeWriter()
        writer.presentServiceIDs = ["ABC"]
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.standalone) }
        let result = try RestorePort(port: Fixtures.port, mode: .serviceOnly).perform(
            writer: writer, world: world,
            environment: Fixtures.environment(store: store), progress: { _, _ in })
        #expect(writer.calls == [
            .lock,
            .deleteService(identifier: "ABC", expecting: "en6"),
            .commitAndApply,
        ])
        #expect(result.noteWasDeleted == false)
        #expect((try? store.load(port: "en6")) != nil)
    }

    @Test("R4: a mounted volume means Restore is not offered")
    func refusesWhileSomethingIsMounted() throws {
        let note = Self.note()
        let plan = RestorePort(port: Fixtures.port).preview(
            note: note,
            world: Fixtures.world(
                ifconfig: Fixtures.standalone,
                mounted: [MountedVolume(name: "Vault", mountPoint: "/Volumes/Vault",
                                        source: "//guest@[fe80::6%25en6]/Vault",
                                        portBSDName: "en6")]))
        #expect(plan.refusal?.code == .volumeMounted)
        #expect(plan.buttonTitle == nil)
    }

    @Test("R28: a service somebody has taken over is not RDMALink's to delete")
    func refusesAnEditedService() throws {
        let edited = NetworkServiceInfo(serviceID: "ABC", name: "RDMA — Back, far left",
                                        interfaceBSDName: "en6", isEnabled: true,
                                        ipv4: Fixtures.ipv4Manual,
                                        ipv6: Fixtures.ipv6LinkLocal)
        let plan = RestorePort(port: Fixtures.port).preview(
            note: Self.note(),
            world: Fixtures.world(ifconfig: Fixtures.standalone, services: [edited]))
        #expect(plan.refusal?.code == .createdServiceEdited)
    }

    @Test("The sheet quotes the moment the note was taken, and the spec's rows")
    func showsTheSpecSheet() throws {
        let plan = RestorePort(port: Fixtures.port).preview(
            note: Self.note(),
            world: Fixtures.world(
                ifconfig: Fixtures.standalone,
                services: [Self.service(id: "ABC", name: "RDMA — Back, far left")]))
        #expect(plan.headline == "Put Back, far left the way it was?")
        #expect(plan.body.hasPrefix(
            "RDMALink will delete the service it made and return the port to Thunderbolt Bridge — exactly as it was on "))
        #expect(plan.rows == [
            "Delete the service RDMA — Back, far left",
            "Add the port back to Thunderbolt Bridge",
            "Check that it really is back, then forget the whole thing",
            "Leave every other setting alone",
        ])
        #expect(plan.notes.contains(RestorePort.identifierNote))
        #expect(plan.notes.contains(RestorePort.rdmaNote))
        #expect(plan.buttonTitle == "Restore")
    }

    @Test("A service somebody already removed leaves only the membership")
    func saysWhenTheServiceIsAlreadyGone() throws {
        let plan = RestorePort(port: Fixtures.port).preview(
            note: Self.note(), world: Fixtures.world(ifconfig: Fixtures.standalone))
        #expect(plan.isServiceAlreadyGone)
        #expect(plan.notes.contains(RestorePort.serviceAlreadyGone))
    }

    @Test("Two bridges get the note that says both")
    func mentionsBothBridges() throws {
        let note = Self.note(bridges: [
            BridgeMembership(bridgeName: "bridge0", displayName: "Thunderbolt Bridge",
                             members: ["en5", "en6"], isActive: true),
            BridgeMembership(bridgeName: "bridge1", displayName: "Thunderbolt Bridge 2",
                             members: ["en6", "en9"], isActive: false),
        ])
        let plan = RestorePort(port: Fixtures.port).preview(
            note: note,
            world: Fixtures.world(ifconfig: Fixtures.standalone,
                                  bridges: [Fixtures.bridge0, Fixtures.bridge1]))
        #expect(plan.notes.contains(RestorePort.twoBridgesNote))
        #expect(plan.bridgesToRejoin == ["Thunderbolt Bridge", "Thunderbolt Bridge 2"])
    }

    @Test("Restore All never rounds the summary up")
    func summarisesPartialSuccess() {
        #expect(RestoreAll.partialSummary(done: ["Back, far left"],
                                          unfinished: ["Back, far right"]) == """
            One port is back. Back, far right didn't finish — its undo note has been kept, \
            so you can try that one again.
            """)
        #expect(RestoreAll.partialSummary(done: ["a", "b"], unfinished: []) == nil)
    }

    @Test("Restore All names how many ports it is about")
    func namesTheCount() {
        var second = Fixtures.port
        second.bsdName = "en7"
        #expect(RestoreAll(ports: [Fixtures.port, second]).body.hasPrefix(
            "Two ports will return to Thunderbolt Bridge"))
    }
}
