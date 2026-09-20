import Foundation
import Testing
@testable import RDMALinkCore

@Suite("Rollback, and what the kernel had to be asked twice about")
struct OperationsRollbackTests {

    /// A failure that macOS would give for a step that would not take.
    private static let stepFailed = NetworkConfigurationError.stepFailed(
        step: "Create the RDMA service", code: 1004, message: "would not create")

    @Test("A failed service creation puts every bridge back, in reverse order")
    func rollsBackInReverse() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inTwoBridges) }
        writer.intercept = { call in
            if case .createService = call { return Self.stepFailed }
            return nil
        }
        #expect {
            try SetUpPorts(ports: [Fixtures.port]).perform(
                writer: writer,
                world: Fixtures.world(ifconfig: Fixtures.inTwoBridges,
                                      bridges: [Fixtures.bridge0, Fixtures.bridge1]),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { error in
            let refusal = error as? Refusal
            return refusal?.code == .rolledBack
                && refusal?.headline == "Put back, safely"
                && refusal?.body.contains("The new service wouldn't create") == true
        }

        #expect(writer.calls == [
            .lock,
            .removeMember(port: "en6", bridge: "bridge0"),
            .removeMember(port: "en6", bridge: "bridge1"),
            .createService(interface: "en6", name: "RDMA — Back, far left"),
            // Reverse order, and each member goes back where it sat.
            .addMember(port: "en6", bridge: "bridge1", position: 0),
            .addMember(port: "en6", bridge: "bridge0", position: 1),
            .commitAndApply,
        ])
    }

    @Test("The undo note is kept when a rollback runs")
    func keepsTheNoteAfterARollback() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        writer.intercept = { call in
            if case .createService = call { return Self.stepFailed }
            return nil
        }
        _ = try? SetUpPorts(ports: [Fixtures.port]).perform(
            writer: writer, world: Fixtures.world(ifconfig: Fixtures.inOneBridge),
            environment: Fixtures.environment(store: store), progress: { _, _ in })
        #expect((try? store.load(port: "en6")) != nil)
    }

    @Test("A rollback that can't finish is R11, with the findings block")
    func reportsAFailedRollback() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.standalone) }
        writer.intercept = { call in
            switch call {
            case .createService: return Self.stepFailed
            case .addMember: return Self.stepFailed  // and it can't be put back
            default: return nil
            }
        }
        #expect {
            try SetUpPorts(ports: [Fixtures.port]).perform(
                writer: writer, world: Fixtures.world(ifconfig: Fixtures.inOneBridge),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { error in
            let refusal = error as? Refusal
            return refusal?.code == .rollbackFailed
                && refusal?.headline == "One thing needs your hand"
                && refusal?.detail?.contains("Members before: en5, en6") == true
                && refusal?.detail?.contains("The port to add back: en6 — Back, far left") == true
        }
    }

    @Test("Nothing is rolled back when nothing was written: R9 says so")
    func refusesBeforeAnythingIsWritten() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        writer.intercept = { call in
            if case .removeMember = call { return Self.stepFailed }
            return nil
        }
        #expect {
            try SetUpPorts(ports: [Fixtures.port]).perform(
                writer: writer, world: Fixtures.world(ifconfig: Fixtures.inOneBridge),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { error in
            let refusal = error as? Refusal
            return refusal?.code == .portStillInBridge
                && refusal?.body.contains("stopped and changed nothing at all") == true
        }
        // The first removal is the only write attempted, and nothing is undone.
        #expect(writer.calls == [.lock, .removeMember(port: "en6", bridge: "bridge0")])
    }

    // MARK: - Verification

    @Test("A kernel that catches up late settles on its own, with no second apply")
    func waitsForASlowKernel() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        // Still in the bridge for the first two reads, out on the third.
        writer.kernel = { state in
            Fixtures.snapshot(state.reads >= 3 ? Fixtures.standalone : Fixtures.inOneBridge)
        }
        let result = try SetUpPorts(ports: [Fixtures.port]).perform(
            writer: writer, world: Fixtures.world(ifconfig: Fixtures.inOneBridge),
            environment: Fixtures.environment(store: store), progress: { _, _ in })

        let agreement = try #require(result.ports.first?.agreement)
        #expect(agreement.agreed)
        #expect(agreement.settledOnItsOwn)
        #expect(agreement.retriedMembership == false)
        #expect(agreement.reads == 3)
    }

    @Test("A kernel that never agrees rolls the port back and says so")
    func rollsBackWhenTheKernelNeverAgrees() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        #expect {
            try SetUpPorts(ports: [Fixtures.port]).perform(
                writer: writer, world: Fixtures.world(ifconfig: Fixtures.inOneBridge),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { error in
            let refusal = error as? Refusal
            return refusal?.code == .rolledBack
                && refusal?.body.contains("macOS didn't actually let go of the port") == true
        }
        // The service RDMALink had just made goes first, in a commit of its
        // own, then the membership in another (see `BridgeRejoin`).
        #expect(writer.calls == [
            .lock,
            .removeMember(port: "en6", bridge: "bridge0"),
            .createService(interface: "en6", name: "RDMA — Back, far left"),
            .commitAndApply,
            .deleteService(identifier: "NEW-SERVICE-ID", expecting: "en6"),
            .commitAndApply,
            .addMember(port: "en6", bridge: "bridge0", position: 1),
            .commitAndApply,
        ])
    }

    @Test("A membership the stored list still had is rewritten on the way back, once")
    func rewritesAtAddTimeDuringRollback() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        // The first add on the way back finds the port already in the stored
        // list, as the SPI reports it; the rewrite that follows is the retry.
        let adds = KernelState()
        writer.intercept = { call in
            guard case .addMember = call else { return nil }
            adds.membersAdded += 1
            return adds.membersAdded == 1
                ? BridgeSPIError.alreadyMember(bsdName: "en6", bridge: "bridge0") : nil
        }
        #expect {
            try SetUpPorts(ports: [Fixtures.port]).perform(
                writer: writer, world: Fixtures.world(ifconfig: Fixtures.inOneBridge),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { ($0 as? Refusal)?.code == .rolledBack }
        // One rewrite at add time, and none from the verification: the kernel
        // agreed on its first read after it.
        #expect(writer.calls == [
            .lock,
            .removeMember(port: "en6", bridge: "bridge0"),
            .createService(interface: "en6", name: "RDMA — Back, far left"),
            .commitAndApply,
            .deleteService(identifier: "NEW-SERVICE-ID", expecting: "en6"),
            .commitAndApply,
            .addMember(port: "en6", bridge: "bridge0", position: 1),
            .removeMember(port: "en6", bridge: "bridge0"),
            .commitAndApply,
            .addMember(port: "en6", bridge: "bridge0", position: 1),
            .commitAndApply,
        ])
        #expect((try? store.load(port: "en6")) != nil)
    }

    @Test("BridgeRejoin says whether it had to rewrite, and the agreement folds it in")
    func reportsTheRewrite() throws {
        let writer = FakeWriter()
        writer.bridgesValue = [Fixtures.bridge0]  // en5 and en6
        let membership = BridgeMembership(bridgeName: "bridge0", members: ["en5", "en6"],
                                          isActive: true)
        #expect(try BridgeRejoin.add("en6", to: membership, at: 1, writer: writer,
                                     policy: Fixtures.quickPolicy))
        #expect(writer.calls == [
            .addMember(port: "en6", bridge: "bridge0", position: 1),
            .removeMember(port: "en6", bridge: "bridge0"),
            .commitAndApply,
            .addMember(port: "en6", bridge: "bridge0", position: 1),
        ])
        let fresh = FakeWriter()
        fresh.bridgesValue = [BridgeSPI.Membership(bsdName: "bridge0", displayName: nil,
                                                   members: ["en5"])]
        #expect(try BridgeRejoin.add("en6", to: membership, at: 1, writer: fresh,
                                     policy: Fixtures.quickPolicy) == false)
        #expect(fresh.calls == [.addMember(port: "en6", bridge: "bridge0", position: 1)])

        let settled = KernelAgreement(agreed: true, settledOnItsOwn: true,
                                      retriedMembership: false, settledAfterRetry: false,
                                      reads: 1)
        #expect(settled.foldingRewrite(atAddTime: false) == settled)
        let folded = settled.foldingRewrite(atAddTime: true)
        #expect(folded.settledOnItsOwn == false)
        #expect(folded.retriedMembership)
        #expect(folded.settledAfterRetry)
        #expect(folded.reads == 1)
        let missed = KernelAgreement(agreed: false, settledOnItsOwn: false,
                                     retriedMembership: true, settledAfterRetry: false,
                                     reads: 8).foldingRewrite(atAddTime: true)
        #expect(missed.retriedMembership)
        #expect(missed.settledAfterRetry == false)
    }

    @Test("Another app holding the network is R12, and nothing is put back")
    func passesBusyStraightThrough() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        writer.intercept = { call in
            if case .lock = call {
                return NetworkConfigurationError.busy(step: "Lock network preferences", code: 1005)
            }
            return nil
        }
        #expect {
            try SetUpPorts(ports: [Fixtures.port]).perform(
                writer: writer, world: Fixtures.world(ifconfig: Fixtures.inOneBridge),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { error in
            guard case .busy = error as? NetworkConfigurationError else { return false }
            return true
        }
        #expect(writer.calls == [.lock])
    }
}
