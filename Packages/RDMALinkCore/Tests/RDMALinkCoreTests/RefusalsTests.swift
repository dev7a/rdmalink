import Foundation
import Testing
@testable import RDMALinkCore

/// Two Thunderbolt ports in a bridge that is down, plus Wi-Fi and Ethernet.
private let mixedFixture = """
lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
    inet 127.0.0.1 netmask 0xff000000
    inet6 ::1 prefixlen 128
bridge0: flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST> mtu 1500
    member: en5 flags=3<LEARNING,DISCOVER>
    member: en6 flags=3<LEARNING,DISCOVER>
    status: inactive
en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    inet6 fe80::5%en5 prefixlen 64 scopeid 0x14
    status: active
en6: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    inet6 fe80::6%en6 prefixlen 64 scopeid 0x15
    status: active
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    inet 10.77.78.1 netmask 0xfffffff8 broadcast 10.77.78.7
    status: active
utun3: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1000
    inet6 fe80::3%utun3 prefixlen 64 scopeid 0x1f
en13: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    inet 169.254.247.57 netmask 0xffff0000 broadcast 169.254.255.255
    status: active
"""

private func snapshot(_ text: String) -> InterfaceSnapshot {
    InterfaceSnapshot(interfaces: InterfaceSnapshot.parse(text))
}

private let farLeft = ObservedPort(bsdName: "en5", positionName: "Back, far left")
private let farRight = ObservedPort(bsdName: "en6", positionName: "Back, far right")

@Suite("R1 — two Macs are connected")
struct OneCableOnlyTests {
    @Test("One Mac on the end is fine")
    func acceptsOneLink() {
        var one = farLeft
        one.hasLinkedMac = true
        #expect(Refusals.oneCableOnly([one, farRight]) == nil)
        #expect(Refusals.oneCableOnly([]) == nil)
    }

    @Test("Two Macs on the end is a loop risk, and says which ports")
    func refusesTwoLinks() throws {
        var left = farLeft, right = farRight
        left.hasLinkedMac = true
        right.hasLinkedMac = true
        let refusal = try #require(Refusals.oneCableOnly([left, right]))
        #expect(refusal.code == .twoMacsConnected)
        #expect(refusal.headline == "Two Macs are connected")
        #expect(refusal.body.hasPrefix("Thunderbolt Bridge forwards Ethernet between Macs"))
        #expect(refusal.detail == "Back, far left and Back, far right each have a Mac on the end.")
        #expect(refusal.subjects == ["en5", "en6"])
    }

    @Test("Three reads as a list, not a pile")
    func namesEveryPort() throws {
        let ports = ["Back, far left", "Back, middle left", "Back, far right"]
            .enumerated()
            .map { ObservedPort(bsdName: "en\($0.offset)", positionName: $0.element,
                                hasLinkedMac: true) }
        let refusal = try #require(Refusals.oneCableOnly(ports))
        #expect(refusal.detail == "Back, far left, Back, middle left and Back, far right "
            + "each have a Mac on the end.")
    }
}

@Suite("R9 — the port is still in a bridge")
struct PortStillBridgedTests {
    @Test("A bridge that is down counts exactly as much as one that is up")
    func refusesWhileAMemberOfADownBridge() throws {
        let refusal = try #require(Refusals.portStillBridged(farLeft, in: snapshot(mixedFixture)))
        #expect(refusal.code == .portStillInBridge)
        #expect(refusal.headline == "macOS wouldn't let go of that port")
        #expect(refusal.detail == "en5 is still a member of bridge0.")
        #expect(refusal.subjects == ["en5"])
    }

    @Test("The bridge is named the way the rest of the app names it")
    func usesTheDisplayNameWhenThereIsOne() throws {
        let refusal = try #require(Refusals.portStillBridged(
            farLeft, in: snapshot(mixedFixture),
            bridgeNames: ["bridge0": "Thunderbolt Bridge"]))
        #expect(refusal.body.contains(
            "RDMALink couldn't remove Back, far left from Thunderbolt Bridge"))
    }

    @Test("A port in every bridge names every bridge")
    func namesEveryBridge() throws {
        let text = mixedFixture + """

        bridge1: flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST> mtu 1500
            member: en5 flags=3<LEARNING,DISCOVER>
        """
        let refusal = try #require(Refusals.portStillBridged(farLeft, in: snapshot(text)))
        #expect(refusal.detail == "en5 is still a member of bridge0 and bridge1.")
    }

    @Test("Out of every bridge is the only way through")
    func acceptsAStandalonePort() {
        let text = """
        en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            status: active
        """
        #expect(Refusals.portStillBridged(farLeft, in: snapshot(text)) == nil)
    }
}

