import Foundation
import Testing
@testable import RDMALinkCore

// Bridge membership is two facts, not one. macOS keeps a bridge's member list
// in the network preferences as well as in the kernel, and the two can
// disagree — which is not a curiosity: while the preferences still list a
// port, `SCNetworkServiceCreate` refuses on it with `kSCStatusFailed`, whose
// `SCErrorString` is the single word "Failed!". Everything here is about the
// second fact.

@Suite("Bridge membership the preferences hold and the kernel does not")
struct NetworkStoredBridgeTests {

    /// This Mac on 2026-09-20: `bridge0` stored with `en5` in it and named
    /// Thunderbolt Bridge, while `ifconfig bridge0` listed no members at all.
    static func thisMacPreferences() -> [String: Any] {
        [
            "VirtualNetworkInterfaces": [
                "Bridge": [
                    "bridge0": [
                        "Interfaces": ["en5"],
                        "UserDefinedName": "Thunderbolt Bridge",
                    ],
                ],
            ],
            "CurrentSet": "/Sets/0",
        ]
    }

    static func plist(_ value: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    }

    /// `bridge0` with no members in the kernel, `en6` standalone, Ethernet as
    /// the way in so R5 is satisfied.
    static let kernelHasNoMembers = """
        bridge0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            status: inactive
        en6: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            status: active
        en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet 10.77.78.1 netmask 0xfffffff8 broadcast 10.77.78.7
            status: active
        """

    /// The stored `bridge0` this Mac had: `en5` and `en6` in it.
    static let storedBridge0 = BridgeSPI.Membership(
        bsdName: "bridge0", displayName: "Thunderbolt Bridge", members: ["en5", "en6"])

    // MARK: - The preferences file

    @Test("The preferences file is parsed in the shape this Mac has")
    func parsesThisMacsPreferences() throws {
        let bridges = try StoredBridges.parsePreferences(Self.plist(Self.thisMacPreferences()))
        #expect(bridges.count == 1)
        #expect(bridges[0].bsdName == "bridge0")
        #expect(bridges[0].displayName == "Thunderbolt Bridge")
        #expect(bridges[0].members == ["en5"])
        #expect(StoredBridges.names(in: bridges, containing: "en5") == ["bridge0"])
        #expect(StoredBridges.names(in: bridges, containing: "en6").isEmpty)
    }

    @Test("A bridge with no Interfaces array is a bridge with no members")
    func parsesABridgeWithNoMembers() throws {
        let data = try Self.plist([
            "VirtualNetworkInterfaces": [
                "Bridge": ["bridge1": ["UserDefinedName": "Spare"]],
            ],
        ])
        let bridges = try StoredBridges.parsePreferences(data)
        #expect(bridges.map(\.bsdName) == ["bridge1"])
        #expect(bridges[0].members.isEmpty)
        #expect(bridges[0].displayName == "Spare")
    }

