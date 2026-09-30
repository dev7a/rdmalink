import Darwin
import Foundation

/// Everything a port read depends on, reduced to what is cheap to look at:
/// the cheap half of the one-second state diff (UX_SPEC §7.4).
///
/// The full port read runs `ifconfig -a`, opens the stored network
/// preferences twice and reads the notes. Measured on Mac15,14 (macOS 27.2, a
/// release build), that is about 15 ms of CPU, most of it the `ifconfig`
/// spawn and the registry lookup and localized name `NetworkServices` pays
/// for every service — and the utility task it runs on lands on the
/// efficiency cores, where it costs two to three times that. Once a second
/// for as long as the window was open, it was the largest cost after the
/// stage, and it was paid to learn that nothing had changed.
///
/// This is the registry pass the full read makes anyway, one `getifaddrs` and
/// two `stat`s: about 1.5 ms on the same Mac, nearly all of it the registry.
/// ``PortReadGate`` decides from it when the full read is owed.
public struct PortStateSignature: Sendable, Equatable {
    /// The receptacles, their link status and their domains: a cable plugged
    /// in or pulled, a Mac arriving at the far end.
    var rows: [PortInventory.PortRow]
    /// Positions and plug presence, the USB-only receptacles included.
    var enrichment: ChassisEnrichment
    /// The kernel's Thunderbolt ports and every bridge, as `getifaddrs` has
    /// them: their flags and their addresses.
    var interfaces: [InterfaceMark]
    /// The stored network configuration: every service and every stored
    /// bridge. `nil` when there is no such file.
    var preferences: FileMark?
    /// The notes folder. A note is always renamed into place, so the folder
    /// itself changes with every save and every delete. `nil` until the
    /// folder exists.
    var notes: FileMark?

    /// Reads the signature, or `nil` when the registry or the interface list
    /// would not answer — which the gate takes as a reason to read, never as
    /// a reason to skip.
    ///
    /// - Parameter notesDirectory: the folder the notes are read from.
    public static func read(notesDirectory: URL) -> PortStateSignature? {
        guard let rows = try? PortInventory.readRows() else { return nil }
        let enrichment = ChassisProbe.read()
        guard let interfaces = InterfaceMark.read(ports: Set(rows.map(\.bsdName))) else {
            return nil
        }
        return PortStateSignature(
            rows: rows,
            enrichment: enrichment,
            interfaces: interfaces,
            preferences: FileMark.read(StoredBridges.preferencesFileURL.path),
            notes: FileMark.read(notesDirectory.path)
        )
    }
}

/// One `getifaddrs` entry: an interface, its flags and one of its addresses.
struct InterfaceMark: Sendable, Equatable {
    var name: String
    var flags: UInt32
    /// The `sockaddr` exactly as the kernel wrote it. For `AF_LINK` that is the
    /// interface's index, type and hardware address, and never its traffic
    /// counters, which live behind `ifa_data` and change with every packet.
    var address: [UInt8]

    /// Up, running, and whether a bridge has taken the interface promiscuous.
    /// The other flags either never change or, like `IFF_OACTIVE`, change
    /// with traffic.
    static let watchedFlags = UInt32(IFF_UP | IFF_RUNNING | IFF_PROMISC)

    /// The entries for `ports` and for every bridge, in the kernel's order.
    /// Other interfaces are left out: Wi-Fi rotating a temporary address or
    /// AWDL coming up for AirDrop says nothing about a Thunderbolt port, and
    /// would buy a full read each time. Bridges are `bridgeN` whoever makes
    /// them — the kernel names the interfaces of its `bridge` family.
    static func read(ports: Set<String>) -> [InterfaceMark]? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { freeifaddrs(head) }
        var marks: [InterfaceMark] = []
        var next = head
        while let entry = next {
            next = entry.pointee.ifa_next
            let name = String(cString: entry.pointee.ifa_name)
            guard ports.contains(name) || name.hasPrefix("bridge") else { continue }
            let address = entry.pointee.ifa_addr.map {
                Array(UnsafeRawBufferPointer(start: $0, count: Int($0.pointee.sa_len)))
            } ?? []
            marks.append(InterfaceMark(
                name: name, flags: entry.pointee.ifa_flags & watchedFlags, address: address
            ))
        }
        return marks
    }
}

/// Which file is at a path, and which version of it: `stat`'s identity and
/// both of its clocks. An atomic replace is a new inode; an edit in place
/// moves the modification time, which APFS keeps to the nanosecond.
struct FileMark: Sendable, Equatable {
    var device: Int32
    var inode: UInt64
    var size: Int64
    var modified: [Int]
    var changed: [Int]

    /// `nil` when nothing is there.
    static func read(_ path: String) -> FileMark? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return FileMark(
            device: info.st_dev,
            inode: info.st_ino,
            size: info.st_size,
            modified: [info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec],
            changed: [info.st_ctimespec.tv_sec, info.st_ctimespec.tv_nsec]
        )
    }
}

/// Decides which wake-ups of the one-second state diff pay for the full port
/// read.
///
/// UX_SPEC §7.4 promises that link state, bridge membership, service and
/// address changes land within a second, including changes made in System
/// Settings. The signature is read every second, and the full read follows:
///
/// - whenever the signature moves or the store sent a notification;
/// - on every wake-up for ``settle`` after that, because two changes follow a
///   first one without moving the signature again: `ifconfig` lists a new
///   `fe80::` address only once duplicate address detection has cleared it,
///   and configd applies a stored bridge change to the kernel a beat after
///   the preferences are written;
/// - and never less often than every ``backstop``, for the one change nothing
///   here can see — kernel bridge membership edited by hand with `ifconfig`,
///   which touches neither the preferences nor, necessarily, a flag.
public struct PortReadGate: Sendable {
    public static let settle: Duration = .seconds(5)
    public static let backstop: Duration = .seconds(10)

    private var signature: PortStateSignature?
    private var lastRead: ContinuousClock.Instant?
    private var settleUntil: ContinuousClock.Instant?

    public init() {}

    /// Whether this wake-up owes the full read. A `true` is recorded as the
    /// read having been made; one that then refuses is reported with
    /// ``readFailed()``.
    ///
    /// - Parameters:
    ///   - signature: this wake-up's signature, `nil` when it could not be
    ///     read.
    ///   - storeEvent: the store sent a notification since the last wake-up.
    public mutating func shouldRead(
        signature: PortStateSignature?,
        storeEvent: Bool,
        at now: ContinuousClock.Instant
    ) -> Bool {
        let moved = storeEvent || signature == nil || signature != self.signature
        self.signature = signature
        if moved { settleUntil = now + Self.settle }
        let owed = moved
            || settleUntil.map { now < $0 } == true
            || lastRead.map { now - $0 >= Self.backstop } != false
        if owed { lastRead = now }
        return owed
    }

    /// The read ``shouldRead(signature:storeEvent:at:)`` owed refused. It is
    /// not a read: the next wake-up owes another, as every tick did before
    /// the diff was gated — the window keeps the last hub it observed and
    /// looks again (`InventoryModel`).
    public mutating func readFailed() {
        lastRead = nil
    }
}
