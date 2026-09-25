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
        // The kernel answers with the finished state throughout, so the
        // session's stored copy is stated rather than mirrored from it.
        writer.bridgesValue = [Self.thunderboltBridge]
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
            .commitAndApply,
            .addMember(port: "en6", bridge: "bridge0", position: nil),
            .commitAndApply,
        ])
        #expect(result.deletedService == "Thunderbolt 6")
        #expect(result.successHeadline == "Back, far left is in Thunderbolt Bridge")
        #expect(result.successBody.contains("Set Up Again is one click away"))

        // The note records what was found, so the port can be set up again —
        // and which bridge it went into, which is what makes it a return record.
        let note = try store.load(port: "en6")
        #expect(note.existingService?.identifier == "FOREIGN")
        #expect(note.bridges.isEmpty)
        #expect(note.isReturned)
        #expect(note.returnedToBridge ==
                BridgeReturn(bsdName: "bridge0", displayName: "Thunderbolt Bridge"))
        #expect(result.agreement.settledOnItsOwn)
        #expect(!result.agreement.retriedMembership)

        // §S11: the log records the return, and that a service went with it.
        let entries = try Fixtures.environment(store: store).log.entries()
        #expect(entries.last?.kind == .returned)
        #expect(entries.last?.sentence ==
                "Put it back in Thunderbolt Bridge and removed its standalone service.")
        #expect(entries.last?.port == "en6")
    }

    @Test("No standalone service: no delete row, no delete step, and no sentence about one")
    func returnsABarePort() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let world = Fixtures.world(ifconfig: Fixtures.standalone, services: [],
                                   bridges: [Self.thunderboltBridge])
        let plan = ReturnToBridge(port: Fixtures.port).preview(world: world)
        #expect(plan.headline == "Return this port to Thunderbolt Bridge?")
        #expect(plan.body == """
            RDMALink didn't set up Back, far left, so it can't put things back \
            exactly as they were — but it can do the ordinary thing: add the port \
            to Thunderbolt Bridge. It writes down what it found first, so you can \
            set the port up again afterwards.
            """)
        #expect(plan.rows == [
            "Add the port to Thunderbolt Bridge",
            "Check that it really is in the bridge",
            "Leave every other setting alone",
        ])
        #expect(plan.serviceID == nil)
        #expect(plan.buttonTitle == "Return to Bridge")

        let writer = FakeWriter()
        writer.bridgesValue = [Self.thunderboltBridge]
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        let log = ProgressLog()
        let result = try ReturnToBridge(port: Fixtures.port).perform(
            writer: writer, world: world,
            environment: Fixtures.environment(store: store), progress: log.record)

        #expect(writer.calls == [
            .lock,
            .addMember(port: "en6", bridge: "bridge0", position: nil),
            .commitAndApply,
        ])
        #expect(log.text == [
            "running Saving how to undo this…",
            "done Saved how to undo this",
            "running Returning the port to Thunderbolt Bridge…",
            "done Add the port to Thunderbolt Bridge",
            "running Checking that it's back…",
            "done Check that it really is in the bridge",
        ])
        #expect(!log.text.contains { $0.contains("Deleting the service") })
        #expect(result.deletedService == nil)
        #expect(result.successHeadline == "Back, far left is in Thunderbolt Bridge")
        #expect(result.successBody == """
            The port is a member of Thunderbolt Bridge again. Set Up Again is \
            one click away if you change your mind.
            """)

        let note = try store.load(port: "en6")
        #expect(note.isReturned)
        #expect(note.existingService == nil)
        let entries = try Fixtures.environment(store: store).log.entries()
        #expect(entries.map(\.kind) == [.returned])
        #expect(entries.last?.sentence == "Put it back in Thunderbolt Bridge.")
    }

    @Test("The bridge is named as the stored configuration names it, or by its kernel name")
    func namesTheBridgeInTheNote() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.bridgesValue = [Self.soleBridge]
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        let result = try ReturnToBridge(port: Fixtures.port).perform(
            writer: writer,
            world: Fixtures.world(ifconfig: Fixtures.standalone, services: [],
                                  bridges: [Self.soleBridge]),
            environment: Fixtures.environment(store: store), progress: { _, _ in })
        #expect(result.bridgeName == "bridge0")
        #expect(try store.load(port: "en6").returnedToBridge ==
                BridgeReturn(bsdName: "bridge0", displayName: nil))
        #expect(try Fixtures.environment(store: store).log.entries().last?.sentence ==
                "Put it back in bridge0.")
    }

    @Test("A stored list that already has the port is rewritten at add time, and the agreement says so")
    func reportsARewriteAtAddTime() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        // An earlier return got as far as the stored list and the kernel did
        // not follow (R20); the session's copy lists en6 already.
        writer.bridgesValue = [BridgeSPI.Membership(
            bsdName: "bridge0", displayName: "Thunderbolt Bridge", members: ["en5", "en6"])]
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        let result = try ReturnToBridge(port: Fixtures.port).perform(
            writer: writer,
            world: Fixtures.world(ifconfig: Fixtures.standalone, services: [],
                                  bridges: [Self.thunderboltBridge]),
            environment: Fixtures.environment(store: store), progress: { _, _ in })
        #expect(writer.calls == [
            .lock,
            .addMember(port: "en6", bridge: "bridge0", position: nil),
            .removeMember(port: "en6", bridge: "bridge0"),
            .commitAndApply,
            .addMember(port: "en6", bridge: "bridge0", position: nil),
            .commitAndApply,
        ])
        #expect(result.agreement.agreed)
        #expect(result.agreement.settledOnItsOwn == false)
        #expect(result.agreement.retriedMembership)
        #expect(result.agreement.settledAfterRetry)
    }

    @Test("The sheet says what §S10's foreign-port form says")
    func showsTheForeignSheet() throws {
        let plan = ReturnToBridge(port: Fixtures.port).preview(
            world: Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.foreign],
                                  bridges: [Self.thunderboltBridge]))
        #expect(plan.headline == "Return this port to Thunderbolt Bridge?")
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
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.standalone) }
        #expect {
            try ReturnToBridge(port: Fixtures.port).perform(
                writer: writer,
                world: Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.foreign],
                                      bridges: [Self.thunderboltBridge]),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: {
            guard let refusal = $0 as? Refusal, refusal.code == .notBackInBridge else { return false }
            // A service went, and R20 says so.
            return refusal.body.hasPrefix("The service is gone, but Thunderbolt Bridge")
        }
        #expect((try? store.load(port: "en6")) != nil)
    }

    @Test("R20 on a bare port: the note is kept, and the body never claims a deletion")
    func keepsTheNoteOnAMissWithoutAService() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.standalone) }
        #expect {
            try ReturnToBridge(port: Fixtures.port).perform(
                writer: writer,
                world: Fixtures.world(ifconfig: Fixtures.standalone, services: [],
                                      bridges: [Self.thunderboltBridge]),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: {
            guard let refusal = $0 as? Refusal, refusal.code == .notBackInBridge else { return false }
            return refusal.body == """
                Thunderbolt Bridge isn't listing Back, far left yet. RDMALink has kept \
                your undo note, so nothing is lost and it can try again whenever you like.
                """
        }
        #expect(!writer.calls.contains { if case .deleteService = $0 { true } else { false } })
        #expect(try store.load(port: "en6").isReturned)
        #expect(try Fixtures.environment(store: store).log.entries().isEmpty)
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
        #expect(plan.buttonTitles == ["Adopt", "Cancel"])
        #expect(plan.notes.contains(AdoptPort.honestyNote))
        // §S9: the note names both buttons by their own words (§1.3 rule 11).
        #expect(AdoptPort.honestyNote.hasSuffix(
            "Return to Bridge does the ordinary thing instead, and Stop Managing leaves the port exactly as it is."))
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

    /// RDMALink's note from setting the port up, naming the service it made.
    private static func setUpNote(created: String, bridges: Bool) -> PortBaseline {
        PortBaseline(
            bsdName: "en6", receptacle: 1, positionName: "Back, far left",
            bridges: bridges
                ? [BridgeMembership(bridgeName: "bridge0", members: ["en5", "en6"], isActive: true)] : [],
            createdService: CreatedServiceRecord(identifier: created, interfaceBSDName: "en6"))
    }

    @Test("A set-up note names another service only by identifier, and only as a set-up note")
    func tellsTheServicesApartByIdentifier() {
        #expect(Self.setUpNote(created: "MINE", bridges: true).namesAServiceOtherThan("A"))
        #expect(!Self.setUpNote(created: "A", bridges: true).namesAServiceOtherThan("A"))
        #expect(!PortBaseline.adopted(bsdName: "en6", receptacle: 1, positionName: "Back, far left")
            .namesAServiceOtherThan("A"), "an adopted note made no service")
        #expect(!PortBaseline(
            bsdName: "en6", receptacle: 1, positionName: "Back, far left",
            returnedToBridge: BridgeReturn(bsdName: "bridge0", displayName: "Thunderbolt Bridge"))
            .namesAServiceOtherThan("A"), "nor did a return record")
        #expect(!PortBaseline(
            bsdName: "en6", receptacle: 1, positionName: "Back, far left",
            bridges: [BridgeMembership(bridgeName: "bridge0", members: ["en5", "en6"], isActive: true)])
            .namesAServiceOtherThan("A"), "a note that names no service has no identity to tell apart")
    }

    @Test("RDMALink's service replaced by a full match made by hand: adopted, over the old note (§S9)")
    func adoptsOverANoteWhoseServiceIsGone() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let world = Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.readyService])
        let old = Self.setUpNote(created: "MINE", bridges: true)
        try store.save(old)

        let plan = AdoptPort(port: Fixtures.port, existingNote: old).preview(world: world)
        #expect(plan.match == .full && plan.canAdopt)
        #expect(plan.notes == [AdoptPort.note, AdoptPort.forgottenBridgesHonestyNote])
        #expect(!plan.notes.contains(AdoptPort.honestyNote), "RDMALink did see this port before")
        #expect(plan.forgetsTheWayBack, "the old note records the bridges the port came from")
        #expect(plan.buttonTitles == ["Adopt", "Cancel"])
        #expect(AdoptPort.forgottenBridgesHonestyNote == """
            One thing to be straight about: RDMALink set this port up before, but the \
            service it made is gone and this one was made by hand. Adopting looks after \
            this one and replaces RDMALink's old note for the port, so RDMALink won't \
            know which bridge the port came from any more. There's no exact "put it \
            back" for an adopted port — Return to Bridge does the ordinary thing \
            instead, and Stop Managing leaves the port exactly as it is.
            """)

        // A note that records no bridges loses nothing but itself.
        let standalone = AdoptPort(port: Fixtures.port,
                                   existingNote: Self.setUpNote(created: "MINE", bridges: false))
            .preview(world: world)
        #expect(standalone.canAdopt && !standalone.forgetsTheWayBack)
        #expect(standalone.notes == [AdoptPort.note, AdoptPort.replacedNoteHonestyNote])
        #expect(AdoptPort.replacedNoteHonestyNote == """
            One thing to be straight about: RDMALink set this port up before, but the \
            service it made is gone and this one was made by hand. Adopting looks after \
            this one and replaces RDMALink's old note for the port. There's no exact \
            "put it back" for an adopted port — Return to Bridge does the ordinary \
            thing instead, and Stop Managing leaves the port exactly as it is.
            """)

        try AdoptPort(port: Fixtures.port, existingNote: old).perform(
            world: world, environment: Fixtures.environment(store: store))
        let adopted = try store.load(port: "en6")
        #expect(adopted.isAdopted && adopted.bridges.isEmpty && adopted.createdService == nil,
                "the adopted note replaces the old one")
        #expect(adopted.existingService?.identifier == "A")
    }

    @Test("RDMALink's own service is never adopted, ready or edited since")
    func neverAdoptsRDMALinksOwnService() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let own = Self.setUpNote(created: "A", bridges: true)
        try store.save(own)
        let ready = Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.readyService])
        let readyPlan = AdoptPort(port: Fixtures.port, existingNote: own).preview(world: ready)
        #expect(readyPlan.match == .none && readyPlan.buttonTitles.isEmpty)
        #expect(throws: (any Error).self) {
            try AdoptPort(port: Fixtures.port, existingNote: own).perform(
                world: ready, environment: Fixtures.environment(store: store))
        }
        #expect(try store.load(port: "en6").createdServiceIdentifier == "A",
                "the note is left exactly where it was")

        let edited = Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.nearService])
        #expect(AdoptPort(port: Fixtures.port, existingNote: own).preview(world: edited).match == .none,
                "R28 answers for RDMALink's own service edited since, never S9's near match")
        #expect(AdoptPort(port: Fixtures.port, existingNote: PortBaseline.adopted(
            bsdName: "en6", receptacle: 1, positionName: "Back, far left")).preview(world: ready).match
                == .none, "an adopted port is already looked after")
    }

    @Test("A return record whose port moved on is adopted over, and the honesty note says RDMALink saw it (§S9)")
    func adoptsOverAStaleReturnRecord() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let record = PortBaseline(
            bsdName: "en6", receptacle: 1, positionName: "Back, far left",
            returnedToBridge: BridgeReturn(bsdName: "bridge0", displayName: "Thunderbolt Bridge"))
        try store.save(record)
        let world = Fixtures.world(ifconfig: Fixtures.standalone, services: [Self.readyService])

        let plan = AdoptPort(port: Fixtures.port, existingNote: record).preview(world: world)
        #expect(plan.canAdopt && !plan.forgetsTheWayBack, "a return record is no way back")
        #expect(plan.notes == [AdoptPort.note, AdoptPort.returnRecordHonestyNote])
        #expect(!plan.notes.contains(AdoptPort.honestyNote), "RDMALink did see this port before")
        #expect(AdoptPort.returnRecordHonestyNote == """
            One thing to be straight about: RDMALink returned this port to the bridge \
            before, but the port has left the bridge since and this service was made by \
            hand. Adopting looks after this one and replaces RDMALink's note of that \
            return. There's no exact "put it back" for an adopted port — Return to Bridge \
            does the ordinary thing instead, and Stop Managing leaves the port exactly as \
            it is.
            """)

        try AdoptPort(port: Fixtures.port, existingNote: record).perform(
            world: world, environment: Fixtures.environment(store: store))
        let adopted = try store.load(port: "en6")
        #expect(adopted.isAdopted && !adopted.isReturned, "the adopted note replaces the record")
    }

    @Test("Stop Managing forgets a return record too")
    func stopsManagingAReturnedPort() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(PortBaseline(
            bsdName: "en6", receptacle: 1, positionName: "Back, far left",
            returnedToBridge: BridgeReturn(bsdName: "bridge0", displayName: "Thunderbolt Bridge")))
        let environment = Fixtures.environment(store: store)
        _ = try StopManaging(port: Fixtures.port).perform(environment: environment)
        #expect((try? store.load(port: "en6")) == nil)
        #expect(try environment.log.entries().last?.kind == .stoppedManaging)
    }

    @Test("Stop Managing forgets the note and says exactly that")
    func stopsManaging() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(PortBaseline.adopted(bsdName: "en6", receptacle: 1,
                                            positionName: "Back, far left"))
        let operation = StopManaging(port: Fixtures.port, note: try store.load(port: "en6"))
        #expect(StopManaging.headline == "Stop managing this port?")
        #expect(!operation.forgetsTheWayBack, "an adopted note records no bridges")
        #expect(operation.body == """
            Stopping just means RDMALink forgets its note for Back, far left. The \
            port and its settings stay exactly as they are.
            """)
        #expect(StopManaging.runningHeadline == "Forgetting this port's note")
        let confirmation = try operation.perform(environment: Fixtures.environment(store: store))
        #expect(confirmation == """
            Done. Back, far left is exactly as it was a moment ago — RDMALink \
            is simply no longer keeping an eye on it.
            """)
        #expect((try? store.load(port: "en6")) == nil)
    }

    @Test("A drifted note records the way back, so the form says it goes too (§S10)")
    func warnsWhenTheNoteIsAWayBack() {
        let drifted = PortBaseline(
            bsdName: "en6", receptacle: 1, positionName: "Back, far left",
            bridges: [BridgeMembership(bridgeName: "bridge0", members: ["en5", "en6"], isActive: true)],
            createdService: CreatedServiceRecord(identifier: "MINE", interfaceBSDName: "en6"))
        let operation = StopManaging(port: Fixtures.port, note: drifted)
        #expect(operation.forgetsTheWayBack)
        #expect(operation.body == """
            Stopping just means RDMALink forgets its note for Back, far left. The \
            port and its settings stay exactly as they are. RDMALink won't be able \
            to put it back afterwards.
            """)
        // A return record names the bridge it went into, not bridges it came
        // from: nothing is lost by forgetting it.
        let returned = PortBaseline(
            bsdName: "en6", receptacle: 1, positionName: "Back, far left",
            returnedToBridge: BridgeReturn(bsdName: "bridge0", displayName: "Thunderbolt Bridge"))
        #expect(!StopManaging(port: Fixtures.port, note: returned).forgetsTheWayBack)
    }
}

@Suite("What is mounted over the link")
struct OperationsMountedVolumeTests {

    /// The shape `mount` prints, with made-up hosts and share names: one share
    /// down the port's own link (scope suffix and all), one on the ordinary
    /// network at a documentation address (RFC 5737), and one whose name has
    /// spaces in it, which is what makes the trailing ` on ` ambiguous.
    private static let mountOutput = """
        /dev/disk3s5 on / (apfs, sealed, local, read-only, journaled)
        //guest@[fe80::6%25en6]/Vault on /Volumes/Vault (smbfs, nodev, nosuid, mounted by someone)
        //guest@192.0.2.4/Backup on /Volumes/Backup (smbfs, nodev, nosuid)
        //guest@[fe80::6]/Scratch on Mac on /Volumes/Scratch on Mac (smbfs, nodev)
        """

    @Test("A share reached down the port's own link is found by its scope")
    func findsAVolumeByScope() {
        let volumes = MountedVolumes.parse(Self.mountOutput, ports: [Fixtures.port])
        #expect(volumes.map(\.name) == ["Vault", "Scratch on Mac"])
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
            nothing gets interrupted, then RDMALink will carry on.
            """)
        #expect(single.detail == nil)

        let two = one + [MountedVolume(name: "Scratch", mountPoint: "/Volumes/Scratch",
                                       source: "s", portBSDName: "en6")]
        let several = try #require(Refusals.nothingMountedOverThunderbolt(two))
        #expect(several.detail == "Vault and Scratch are mounted over Thunderbolt.")
        #expect(Refusals.nothingMountedOverThunderbolt([]) == nil)
    }
}
