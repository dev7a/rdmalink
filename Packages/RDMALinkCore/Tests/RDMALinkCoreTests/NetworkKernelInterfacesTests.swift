import Darwin
import Foundation
import Testing
@testable import RDMALinkCore

/// The in-process read is `ifconfig -a` without the process, so it is checked
/// against `ifconfig -a` itself, on whatever Mac runs the tests.
@Suite("Kernel interfaces, read in-process")
struct NetworkKernelInterfacesTests {

    @Test("The two ioctl requests are the SDK's")
    func requestNumbersMatchTheSDK() {
        // `SIOCGIFXMEDIA` and `SIOCGIFAFLAG_IN6` from <sys/sockio.h> and
        // <netinet6/in6_var.h>, printed by a C program against the macOS 27
        // SDK. A struct that changed size would change these.
        #expect(KernelInterfaces.getExtendedMedia == 0xC02C_6948)
        #expect(KernelInterfaces.getAddressFlags6 == 0xC120_6949)
    }

    @Test("A link-local address's embedded scope reads as ifconfig prints it")
    func embeddedScopeIsNamed() {
        // fe80:1::1 with no scope id: the kernel's way of carrying interface
        // index 1, which is lo0 on every Mac.
        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        withUnsafeMutableBytes(of: &address.sin6_addr) { bytes in
            bytes[0] = 0xFE
            bytes[1] = 0x80
            bytes[3] = 0x01
            bytes[15] = 0x01
        }
        #expect(KernelInterfaces.ipv6Text(address) == "fe80::1%lo0")

        var global = sockaddr_in6()
        global.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        global.sin6_family = sa_family_t(AF_INET6)
        withUnsafeMutableBytes(of: &global.sin6_addr) { bytes in
            bytes[0] = 0x20
            bytes[1] = 0x01
            bytes[2] = 0x0D
            bytes[3] = 0xB8
            bytes[15] = 0x01
        }
        #expect(KernelInterfaces.ipv6Text(global) == "2001:db8::1")
    }

    @Test("This Mac reads the same in-process as through ifconfig -a")
    func matchesIfconfig() throws {
        let output = try CommandRunner().run("/sbin/ifconfig", ["-a"])
        let parsed = InterfaceSnapshot.parse(output.text)
        guard let read = KernelInterfaces.read() else {
            // A bridge the SPI leaves out — bridge100 and up — or no SPI:
            // the read falls back to ifconfig, which is what it is for.
            print("in-process read fell back to ifconfig -a on this Mac")
            return
        }
        print("in-process read: \(read.count) interfaces, ifconfig: \(parsed.count)")
        #expect(read.map(\.name) == parsed.map(\.name))
        for interface in parsed {
            #expect(read.first { $0.name == interface.name } == interface)
        }
    }

    @Test("A bridge the SPI does not report sends the read back to ifconfig")
    func unreportedBridgeFallsBack() {
        struct Unavailable: Error {}
        #expect(KernelInterfaces.read(activeBridges: { throw Unavailable() }) == nil)

        let bridged = (try? CommandRunner().run("/sbin/ifconfig", ["-a"]))
            .map { InterfaceSnapshot.parse($0.text).contains(where: \.isBridge) } ?? false
        if bridged {
            #expect(KernelInterfaces.read(activeBridges: { [] }) == nil)
        }
    }
}
