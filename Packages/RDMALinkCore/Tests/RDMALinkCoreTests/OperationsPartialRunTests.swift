import Foundation
import Testing

@testable import RDMALinkCore

/// The answers to UX_SPEC §10 question 4 and the promises around them: a
/// later port's failure rolls back **only that port**, a burst that refuses
/// before it has changed anything leaves no note behind, and the kernel wait
/// is budgeted on the wall clock rather than on the sleeps it took.
@Suite("A multi-port burst, and what it leaves behind")
struct OperationsPartialRunTests {

    private static let stepFailed = NetworkConfigurationError.stepFailed(
        step: "Create the RDMA service", code: 1004, message: "would not create")

    /// en6 and en7 both in bridge0, with Ethernet as the way in.
    private static let twoInOneBridge = """
        bridge0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            member: en5 flags=3<LEARNING,DISCOVER>
            member: en6 flags=3<LEARNING,DISCOVER>
            member: en7 flags=3<LEARNING,DISCOVER>
            status: active
        en6: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            status: active
        en7: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            status: active
        en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet 10.77.78.1 netmask 0xfffffff8 broadcast 10.77.78.7
            status: active
        """

    /// en7 back where it started, en6 out: what the kernel says once the
    /// second port has been rolled back.
    private static let secondPortBack = """
        bridge0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            member: en5 flags=3<LEARNING,DISCOVER>
            member: en7 flags=3<LEARNING,DISCOVER>
            status: active
        en6: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            status: active
        en7: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            status: active
        en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet 10.77.78.1 netmask 0xfffffff8 broadcast 10.77.78.7
            status: active
        """

    /// Neither port is in a bridge any more.
    private static let bothStandalone = """
        bridge0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            member: en5 flags=3<LEARNING,DISCOVER>
            status: active
        en6: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            status: active
        en7: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            status: active
        en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet 10.77.78.1 netmask 0xfffffff8 broadcast 10.77.78.7
            status: active
        """

    private static let first = OperationPort(
        bsdName: "en6", receptacle: 1, positionName: "Back, far left", link: .empty)
    private static let second = OperationPort(
        bsdName: "en7", receptacle: 2, positionName: "Back, far right", link: .empty)

    private static func twoPortWorld() -> ObservedWorld {
        Fixtures.world(
            ifconfig: twoInOneBridge,
            bridges: [BridgeSPI.Membership(bsdName: "bridge0",
                                           displayName: "Thunderbolt Bridge",
                                           members: ["en5", "en6", "en7"])],
            ports: [first, second])
    }

    @Test("The second port's failure leaves the first port set up, and says so")
    func firstPortStands() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        let phase = RollbackPhase()
        writer.kernel = { _ in
            Fixtures.snapshot(phase.secondPortIsBack ? Self.secondPortBack : Self.bothStandalone)
        }
        writer.intercept = { call in
            if case let .createService(interface, _) = call, interface == "en7" {
                return Self.stepFailed
            }
            if case let .addMember(port, _, _) = call, port == "en7" {
                phase.secondPortIsBack = true
            }
            return nil
        }

        let result = try SetUpPorts(ports: [Self.first, Self.second]).perform(
            writer: writer, world: Self.twoPortWorld(),
            environment: Fixtures.environment(store: store), progress: { _, _ in })

        // The port that landed stands: committed, verified, noted.
        #expect(result.ports.map(\.bsdName) == ["en6"])
        #expect(result.ports.first?.leftBridges == ["Thunderbolt Bridge"])
        #expect((try? store.load(port: "en6")) != nil)

        // The port that did not is named, with its own refusal and nobody
        // else's — R10 is never printed as a claim about the whole run.
        #expect(result.unfinished?.bsdName == "en7")
        #expect(result.unfinished?.positionName == "Back, far right")
        #expect(result.unfinished?.refusal.code == .rolledBack)

