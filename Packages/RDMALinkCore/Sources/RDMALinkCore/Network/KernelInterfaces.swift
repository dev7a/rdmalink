import Darwin
import Foundation

/// The kernel's network interfaces, read in-process: what `ifconfig -a` prints
/// and ``InterfaceSnapshot/parse(_:)`` reads out of it, without the process.
///
/// Every field comes from where `ifconfig` itself gets it (Apple's
/// network_cmds, `ifconfig.tproj`):
///
/// - the interfaces, their `UP` flag and their addresses from `getifaddrs`,
///   in its order, which is the order `ifconfig` prints them in;
/// - `status: active` from `SIOCGIFXMEDIA`: `ifconfig` prints a status only
///   when the call answers with at least one media type and `IFM_AVALID`, and
///   says `active` only with `IFM_ACTIVE`;
/// - an IPv6 address's tentative, duplicated and detached flags from
///   `SIOCGIFAFLAG_IN6` — an address that call refuses is one `ifconfig` does
///   not print at all — and its text from `getnameinfo`, once the scope the
///   kernel embeds in a link-local address is moved to `sin6_scope_id`, so
///   it reads `fe80::1%en5` exactly as `ifconfig` prints it;
/// - bridge membership from `_SCBridgeInterfaceCopyActive`
///   (``BridgeSPI/activeBridges()``), which asks the kernel with the same
///   `SIOCGDRVSPEC`/`BRDGGIFS` call `ifconfig` makes — the call whose
///   structures are in no public header.
///
/// That SPI is configd's, and it leaves bridges out on purpose: any whose unit
/// number has three digits — `bridge100` and up, which Internet Sharing and
/// virtual machines make — and any that answers `EBUSY`. A port must be out of
/// every bridge, those included (``InterfaceState``), so when `getifaddrs`
/// shows a bridge the SPI did not report, or the SPI is missing or fails, this
/// answers `nil` and ``InterfaceSnapshot/read(using:)`` runs `ifconfig -a`.
enum KernelInterfaces {
    /// Every interface, or `nil` when the in-process read cannot answer for
    /// all of them.
    ///
    /// - Parameter activeBridges: the kernel's bridges and their members;
    ///   ``BridgeSPI/activeBridges()`` unless a test says otherwise.
    static func read(
        activeBridges: () throws -> [BridgeSPI.Membership] = BridgeSPI.activeBridges
    ) -> [InterfaceState]? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { freeifaddrs(head) }
        // `SIOCGIFAFLAG_IN6` needs an IPv6 socket; the media call takes any.
        let descriptor = socket(AF_INET6, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var interfaces: [InterfaceState] = []
        var position: [String: Int] = [:]
        var bridges: [String] = []
        var next = head
        while let entry = next {
            next = entry.pointee.ifa_next
            let name = String(cString: entry.pointee.ifa_name)
            let index: Int
            if let known = position[name] {
                index = known
            } else {
                index = interfaces.count
                position[name] = index
                interfaces.append(InterfaceState(
                    name: name,
                    isUp: entry.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                    isActive: linkIsActive(name, descriptor: descriptor)
                ))
            }
            guard let address = entry.pointee.ifa_addr else { continue }
            switch Int32(address.pointee.sa_family) {
            case AF_LINK:
                if let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self),
                   Int32(data.pointee.ifi_type) == IFT_BRIDGE {
                    bridges.append(name)
                }
            case AF_INET:
                if let text = ipv4Text(address) {
                    interfaces[index].addresses.append(text)
                }
            case AF_INET6:
                let ipv6 = UnsafeRawPointer(address).load(as: sockaddr_in6.self)
                guard let flags = addressFlags(ipv6, on: name, descriptor: descriptor) else {
                    continue
                }
                let text = ipv6Text(ipv6)
                interfaces[index].addresses.append(text)
                // The parser's own rule, on the same printed text.
                if text.hasPrefix("fe80:"), flags & unusable == 0 {
                    interfaces[index].linkLocalAddresses.append(
                        String(text.split(separator: "%")[0])
                    )
                }
            default:
                break
            }
        }

