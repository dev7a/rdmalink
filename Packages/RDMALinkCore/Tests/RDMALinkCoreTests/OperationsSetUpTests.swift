import Foundation
import Testing
@testable import RDMALinkCore

@Suite("Setting up a port, end to end")
struct OperationsSetUpTests {

    @Test("The undo note is on disk before the first network write")
    func writesTheNoteFirst() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.standalone) }
        var noteWasThere = false
        writer.intercept = { call in
            if case .removeMember = call {
                noteWasThere = (try? store.load(port: "en6")) != nil
            }
            return nil
        }
        let log = ProgressLog()
        let result = try SetUpPorts(ports: [Fixtures.port]).perform(
            writer: writer, world: Fixtures.world(ifconfig: Fixtures.inOneBridge),
            environment: Fixtures.environment(store: store), progress: log.record)

        #expect(noteWasThere, "the note has to exist before anything is changed")
        #expect(writer.calls == [
            .lock,
            .removeMember(port: "en6", bridge: "bridge0"),
            .createService(interface: "en6", name: "RDMA — Back, far left"),
            .commitAndApply,
        ])
        #expect(result.ports.first?.createdServiceID == "NEW-SERVICE-ID")
        #expect(result.ports.first?.leftBridges == ["Thunderbolt Bridge"])
        #expect(result.ports.first?.agreement.settledOnItsOwn == true)
        #expect(result.ports.first?.agreement.retriedMembership == false)
    }

    @Test("Setting a returned port up again replaces its record and marks the log entry")
    func setsAReturnedPortUpAgain() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let environment = Fixtures.environment(store: store)
        // What Return to Bridge left: a return record, and its log entry.
        try store.save(PortBaseline(
            bsdName: "en6", receptacle: 1, positionName: "Back, far left",
            returnedToBridge: BridgeReturn(bsdName: "bridge0", displayName: "Thunderbolt Bridge")))
        let returned = ChangeEntry.returned(
            port: "en6", positionName: "Back, far left", bridgeName: "Thunderbolt Bridge",
            removedService: false, date: Date(timeIntervalSince1970: 1_758_382_823))
        try environment.log.append(returned)

        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.standalone) }
        let result = try SetUpPorts(ports: [Fixtures.port]).perform(
            writer: writer, world: Fixtures.world(ifconfig: Fixtures.inOneBridge),
            environment: environment, progress: { _, _ in })
        #expect(result.ports.count == 1)

        // §7.5 step 5: setting the port up again replaces the return record.
        let note = try store.load(port: "en6")
        #expect(!note.isReturned)
        #expect(note.createdService?.identifier == "NEW-SERVICE-ID")
        #expect(note.bridges.map(\.bridgeName) == ["bridge0"])

        // §S11: the returned entry stays, answered by the new set-up, and
        // reads "Set up again on…" — the log itself is only appended to.
        let entries = try environment.log.entries()
        #expect(entries.map(\.kind) == [.returned, .setUp])
        #expect(entries[0] == returned)
        let answer = try #require(ChangeLog.answer(to: returned, in: entries))
        #expect(answer == entries[1])
        #expect(ChangeLog.note(for: returned, answeredBy: answer) ==
                ChangeSentence.setUpAgain(moment: Moment.text(answer.date)))
        #expect(ChangeLog.answer(to: answer, in: entries) == nil, "the new set-up stands")
    }

    @Test("A set-up that changed nothing puts the note that was there back, not away")
    func keepsThePreviousNoteWhenNothingChanged() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let record = PortBaseline(
            bsdName: "en6", receptacle: 1, positionName: "Back, far left",
            returnedToBridge: BridgeReturn(bsdName: "bridge0", displayName: "Thunderbolt Bridge"),
            recordedAt: Date(timeIntervalSince1970: 1_758_382_823))
        try store.save(record)
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        writer.intercept = { call in
            if case .removeMember = call {
                return NetworkConfigurationError.stepFailed(
                    step: "Remove from Thunderbolt Bridge", code: 1001, message: "Failed!")
            }
            return nil
        }
        #expect {
            try SetUpPorts(ports: [Fixtures.port]).perform(
                writer: writer, world: Fixtures.world(ifconfig: Fixtures.inOneBridge),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { ($0 as? Refusal)?.code == .portStillInBridge }
        #expect(try store.load(port: "en6") == record, "R9 changed nothing, the note included")
    }

    @Test("The note records every bridge with its whole member list")
    func recordsTheWholeWorld() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.standalone) }
        try SetUpPorts(ports: [Fixtures.port]).perform(
            writer: writer,
            world: Fixtures.world(ifconfig: Fixtures.inTwoBridges,
                                  bridges: [Fixtures.bridge0, Fixtures.bridge1]),
            environment: Fixtures.environment(store: store), progress: { _, _ in })

        let note = try store.load(port: "en6")
        #expect(note.bridges.map(\.bridgeName) == ["bridge0", "bridge1"])
        #expect(note.bridges[0].members == ["en5", "en6"])
        #expect(note.bridges[1].members == ["en6", "en9"])
        #expect(note.bridges[1].isActive == false)
        #expect(note.positionName == "Back, far left")
        #expect(note.receptacle == 1)
        #expect(note.createdService?.identifier == "NEW-SERVICE-ID")
        #expect(note.systemBuild.isEmpty == false)
    }

    @Test("The checklist says what UX_SPEC §S6 says")
    func reportsTheSpecChecklist() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.standalone) }
        let log = ProgressLog()
        try SetUpPorts(ports: [Fixtures.port]).perform(
            writer: writer, world: Fixtures.world(ifconfig: Fixtures.inOneBridge),
            environment: Fixtures.environment(store: store), progress: log.record)

        #expect(log.text == [
            "running Saving how to undo this…",
            "done Saved how to undo this",
            "running Leaving Thunderbolt Bridge…",
            "done Left Thunderbolt Bridge",
            "running Getting its own network service…",
            "done Got its own network service, RDMA — Back, far left",
            "running Turning IPv4 off, IPv6 to link-local…",
            "done Turned IPv4 off, IPv6 to link-local",
            "running Checking every bridge…",
            "done Out of every bridge",
        ])
    }

    // MARK: - The gates

    @Test("R14: a note that can't be written stops everything before it starts")
    func refusesWithoutSomewhereToSaveTheNote() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        let world = Fixtures.world(
            ifconfig: Fixtures.inOneBridge,
            notesAreWritable: Refusals.baselineUnwritable(detail: "The folder isn't writable."))
        #expect {
            try SetUpPorts(ports: [Fixtures.port]).perform(
                writer: writer, world: world,
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { error in
            (error as? Refusal)?.code == .baselineUnwritable
        }
        #expect(writer.calls == [.lock], "nothing may be written")
    }

    @Test("R1: a second Mac blocks the apply, and nothing is written")
    func refusesTwoMacs() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        // `inOneBridge` has en5 and en6 in bridge0; a Mac on the end of both
        // is the loop R1 is about.
        var second = Fixtures.port
        second.bsdName = "en5"
        second.positionName = "Back, far right"
        let world = Fixtures.world(ifconfig: Fixtures.inOneBridge,
                                   ports: [Fixtures.port, second])
        #expect {
            try SetUpPorts(ports: [Fixtures.port]).perform(
                writer: writer, world: world,
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { ($0 as? Refusal)?.code == .twoMacsConnected }
        #expect(writer.calls == [.lock])
    }

    @Test("R2: a cable back into this Mac blocks the apply ahead of R1, and nothing is written")
    func refusesLoopedCable() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        // The same two bridged, linked ports as R1's case, but the domain
        // identities say the cable comes back into this Mac.
        var first = Fixtures.port
        first.loopedBackTo = "en5"
        var second = Fixtures.port
        second.bsdName = "en5"
        second.positionName = "Back, far right"
        second.loopedBackTo = "en6"
        let world = Fixtures.world(ifconfig: Fixtures.inOneBridge, ports: [first, second])
        #expect(SetUpPorts(ports: [first]).preview(world: world).refusal?.code
            == .loopedBackIntoThisMac)
        #expect {
            try SetUpPorts(ports: [first]).perform(
                writer: writer, world: world,
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { ($0 as? Refusal)?.code == .loopedBackIntoThisMac }
        #expect(writer.calls == [.lock])
        #expect(!FileManager.default.fileExists(atPath: store.directory.path))
    }

    @Test("R5: Thunderbolt being the only way in blocks the apply")
    func refusesWhenThunderboltIsTheOnlyRoute() throws {
        let world = Fixtures.world(ifconfig: Fixtures.inOneBridge, primary: ["bridge0"])
        let plan = SetUpPorts(ports: [Fixtures.port]).preview(world: world)
        #expect(plan.refusal?.code == .onlyRouteIsThunderbolt)
        #expect(plan.defaultButtonTitle == nil, "the button is removed, not disabled")
    }

    @Test("R4: a volume mounted over the link blocks the apply")
    func refusesAMountedVolume() throws {
        let mounted = [MountedVolume(name: "Vault", mountPoint: "/Volumes/Vault",
                                     source: "//guest@[fe80::6%25en6]/Vault", portBSDName: "en6")]
        let plan = SetUpPorts(ports: [Fixtures.port]).preview(
            world: Fixtures.world(ifconfig: Fixtures.inOneBridge, mounted: mounted))
        #expect(plan.refusal?.code == .volumeMounted)
        #expect(plan.refusal?.body.contains("The volume Vault is mounted over Thunderbolt") == true)
    }

    @Test("R16: a port with someone else's fixed address is refused, never rewritten")
    func refusesAForeignService() throws {
        let services = [NetworkServiceInfo(serviceID: "X", name: "Static link",
                                           interfaceBSDName: "en6", isEnabled: true,
                                           ipv4: Fixtures.ipv4Manual, ipv6: nil)]
        let plan = SetUpPorts(ports: [Fixtures.port]).preview(
            world: Fixtures.world(ifconfig: Fixtures.inOneBridge, services: services))
        #expect(plan.ports.first?.refusal?.code == .foreignService)
        #expect(!plan.canProceed)
    }

    @Test("R15: a bridge the configuration can't see is refused, not guessed at")
    func refusesAnUnreadableBridge() throws {
        let plan = SetUpPorts(ports: [Fixtures.port]).preview(
            world: Fixtures.world(ifconfig: Fixtures.inOneBridge, bridges: []))
        #expect(plan.ports.first?.refusal?.code == .bridgeUnreadable)
    }

    @Test("R17: a cable that moved between the review and the burst stops it")
    func refusesAWorldThatMoved() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let operation = SetUpPorts(ports: [Fixtures.port])
        let reviewed = operation.preview(world: Fixtures.world(ifconfig: Fixtures.inOneBridge))
        let writer = FakeWriter()
        #expect {
            try SetUpPorts(ports: [Fixtures.port], reviewed: reviewed).perform(
                writer: writer,
                world: Fixtures.world(ifconfig: Fixtures.inTwoBridges,
                                      bridges: [Fixtures.bridge0, Fixtures.bridge1]),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { ($0 as? Refusal)?.code == .topologyChanged }
        #expect(writer.calls == [.lock])
    }

    @Test("A port that is already set up routes to Adopt and offers no button")
    func routesToAdopt() throws {
        let services = [NetworkServiceInfo(serviceID: "A", name: "Thunderbolt Bridge Free",
                                           interfaceBSDName: "en6", isEnabled: true,
                                           ipv4: Fixtures.ipv4Off, ipv6: Fixtures.ipv6LinkLocal)]
        let plan = SetUpPorts(ports: [Fixtures.port]).preview(
            world: Fixtures.world(ifconfig: Fixtures.standalone, services: services))
        #expect(plan.ports.first?.routesToAdopt == true)
        #expect(plan.ports.first?.refusal == nil, "routing, not refusing")
        #expect(plan.defaultButtonTitle == nil)
    }

    // MARK: - The review screen

    @Test("The review rows and chips are the spec's")
    func showsTheSpecReview() throws {
        let plan = SetUpPorts(ports: [Fixtures.port]).preview(
            world: Fixtures.world(ifconfig: Fixtures.inOneBridge))
        let rows = try #require(plan.ports.first?.rows)
        #expect(rows.count == 4)
        #expect(rows[0].title == "Save how to undo this")
        #expect(rows[0].before == "Nothing saved")
        #expect(rows[0].after == "Saved")
        #expect(rows[1].title == "Leave Thunderbolt Bridge")
        #expect(rows[1].before == "In the bridge")
        #expect(rows[1].after == "Standalone")
        #expect(rows[1].body.contains("This port is a member of Thunderbolt Bridge."))
        #expect(rows[2].body == "A new service called RDMA — Back, far left. Nothing else on this Mac uses it.")
        #expect(rows[2].before == "Doesn't exist")
        #expect(rows[3].after == "IPv4 off, IPv6 link-local only")
        #expect(plan.defaultButtonTitle == "Set Up Port")
    }

    @Test("S6's checklist is S5's rows, word for word (§S6)")
    func checklistIsTheReview() throws {
        let plan = SetUpPorts(ports: [Fixtures.port]).preview(
            world: Fixtures.world(ifconfig: Fixtures.inOneBridge))
        let port = try #require(plan.ports.first)
        let steps: [OperationStep] = [
            .saveUndoNote, .leaveBridge(named: port.bridgeNames[0]),
            .createService(named: port.serviceName), .setAddresses,
        ]
        #expect(steps.map(\.pending) == port.rows.map(\.title))
        #expect(steps.map(\.running) == [
            "Saving how to undo this…", "Leaving Thunderbolt Bridge…",
            "Getting its own network service…", "Turning IPv4 off, IPv6 to link-local…",
        ])
        #expect(steps.map(\.done) == [
            "Saved how to undo this", "Left Thunderbolt Bridge",
            "Got its own network service, RDMA — Back, far left",
            "Turned IPv4 off, IPv6 to link-local",
        ])
        #expect(OperationStep.leaveBridge(named: "Thunderbolt Bridge 2").pending
                == "Leave Thunderbolt Bridge 2", "one step per bridge, each by its own name")
        #expect(!SetUpPortsPlan.whatRDMALinkWontTouch.contains("The Thunderbolt Bridge"),
                "Thunderbolt Bridge is a name, with no article (§1.3 rule 12)")
    }

    @Test("Orange asks for an act; what is plugged in only informs (§3.1, §S4, §S5)")
    func separatesWarningsFromInformation() throws {
        var empty = Fixtures.port
        empty.link = .empty
        var dock = Fixtures.port
        dock.link = .device
        let off = SetUpPorts(ports: [empty]).preview(
            world: Fixtures.world(ifconfig: Fixtures.inOneBridge, ports: [empty], rdma: .off))
        let emptyPlan = try #require(off.ports.first)
        #expect(emptyPlan.warnings == [
            "RDMA over Thunderbolt is still off. The port will be ready; RDMA will start using it after you turn that on and restart.",
        ], "only switching RDMA on asks something of the user")
        #expect(emptyPlan.informationalLines == [
            "Nothing is plugged into this port yet. That's fine — the address appears when a Mac arrives.",
        ])
        let on = SetUpPorts(ports: [dock]).preview(
            world: Fixtures.world(ifconfig: Fixtures.inOneBridge, ports: [dock],
                                  rdma: .on(devices: ["rdma_en6"])))
        let dockPlan = try #require(on.ports.first)
        #expect(dockPlan.warnings.isEmpty)
        #expect(dockPlan.informationalLines == [
            SetUpPorts.informationalLine(for: .device) ?? "",
        ])
        #expect(SetUpPorts.informationalLine(for: .device)
                == "There's a dock or a display in this port. It'll keep working exactly as it does now — RDMA will use the port once a Mac is on the other end.")
        #expect(SetUpPorts.informationalLine(for: .device, naming: "Back, far right")
                == "There's a dock or a display in Back, far right. It'll keep working exactly as it does now — RDMA will use the port once a Mac is on the other end.")
        #expect(SetUpPorts.informationalLine(for: .empty, naming: "Back, far left")
                == "Nothing is plugged into Back, far left yet. That's fine — the address appears when a Mac arrives.")
        #expect(SetUpPorts.informationalLine(for: .macLinked) == nil
                && SetUpPorts.informationalLine(for: .macLinkComingUp) == nil)
    }

    @Test("Two bridges get the spec's second sentence and its own chip")
    func showsTwoBridges() throws {
        let plan = SetUpPorts(ports: [Fixtures.port]).preview(
            world: Fixtures.world(ifconfig: Fixtures.inTwoBridges,
                                  bridges: [Fixtures.bridge0, Fixtures.bridge1]))
        let row = try #require(plan.ports.first?.rows[1])
        #expect(row.before == "In two bridges")
        #expect(row.body.contains("It's also in an unused bridge, Thunderbolt Bridge 2."))
        #expect(row.body.contains("a port has to be out of every bridge, even one that isn't being used"))
    }

    @Test("A port in no bridge says so, and nothing is removed")
    func showsNoBridge() throws {
        let plan = SetUpPorts(ports: [Fixtures.port]).preview(
            world: Fixtures.world(ifconfig: Fixtures.standalone))
        let row = try #require(plan.ports.first?.rows[1])
        #expect(row.body == "This port isn't in any bridge, so there's nothing to remove.")
        #expect(row.before == "Standalone")
        #expect(row.after == "Standalone")
    }

    @Test("The technical disclosure names the interface, the service and each member list")
    func showsTechnicalNames() throws {
        let plan = SetUpPorts(ports: [Fixtures.port]).preview(
            world: Fixtures.world(ifconfig: Fixtures.inTwoBridges,
                                  bridges: [Fixtures.bridge0, Fixtures.bridge1]))
        let lines = try #require(plan.ports.first?.technicalNames)
        #expect(lines[0] == "Interface en6")
        #expect(lines[1] == "New service RDMA — Back, far left")
        #expect(lines[2] == "Removing from bridge0: members en5, en6 → en5")
        #expect(lines[3] == "Also removing from bridge1: members en6, en9 → en9")
        #expect(lines.contains("IPv4 configuration: Off"))
        #expect(lines.contains("IPv6 configuration: Link-local only"))
    }

    @Test("Two ports name the button for exactly what it will do, the count spelled out")
    func namesTheButtonForTwoPorts() throws {
        // Nothing on the end of the second one: two linked Macs would be R1,
        // and the button would be gone rather than renamed.
        var second = Fixtures.port
        second.bsdName = "en7"
        second.positionName = "Back, far right"
        second.link = .empty
        let plan = SetUpPorts(ports: [Fixtures.port, second]).preview(
            world: Fixtures.world(ifconfig: Fixtures.standalone,
                                  ports: [Fixtures.port, second]))
        #expect(plan.defaultButtonTitle == "Set Up Two Ports")

        var third = second
        third.bsdName = "en8"
        third.positionName = "Back, middle right"
        let three = SetUpPorts(ports: [Fixtures.port, second, third]).preview(
            world: Fixtures.world(ifconfig: Fixtures.standalone,
                                  ports: [Fixtures.port, second, third]))
        #expect(three.buttonTitle == "Set Up Three Ports")
    }

    @Test("Every count in the copy is spelled out by one formatter, in English (§1.3 rule 1)")
    func spellsCountsOut() {
        #expect(Counts.spelledOut(2, capitalized: true) == "Two")
        #expect(Counts.spelledOut(3, capitalized: false) == "three")
        #expect(Counts.spelledOut(11, capitalized: true) == "Eleven")
        // Pinned to the language every sentence around it is written in,
        // whatever the user's locale, so a count never lands in French.
        #expect(Counts.english.identifier == "en_US")
        #expect(RestoreAll.count(3, capitalized: true) == "Three ports")
        #expect(RestoreAll.count(1, capitalized: false) == "one port")
    }

    @Test("The completion line is the spec's sentence")
    func printsTheCompletionLine() {
        #expect(OperationTiming.completionLine(seconds: 1.84) == "Done. That took 1.8 seconds.")
    }
}