@Suite("R5 — Thunderbolt is the only way in")
struct ManagementPathTests {
    @Test("Ethernet with a real address is another way to reach this Mac")
    func acceptsAnEthernetRoute() {
        #expect(Refusals.managementPathExists(in: snapshot(mixedFixture),
                                              thunderboltPorts: ["en5", "en6"]) == nil)
    }

    @Test("A Thunderbolt bridge is not a way out, and neither are tunnels or self-assigned addresses")
    func refusesWhenOnlyThunderboltIsLeft() throws {
        let text = mixedFixture
            .replacingOccurrences(of: "    inet 10.77.78.1 netmask 0xfffffff8 broadcast 10.77.78.7\n",
                                  with: "")
        let refusal = try #require(Refusals.managementPathExists(
            in: snapshot(text), thunderboltPorts: ["en5", "en6"]))
        #expect(refusal.code == .onlyRouteIsThunderbolt)
        #expect(refusal.headline == "This is how you're connected right now")
        #expect(refusal.body.contains("Connect Wi-Fi or Ethernet first"))
        #expect(refusal.subjects.contains("bridge0"))
    }

    @Test("A bridge with no Thunderbolt port in it is a route like any other")
    func acceptsANonThunderboltBridge() {
        let text = """
        bridge9: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            member: en20 flags=3<LEARNING,DISCOVER>
            inet 192.168.4.28 netmask 0xfffffc00 broadcast 192.168.7.255
            status: active
        en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet6 fe80::5%en5 prefixlen 64 scopeid 0x14
            status: active
        """
        #expect(Refusals.managementPathExists(in: snapshot(text),
                                              thunderboltPorts: ["en5"]) == nil)
    }

    @Test("A route that is down is not a route")
    func refusesWhenTheOnlyOtherRouteIsDown() throws {
        let text = """
        en0: flags=8862<BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet 10.77.78.1 netmask 0xfffffff8 broadcast 10.77.78.7
            status: inactive
        en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet6 fe80::5%en5 prefixlen 64 scopeid 0x14
            status: active
        """
        #expect(Refusals.managementPathExists(in: snapshot(text),
                                              thunderboltPorts: ["en5"]) != nil)
    }

    @Test("An interface that is up but carrying nothing is not a route")
    func ignoresAnUpButInactiveInterface() {
        // On macOS practically every interface carries the UP flag whatever its
        // carrier state: en8-en12, bridge0 and ap1 are all UP with
        // `status: inactive` on a Mac Studio. An unplugged Ethernet port with a
        // Manual address keeps both the flag and the address.
        let text = """
        en8: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet 192.168.9.4 netmask 0xffffff00 broadcast 192.168.9.255
            status: inactive
        en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet6 fe80::5%en5 prefixlen 64 scopeid 0x14
            status: active
        """
        #expect(Refusals.managementPathExists(in: snapshot(text),
                                              thunderboltPorts: ["en5"]) != nil)
    }

    @Test("A VM host bridge reaches the VM and nothing else")
    func ignoresAVirtualizationHostBridge() {
        // A headless Mac administered over Thunderbolt, with any
        // Virtualization.framework guest running. bridge100 is UP, active, and
        // carries a routable 192.168.64.1 - and reaches nobody.
        let text = """
        bridge100: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            member: vmenet0 flags=3<LEARNING,DISCOVER>
            inet 192.168.64.1 netmask 0xffffff00 broadcast 192.168.64.255
            status: active
        bridge0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            member: en5 flags=3<LEARNING,DISCOVER>
            inet 10.1.1.4 netmask 0xffffff00 broadcast 10.1.1.255
            status: active
        en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            status: active
        """
        #expect(Refusals.managementPathExists(in: snapshot(text),
                                              thunderboltPorts: ["en5"]) != nil)
    }

    @Test("What macOS says the default route is on wins over what can be inferred")
    func prefersThePrimaryInterface() {
        let text = snapshot(mixedFixture)
        // en0 has a routable address, but the default route is on the
        // Thunderbolt bridge: this is exactly how you are connected right now.
        #expect(Refusals.managementPathExists(in: text, thunderboltPorts: ["en5", "en6"],
                                              primaryInterfaces: ["bridge0"]) != nil)
        #expect(Refusals.managementPathExists(in: text, thunderboltPorts: ["en5", "en6"],
                                              primaryInterfaces: ["en5"]) != nil)
        #expect(Refusals.managementPathExists(in: text, thunderboltPorts: ["en5", "en6"],
                                              primaryInterfaces: ["en0"]) == nil)
    }

    @Test("Macs with no default route fall back to what can be observed")
    func fallsBackWhenMacOSDoesNotSay() {
        #expect(Refusals.managementPathExists(in: snapshot(mixedFixture),
                                              thunderboltPorts: ["en5", "en6"],
                                              primaryInterfaces: []) == nil)
    }

    @Test("Loopback, link-local and self-assigned addresses carry nobody")
    func knowsWhichAddressesCount() {
        #expect(Refusals.isRoutable("10.77.78.1"))
        #expect(Refusals.isRoutable("fdaf:6051:a2aa:1::1"))
        #expect(!Refusals.isRoutable("fe80::1%en0"))
        #expect(!Refusals.isRoutable("::1"))
        #expect(!Refusals.isRoutable("127.0.0.1"))
        #expect(!Refusals.isRoutable("169.254.247.57"))
    }
}