        // Only the failed port was put back.
        #expect(writer.calls.contains(.addMember(port: "en7", bridge: "bridge0", position: 2)))
        #expect(!writer.calls.contains(.addMember(port: "en6", bridge: "bridge0", position: 1)))
        #expect(!writer.calls.contains(.deleteService(identifier: "NEW-SERVICE-ID",
                                                      expecting: "en6")))
    }

    @Test("A run where nothing landed still throws its refusal, exactly as before")
    func singlePortStillThrows() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        writer.intercept = { call in
            if case .createService = call { return Self.stepFailed }
            return nil
        }
        #expect {
            try SetUpPorts(ports: [Fixtures.port]).perform(
                writer: writer, world: Fixtures.world(ifconfig: Fixtures.inOneBridge),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { ($0 as? Refusal)?.code == .rolledBack }
    }

    @Test("R9: a burst that changed nothing at all leaves no note behind")
    func removesTheNoteWhenNothingWasWritten() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        writer.intercept = { call in
            if case .removeMember = call {
                return BridgeSPIError.memberNotFound(bsdName: "en6", bridge: "bridge0")
            }
            return nil
        }
        #expect {
            try SetUpPorts(ports: [Fixtures.port]).perform(
                writer: writer, world: Fixtures.world(ifconfig: Fixtures.inOneBridge),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { ($0 as? Refusal)?.code == .portStillInBridge }

        #expect((try? store.load(port: "en6")) == nil,
                "R9 promises it changed nothing at all, so no note may claim otherwise")
    }

    @Test("R12: the lock being held is R12, and it leaves no note behind either")
    func removesTheNoteWhenTheNetworkIsBusy() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.standalone) }
        var locks = 0
        writer.intercept = { call in
            if case .lock = call {
                locks += 1
                return nil
            }
            if case .commitAndApply = call {
                return NetworkConfigurationError.busy(step: "Commit network preferences",
                                                      code: -1)
            }
            return nil
        }
        #expect {
            try SetUpPorts(ports: [Fixtures.port]).perform(
                writer: writer, world: Fixtures.world(ifconfig: Fixtures.inOneBridge),
                environment: Fixtures.environment(store: store), progress: { _, _ in })
        } throws: { ($0 as? Refusal)?.code == .networkBusy }

        #expect((try? store.load(port: "en6")) == nil)
    }

    @Test("The rollback reverses the checklist, row by row")
    func reportsTheReversal() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        writer.intercept = { call in
            if case .createService = call { return Self.stepFailed }
            return nil
        }
        let log = ProgressLog()
        _ = try? SetUpPorts(ports: [Fixtures.port]).perform(
            writer: writer, world: Fixtures.world(ifconfig: Fixtures.inOneBridge),
            environment: Fixtures.environment(store: store), progress: log.record)

        let reversed = log.rows.filter { $0.state == .reversing }.map(\.step)
        // Only the rows that really happened are un-ticked: the service never
        // existed, so its row was never ticked either.
        #expect(reversed == [.leaveBridge(named: "Thunderbolt Bridge")])
        // And the row ends back where it started, so the checklist reads as
        // pending rather than as done.
        #expect(log.rows.last?.state == .pending)
    }

    @Test("A wait that runs out of wall clock is R8, not R10")
    func budgetExhaustionIsTheCredential() throws {
        let store = Fixtures.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let writer = FakeWriter()
        // The kernel never agrees, and there is no time left to wait for it.
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        let spent = KernelWaitPolicy(window: .milliseconds(30), interval: .milliseconds(10),
                                     budget: .zero, pause: { _ in })
        let environment = OperationEnvironment(
            archetype: .studioFour, store: store,
            log: ChangeLog(url: store.directory.appending(path: "changes.jsonl")),
            policy: spent)

        #expect {
            try SetUpPorts(ports: [Fixtures.port]).perform(
                writer: writer, world: Fixtures.world(ifconfig: Fixtures.inOneBridge),
                environment: environment, progress: { _, _ in })
        } throws: { ($0 as? Refusal)?.code == .credentialExpired }
    }

    @Test("The wait counts the reads, not only the sleeps")
    func theWaitIsOnTheWallClock() throws {
        let writer = FakeWriter()
        writer.kernel = { _ in Fixtures.snapshot(Fixtures.inOneBridge) }
        // A read that costs real time, and a budget smaller than two of them.
        let slow = KernelWaitPolicy(
            window: .seconds(30), interval: .milliseconds(1), budget: .milliseconds(30),
            pause: { _ in Thread.sleep(forTimeInterval: 0.02) })
        let agreement = try KernelVerification.wait(writer: writer, policy: slow) { _ in false }
        #expect(agreement.agreed == false)
        #expect(agreement.ranOutOfTime, "the budget is wall clock, not a count of sleeps")
        #expect(agreement.reappliedConfiguration == false,
                "a wait that ran out of time does not then spend more of it applying again")
    }
}

/// Mutable state the fake kernel and the fake writer share, so a two-port
/// run can answer differently before and after the second port is put back.
private final class RollbackPhase {
    var secondPortIsBack = false
}

@Suite("S4b's two timers")
struct IdentifyClockTests {

    @Test("Nothing seen for sixty seconds is the timeout, and it really arrives")
    func timesOut() {
        #expect(IdentifyClock.tick(watchingFor: .seconds(59), unpluggedFor: nil)
            == .keepWatching)
        #expect(IdentifyClock.tick(watchingFor: .seconds(60), unpluggedFor: nil) == .timedOut)
        #expect(IdentifyClock.tick(watchingFor: .seconds(600), unpluggedFor: nil) == .timedOut)
    }

    @Test("An unplug is already an answer, so it nudges rather than times out")
    func nudges() {
        #expect(IdentifyClock.tick(watchingFor: .seconds(600), unpluggedFor: .seconds(29))
            == .keepWatching)
        #expect(IdentifyClock.tick(watchingFor: .seconds(600), unpluggedFor: .seconds(30))
            == .nudge)
    }
}
