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

    @Test("The fallback reads the file when the SPI is not the source")
    func readsTheFallbackFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "rdmalink-preferences-\(UUID().uuidString).plist")
        try Self.plist(Self.thisMacPreferences()).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // The real read prefers the SPI, which resolves on this Mac, so the
        // file path is exercised through the parser it delegates to — and the
        // missing-file case proves the honest answer for "neither answered".
        let reading = StoredBridges.read(fileURL: url)
        #expect(reading.source == .bridgeSPI || reading.source == .preferencesFile)

        let absent = StoredBridges.read(
            clientName: "", fileURL: url.appending(path: "does-not-exist"))
        #expect(absent.source != .preferencesFile)
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
        #expect(Refusals.portStillBridged(port, in: kernel) == nil)
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