@Suite("R14 — the undo note has to be writable")
struct BaselineWritableTests {
    @Test("A writable folder is the whole requirement")
    func acceptsAWritableFolder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rdmalink-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // The note itself does not exist yet: the check looks at the folder.
        #expect(Refusals.baselineWritable(directory.appendingPathComponent("en5.json")) == nil)
    }

    @Test("A folder that cannot be written to stops everything")
    func refusesAnUnwritableFolder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rdmalink-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o500])
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let refusal = try #require(
            Refusals.baselineWritable(directory.appendingPathComponent("en5.json")))
        #expect(refusal.code == .baselineUnwritable)
        #expect(refusal.headline == "I can't write down how things are right now")
        #expect(refusal.detail == "The folder isn't writable.")
        #expect(refusal.body.contains("It won't change anything it can't undo."))
    }

    @Test("The check walks up to the folder that would hold the note")
    func looksAtTheNearestExistingFolder() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rdmalink-missing-" + UUID().uuidString, isDirectory: true)
        // Nothing is created: the writable temporary folder above it decides.
        #expect(Refusals.baselineWritable(directory.appendingPathComponent("en5.json")) == nil)
    }
}

@Suite("R10 and R11 — after something has already been written")
struct RollbackRefusalTests {
    @Test("R10 states the rollback first, and names what went wrong")
    func reportsARollback() {
        let refusal = Refusals.rolledBack(port: farLeft, bridgeName: "Thunderbolt Bridge")
        #expect(refusal.code == .rolledBack)
        #expect(refusal.headline == "Put back, safely")
        #expect(refusal.body.hasPrefix(
            "The new service wouldn't create, so RDMALink returned the port to Thunderbolt Bridge."))
        #expect(refusal.body.contains("it checked before telling you"))

        // R9's copy promises nothing at all was changed, so it cannot be the
        // read-back after a write. This is the one that can.
        let readBack = Refusals.rolledBack(port: farLeft, bridgeName: "Thunderbolt Bridge",
                                           cause: "macOS didn't actually let go of the port")
        #expect(readBack.code == .rolledBack)
        #expect(readBack.body.hasPrefix("macOS didn't actually let go of the port, so"))
    }

    @Test("R11 hands over the findings block, technical names and all")
    func reportsAFailedRollback() {
        let refusal = Refusals.rollbackFailed(
            port: farLeft, bridgeBSDName: "bridge0", bridgeDisplayName: "Thunderbolt Bridge",
            membersBefore: ["en5", "en6", "en7", "en8"], membersNow: ["en6", "en7", "en8"])
        #expect(refusal.code == .rollbackFailed)
        #expect(refusal.headline == "One thing needs your hand")
        #expect(refusal.body.contains("the port is currently in neither place"))
        #expect(refusal.detail == "Bridge: Thunderbolt Bridge (bridge0) · "
            + "Members before: en5, en6, en7, en8 · Members now: en6, en7, en8 · "
            + "The port to add back: en5 — Back, far left")
    }

    @Test("A bridge with no display name is named by its kernel name, not guessed at")
    func fallsBackToTheBSDName() {
        let refusal = Refusals.rollbackFailed(
            port: farLeft, bridgeBSDName: "bridge0",
            membersBefore: ["en5"], membersNow: [])
        #expect(refusal.body.contains("out of bridge0"))
    }
}

@Suite("R28 — RDMALink's own service has been taken over")
struct CreatedServiceEditedTests {
    @Test("It says what differs and offers to leave everything alone")
    func namesTheDifferences() {
        let refusal = Refusals.createdServiceEdited(
            port: farLeft, differences: ["it's been switched off", "IPv4 is set to Manual now"])
        #expect(refusal.code == .createdServiceEdited)
        #expect(refusal.body.contains("won't quietly delete something you've made your own"))
        #expect(refusal.detail == "it's been switched off and IPv4 is set to Manual now.")
        #expect(refusal.subjects == ["en5"])
    }
}
