import Testing
@testable import RDMALinkCore

/// The fixture the reference tool self-tested against: a bridge that is **down**
/// but still has a member, one usable link-local address, and one that is
/// tentative and therefore not usable.
private let bridgedFixture = """
bridge4: flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST> mtu 1500
    member: en3 flags=3<LEARNING,DISCOVER>
en3: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    inet6 fe80::1%en3 prefixlen 64 scopeid 0x4
    status: active
en4: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    inet6 fe80::2%en4 prefixlen 64 tentative
    status: active
"""

@Suite("ifconfig parser")
struct InterfaceStateParsingTests {
    @Test("Reads bridges, flags, status and addresses")
    func parsesTheReferenceFixture() {
        let parsed = InterfaceSnapshot.parse(bridgedFixture)
        #expect(parsed.count == 3)
        #expect(parsed[0].name == "bridge4")
        #expect(parsed[0].isUp == false)
        #expect(parsed[0].members == ["en3"])
        #expect(parsed[0].isBridge)
        #expect(parsed[1].name == "en3")
        #expect(parsed[1].isUp)
        #expect(parsed[1].isActive)
        #expect(parsed[1].linkLocalAddresses == ["fe80::1"])
        #expect(parsed[1].addresses == ["fe80::1%en3"])
    }

    @Test("A tentative address is not a usable link-local address")
    func skipsTentativeAddresses() {
        let parsed = InterfaceSnapshot.parse(bridgedFixture)
        #expect(parsed[2].linkLocalAddresses.isEmpty)
        #expect(parsed[2].addresses == ["fe80::2%en4"])
    }

    @Test("Duplicated and detached addresses are not usable either")
    func skipsDuplicatedAndDetachedAddresses() {
        let text = """
        en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet6 fe80::3%en5 prefixlen 64 duplicated
            inet6 fe80::4%en5 prefixlen 64 detached
            inet6 fe80::5%en5 prefixlen 64 secured scopeid 0x14
        """
        #expect(InterfaceSnapshot.parse(text)[0].linkLocalAddresses == ["fe80::5"])
    }

    @Test("A bridge that is down still owns its member")
    func findsBridgesRegardlessOfState() {
        let snapshot = InterfaceSnapshot(interfaces: InterfaceSnapshot.parse(bridgedFixture))
        #expect(snapshot.bridges(containing: "en3") == ["bridge4"])
        #expect(snapshot.bridges(containing: "en4").isEmpty)
        #expect(snapshot.bridgeNames == ["bridge4"])
        #expect(snapshot["en3"]?.isActive == true)
        #expect(snapshot["en99"] == nil)
    }

    @Test("Indented detail lines never open an interface")
    func ignoresIndentedConfigurationBlocks() {
        let text = """
        bridge0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            Configuration:
                id 0:0:0:0:0:0 priority 0 hellotime 0 fwddelay 0
                ipfilter disabled flags 0x0
            member: en5 flags=3<LEARNING,DISCOVER>
            status: inactive
        en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet 10.77.78.1 netmask 0xfffffff8 broadcast 10.77.78.7
            status: active
        """
        let parsed = InterfaceSnapshot.parse(text)
        #expect(parsed.map(\.name) == ["bridge0", "en0"])
        #expect(parsed[0].members == ["en5"])
        #expect(parsed[0].isActive == false)
        #expect(parsed[1].addresses == ["10.77.78.1"])
    }

    @Test("An empty read parses to nothing rather than guessing")
    func parsesEmptyOutput() {
        #expect(InterfaceSnapshot.parse("").isEmpty)
    }
}
