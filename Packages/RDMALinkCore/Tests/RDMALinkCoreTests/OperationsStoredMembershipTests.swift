import Foundation
import Testing
@testable import RDMALinkCore

/// Set-up plans its removals from the stored member list, not only the
/// kernel's, and signs nothing off until both reads agree.
///
/// The bug this suite is about: the preferences held `bridge0` with `en5` in
/// it while `ifconfig bridge0` listed no members, so the review said "This
/// port isn't in any bridge, so there's nothing to remove", no removal was
/// planned, and `SCNetworkServiceCreate` then refused with `kSCStatusFailed`.
@Suite("Set-up against a bridge only the preferences remember")
struct OperationsStoredMembershipTests {

    /// `bridge0` with no members in the kernel; Ethernet is the way in.
    static let kernelHasNoMembers = """
        bridge0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            status: inactive
        en6: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            status: active
        en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet 10.77.78.1 netmask 0xfffffff8 broadcast 10.77.78.7
            status: active
        """

    static let storedBridge0 = BridgeSPI.Membership(
        bsdName: "bridge0", displayName: "Thunderbolt Bridge", members: ["en5", "en6"])

    static func world() -> ObservedWorld {
        Fixtures.world(ifconfig: kernelHasNoMembers, bridges: [storedBridge0])
    }

    // MARK: - The review

    @Test("The review plans the removal the preferences make necessary")
    func previewPlansTheStoredRemoval() throws {
        let plan = SetUpPorts(ports: [Fixtures.port]).preview(world: Self.world())
        let port = try #require(plan.ports.first)
        #expect(port.bridgesToLeave == ["bridge0"])
        #expect(port.bridgeNames == ["Thunderbolt Bridge"])
        #expect(port.canProceed)

        // UX_SPEC §S5 row 2, the one-bridge form — not the "nothing to remove"
        // variant the kernel alone would have produced.
        let row = port.rows[1]
        #expect(row.title == "Leave Thunderbolt Bridge")
        #expect(row.before == "In the bridge")
        #expect(row.after == "Standalone")
        #expect(row.body.contains("This port is a member of Thunderbolt Bridge."))

        // The technical line prints the list the write actually edits.
        #expect(port.technicalNames.contains("Removing from bridge0: members en5, en6 → en5"))
    }

    @Test("A stored-only membership is removed, and the note records it")
    func performRemovesTheStoredMembership() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.bridgesValue = [Self.storedBridge0]
        writer.kernel = { _ in Fixtures.snapshot(Self.kernelHasNoMembers) }

        let result = try SetUpPorts(ports: [Fixtures.port]).perform(
            writer: writer, world: Self.world(),
            environment: Fixtures.environment(store: store), progress: { _, _ in })

        #expect(writer.calls == [
            .lock,
            .removeMember(port: "en6", bridge: "bridge0"),
            .createService(interface: "en6", name: "RDMA — Back, far left"),
            .commitAndApply,
        ])
        #expect(result.ports.first?.leftBridges == ["Thunderbolt Bridge"])
        // The undo note has to carry the stored member list, or the restore
        // would put the port back into a bridge it thinks had one member.
        let note = try store.load(port: "en6")
        #expect(note.bridges.map(\.bridgeName) == ["bridge0"])
        #expect(note.bridges[0].members == ["en5", "en6"])
    }

    @Test("A kernel-only membership is still removed")
    func performRemovesAKernelOnlyMembership() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        // The preferences have a bridge0 that does not list the port at all.
        let storedWithoutThePort = BridgeSPI.Membership(
            bsdName: "bridge0", displayName: "Thunderbolt Bridge", members: ["en5"])
        writer.bridgesValue = [storedWithoutThePort]
        writer.kernel = { state in
            Fixtures.snapshot(state.reads > 1 ? Fixtures.standalone : Fixtures.inOneBridge)
        }
        let world = Fixtures.world(ifconfig: Fixtures.inOneBridge,
                                   bridges: [storedWithoutThePort])
        #expect(world.kernelBridges(containing: "en6") == ["bridge0"])
        #expect(world.storedBridges(containing: "en6").isEmpty)

        try SetUpPorts(ports: [Fixtures.port]).perform(
            writer: writer, world: world,
            environment: Fixtures.environment(store: store), progress: { _, _ in })

        #expect(writer.calls == [
            .lock,
            .removeMember(port: "en6", bridge: "bridge0"),
            .createService(interface: "en6", name: "RDMA — Back, far left"),
            .commitAndApply,
        ])
    }

    // MARK: - Verification

    @Test("A kernel that let go while the preferences did not is not a success")
    func storedMembershipThatPersistsFailsVerification() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.bridgesValue = [Self.storedBridge0]
        // The preferences keep listing the port however often the burst
        // commits — the other half of "macOS didn't actually let go".
        writer.storedMembershipPersists = true
        // The kernel, meanwhile, does exactly what was asked: the port is out
        // of bridge0 until the rollback puts it back. On the kernel's evidence
        // alone this burst would have been reported as done.
        var rolledBack = false
        writer.intercept = { call in
            if case .addMember = call { rolledBack = true }
            return nil
        }
        writer.kernel = { _ in
            Fixtures.snapshot(rolledBack ? Fixtures.inOneBridge : Fixtures.standalone)
        }

        #expect {
            try SetUpPorts(ports: [Fixtures.port]).perform(
                writer: writer,
                world: Fixtures.world(ifconfig: Fixtures.inOneBridge,
                                      bridges: [Self.storedBridge0]),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { error in
            // R10: the port went back, and the rollback is stated first.
            (error as? Refusal)?.code == .rolledBack
        }

        // It was rolled back, in reverse order.
        #expect(writer.calls.contains(.addMember(port: "en6", bridge: "bridge0", position: 1)))
        // The note is kept, exactly as it is for every other rollback.
        #expect((try? store.load(port: "en6")) != nil)
    }

    @Test("An unreadable stored configuration is never read as 'no bridges'")
    func anUnreadableConfigurationIsNotAnEmptyOne() {
        let kernel = Fixtures.snapshot(Fixtures.standalone)
        let unreadable = VerificationReading(snapshot: kernel, stored: nil)
        #expect(unreadable.isOutOfEveryBridge("en6") == false)
        #expect(unreadable.isMember("en5", ofAll: ["bridge0"]) == false)

        let readable = VerificationReading(snapshot: kernel, stored: [])
        #expect(readable.isOutOfEveryBridge("en6"))
    }

    @Test("Putting the port back is only done when both reads list it again")
    func restoreNeedsBothReads() {
        let kernel = Fixtures.snapshot(Fixtures.inOneBridge)
        let storedWithout = BridgeSPI.Membership(bsdName: "bridge0", members: ["en5"])
        #expect(VerificationReading(snapshot: kernel, stored: [storedWithout])
            .isMember("en6", ofAll: ["bridge0"]) == false)
        #expect(VerificationReading(snapshot: kernel, stored: [Self.storedBridge0])
            .isMember("en6", ofAll: ["bridge0"]))
    }
}