    @Test("A file with no bridges at all parses to none, not to a failure")
    func parsesAFileWithNoBridges() throws {
        #expect(try StoredBridges.parsePreferences(Self.plist(["CurrentSet": "/Sets/0"])).isEmpty)
        #expect(try StoredBridges.parsePreferences(
            Self.plist(["VirtualNetworkInterfaces": ["VLAN": [String: Any]()]])).isEmpty)
    }

    /// A preferences file in the shape this Mac had, removed afterwards.
    static func temporaryPreferences() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "rdmalink-preferences-\(UUID().uuidString).plist")
        try plist(thisMacPreferences()).write(to: url)
        return url
    }

    /// An SPI read that fails the way a dropped symbol or a refused call does.
    static func failingSPI(_: String) throws -> [BridgeSPI.Membership] {
        throw BridgeSPIError.symbolMissing("SCBridgeInterfaceCopyAll")
    }

    @Test("A failed SPI read falls through to the preferences file")
    func readsTheFallbackFile() throws {
        let url = try Self.temporaryPreferences()
        defer { try? FileManager.default.removeItem(at: url) }

        // The SPI resolves on every Mac there is today, so the branch that
        // exists for the one where it does not is driven directly.
        let reading = StoredBridges.read(fileURL: url, spi: Self.failingSPI)
        #expect(reading.source == .preferencesFile)
        #expect(reading.bridges.map(\.bsdName) == ["bridge0"])
        #expect(reading.bridges[0].displayName == "Thunderbolt Bridge")
        #expect(reading.names(containing: "en5") == ["bridge0"])
    }

    @Test("The SPI is preferred while it answers")
    func prefersTheSPI() throws {
        let url = try Self.temporaryPreferences()
        defer { try? FileManager.default.removeItem(at: url) }
        let reading = StoredBridges.read(fileURL: url, spi: { _ in [Self.storedBridge0] })
        #expect(reading.source == .bridgeSPI)
        #expect(reading.bridges == [Self.storedBridge0])
    }

    @Test("Neither read answering is 'unavailable', which is not 'no bridges'")
    func saysSoWhenNeitherAnswers() {
        let absent = StoredBridges.read(
            fileURL: URL(fileURLWithPath: "/does-not-exist/preferences.plist"),
            spi: Self.failingSPI)
        #expect(absent.source == .unavailable)
        #expect(absent.bridges.isEmpty)
        // The distinction the whole design rests on: an empty list from an
        // answered read is a Mac with no bridges, and this is not that.
        #expect(StoredBridges.read(spi: { _ in [] }).source == .bridgeSPI)
    }

    @Test("An SPI read that answers nothing at all is a failure, not an empty Mac")
    func aFailedCopyAllIsNotAnEmptyList() {
        // `BridgeSPI.copyAll` throws rather than returning `[]` when the call
        // fails, which is what makes the fallback above reachable at all. The
        // error carries the code macOS gave.
        let error = BridgeSPIError.bridgeListUnreadable(code: 1001)
        #expect(error.description.contains("would not say what bridges"))
        #expect(error.description.contains("1001"))
    }

    // MARK: - The merge

    @Test("A port the preferences list is in the bridge, whatever the kernel says")
    func mergesStoredMembershipIntoTheInventory() {
        let kernel = Fixtures.snapshot(Self.kernelHasNoMembers)
        let bridges = Inventory.membership(of: "en6", kernel: kernel, stored: [Self.storedBridge0])
        #expect(bridges.map(\.name) == ["bridge0"])
        #expect(bridges[0].source == .stored)
        #expect(bridges[0].displayName == "Thunderbolt Bridge")
        // The kernel is not running it, and nothing here pretends otherwise.
        #expect(bridges[0].isUp == false)
    }

    @Test("A bridge only the kernel has is still a bridge the port is in")
    func keepsKernelOnlyMembership() {
        let kernel = Fixtures.snapshot(Fixtures.inOneBridge)
        let bridges = Inventory.membership(of: "en6", kernel: kernel, stored: [])
        #expect(bridges.map(\.name) == ["bridge0"])
        #expect(bridges[0].source == .kernel)
        #expect(bridges[0].isUp == true)
        #expect(bridges[0].displayName == nil)
    }

    @Test("A bridge both reads agree on is listed once, from both")
    func mergesAgreementIntoOneRow() {
        let kernel = Fixtures.snapshot(Fixtures.inOneBridge)
        let bridges = Inventory.membership(of: "en6", kernel: kernel, stored: [Self.storedBridge0])
        #expect(bridges.count == 1)
        #expect(bridges[0].source == .both)
        #expect(bridges[0].source.includesKernel)
        #expect(bridges[0].source.includesStored)
    }

    @Test("A USB-only receptacle has no interface, so it is in nothing")
    func aReceptacleWithNoNameIsInNothing() {
        #expect(Inventory.membership(of: "", kernel: Fixtures.snapshot(Fixtures.inOneBridge),
                                     stored: [Self.storedBridge0]).isEmpty)
    }

    // MARK: - R9

    @Test("R9 counts a membership only the preferences know about")
    func r9ReadsBothSources() throws {
        let port = ObservedPort(bsdName: "en6", positionName: "Back, far left",
                                hasLinkedMac: false)
        let kernel = Fixtures.snapshot(Self.kernelHasNoMembers)
        #expect(Refusals.portStillBridged(port, in: kernel, storedBridges: []) == nil)
        let refusal = try #require(Refusals.portStillBridged(
            port, in: kernel, storedBridges: [Self.storedBridge0],
            bridgeNames: ["bridge0": "Thunderbolt Bridge"]))
        #expect(refusal.code == .portStillInBridge)
        #expect(refusal.body.contains("couldn't remove Back, far left from Thunderbolt Bridge"))
        #expect(refusal.detail == "en6 is still a member of bridge0.")
    }

    @Test("A bridge both reads know about is named once in R9")
    func r9DoesNotDoubleCount() throws {
        let port = ObservedPort(bsdName: "en6", positionName: "Back, far left",
                                hasLinkedMac: false)
        let refusal = try #require(Refusals.portStillBridged(
            port, in: Fixtures.snapshot(Fixtures.inOneBridge),
            storedBridges: [Self.storedBridge0]))
        #expect(refusal.detail == "en6 is still a member of bridge0.")
    }

    // MARK: - The world an operation plans from

    @Test("The world takes the union, and the note records the stored member list")
    func theWorldTakesTheUnion() {
        let world = Fixtures.world(ifconfig: Self.kernelHasNoMembers,
                                   bridges: [Self.storedBridge0])
        #expect(world.bridges(containing: "en6") == ["bridge0"])
        #expect(world.kernelBridges(containing: "en6").isEmpty)
        #expect(world.storedBridges(containing: "en6") == ["bridge0"])
        // The member list the SPI's remove is checked against. Reading it from
        // `ifconfig` alone would make every stored member look like a
        // stranger's and `resolveRecorded` would refuse the bridge.
        #expect(world.membership(ofBridge: "bridge0").members == ["en5", "en6"])
        #expect(world.membership(ofBridge: "bridge0").displayName == "Thunderbolt Bridge")
    }

    // MARK: - The error configd gives instead of a reason

    @Test("A create refused while only the committed settings claim the port")
    func namesTheBridgeFromTheCommittedConfiguration() throws {
        // The shape `SetUpPorts` is in when it gets here: the member has
        // already been taken out of the session's copy, so only a fresh read
        // of what is on disk can say why configd refused.
        let error = StandalonePortSetup.createFailure(
            bsdName: "en5", code: 1001, session: [], committed: [Self.storedBridge0])
        guard case let .interfaceIsStoredBridgeMember(bsdName, bridges, code) = error else {
            Issue.record("expected the stored-member diagnosis, got \(error)")
            return
        }
        #expect(bsdName == "en5")
        #expect(bridges == ["bridge0"])
        #expect(code == 1001)
    }

    @Test("A bridge both stored reads name is named once")
    func doesNotNameTheBridgeTwice() {
        let error = StandalonePortSetup.createFailure(
            bsdName: "en5", code: 1001,
            session: [Self.storedBridge0], committed: [Self.storedBridge0])
        #expect(error == .interfaceIsStoredBridgeMember(
            bsdName: "en5", bridges: ["bridge0"], code: 1001))
    }

    @Test("A 1001 with nothing claiming the port stays the step that failed")
    func keepsTheOrdinaryErrorWhenNoBridgeClaimsThePort() {
        let error = StandalonePortSetup.createFailure(
            bsdName: "en5", code: 1001, session: [], committed: [])
        #expect(error.scStatus == 1001)
        guard case .stepFailed = error else {
            Issue.record("expected the ordinary failure, got \(error)")
            return
        }
    }

    @Test("Another code is not diagnosed as a bridge membership")
    func doesNotBlameTheBridgeForOtherCodes() {
        let error = StandalonePortSetup.createFailure(
            bsdName: "en5", code: 1003, session: [Self.storedBridge0], committed: [])
        guard case .stepFailed = error else {
            Issue.record("expected the ordinary failure, got \(error)")
            return
        }
    }

    @Test("A refused create names the bridge that is still holding the port")
    func nameTheBridgeBehindKSCStatusFailed() {
        let error = NetworkConfigurationError.interfaceIsStoredBridgeMember(
            bsdName: "en5", bridges: ["bridge0"], code: 1001)
        #expect(error.scStatus == 1001)
        let text = error.description
        #expect(text.contains("en5"))
        #expect(text.contains("bridge0"))
        #expect(text.contains("saved network settings"))
        // The whole point: not the bare word macOS offers.
        #expect(text != "Create the RDMA service: Failed!")
        #expect(text.contains("Failed!"), "the code macOS gave is still quoted")
    }
}