        guard let reported = try? activeBridges() else { return nil }
        var members: [String: [String]] = [:]
        for bridge in reported where members[bridge.bsdName] == nil {
            members[bridge.bsdName] = bridge.members
        }
        for name in bridges {
            guard let list = members[name], let index = position[name] else { return nil }
            interfaces[index].members = list
        }
        return interfaces
    }

    /// Tentative, duplicated and detached: the three flags `ifconfig` prints
    /// as words the parser leaves an address out for.
    static let unusable = Int32(IN6_IFF_TENTATIVE | IN6_IFF_DUPLICATED | IN6_IFF_DETACHED)

    /// `_IOWR('i', number, T)`, which Swift cannot import: `IOC_INOUT`, the
    /// argument's size in the 13 bits `IOCPARM_MASK` leaves it, the group and
    /// the number.
    static func readWriteRequest<T>(_ number: UInt, _ argument: T.Type) -> UInt {
        0xC000_0000
            | (UInt(MemoryLayout<T>.size) & 0x1FFF) << 16
            | UInt(UInt8(ascii: "i")) << 8
            | number
    }

    /// `SIOCGIFXMEDIA`, `ifconfig`'s media and status call.
    static let getExtendedMedia = readWriteRequest(72, ifmediareq.self)
    /// `SIOCGIFAFLAG_IN6`, one IPv6 address's flags.
    static let getAddressFlags6 = readWriteRequest(73, in6_ifreq.self)

    /// `status: active`, as `ifconfig` decides it.
    static func linkIsActive(_ name: String, descriptor: Int32) -> Bool {
        var request = ifmediareq()
        copy(name, into: &request.ifm_name)
        guard ioctl(descriptor, getExtendedMedia, &request) == 0, request.ifm_count > 0 else {
            return false
        }
        let status = request.ifm_status
        return status & IFM_AVALID != 0 && status & IFM_ACTIVE != 0
    }

    /// The address's `IN6_IFF_*` flags, or `nil` when the kernel will not
    /// say — an address `ifconfig` then leaves out.
    static func addressFlags(_ address: sockaddr_in6, on name: String, descriptor: Int32) -> Int32? {
        var request = in6_ifreq()
        copy(name, into: &request.ifr_name)
        request.ifr_ifru.ifru_addr = address
        guard ioctl(descriptor, getAddressFlags6, &request) == 0 else { return nil }
        return request.ifr_ifru.ifru_flags6
    }

    /// `inet_ntoa`'s dotted quad.
    static func ipv4Text(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var ipv4 = UnsafeRawPointer(address).load(as: sockaddr_in.self).sin_addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &ipv4, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        return CBuffer.string(buffer)
    }

    /// The address as `ifconfig` prints it: a link-local address's embedded
    /// scope moved to `sin6_scope_id`, then `getnameinfo` with numeric hosts,
    /// which names the scope — `fe80::1%en5`.
    static func ipv6Text(_ address: sockaddr_in6) -> String {
        var ipv6 = address
        let embedded = withUnsafeMutableBytes(of: &ipv6.sin6_addr) { bytes -> UInt32? in
            let linkLocal = bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80
            guard linkLocal, bytes[2] != 0 || bytes[3] != 0 else { return nil }
            let scope = UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            bytes[2] = 0
            bytes[3] = 0
            return scope
        }
        if let embedded, ipv6.sin6_scope_id == 0 { ipv6.sin6_scope_id = embedded }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(ipv6.sin6_len)
        let named = withUnsafePointer(to: ipv6) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
            }
        }
        if named != 0 {
            _ = inet_ntop(AF_INET6, &ipv6.sin6_addr, &buffer, socklen_t(buffer.count))
        }
        return CBuffer.string(buffer)
    }

    /// An interface name into a fixed `IFNAMSIZ` field, NUL-terminated.
    private static func copy<Field>(_ name: String, into field: inout Field) {
        withUnsafeMutableBytes(of: &field) { bytes in
            bytes.initializeMemory(as: UInt8.self, repeating: 0)
            for (offset, byte) in name.utf8.prefix(bytes.count - 1).enumerated() {
                bytes[offset] = byte
            }
        }
    }
}
