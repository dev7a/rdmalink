import Testing
@testable import RDMALinkCore

@Suite("Reading this Mac, read-only")
struct LiveInterfaceTests {
    @Test("ifconfig -a parses into something that looks like a Mac", .tags(.liveRead))
    func readsTheKernel() throws {
        let snapshot = try InterfaceSnapshot.read()
        #expect(!snapshot.interfaces.isEmpty)
        #expect(snapshot["lo0"]?.isUp == true)
        let bridges = snapshot.interfaces.filter { $0.name.hasPrefix("bridge") }
        for bridge in bridges {
            print("\(bridge.name): up=\(bridge.isUp) active=\(bridge.isActive) members="
                + (bridge.members.isEmpty ? "none" : bridge.members.joined(separator: ", ")))
        }
        print("Interfaces: \(snapshot.interfaces.count); "
            + "bridges: \(bridges.map(\.name).joined(separator: ", "))")
    }

    @Test("A tool that will not talk is a failure with its exit status in it")
    func namesAFailedRead() {
        #expect(InterfaceReadFailure.ifconfigFailed(exitStatus: 1, output: "no").description
            == "/sbin/ifconfig -a failed (1): no")
    }
}
