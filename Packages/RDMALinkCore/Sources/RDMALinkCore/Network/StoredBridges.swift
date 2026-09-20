import Foundation
import SystemConfiguration

/// Bridge membership as the **stored** network configuration has it, plus which
/// of the two ways of reading it actually answered.
///
/// The kernel is not the whole truth about bridge membership. macOS keeps a
/// bridge's member list in the network preferences as well, and the two can
/// disagree: a `bridge0` whose stored `Interfaces` array still lists `en5`
/// while `ifconfig bridge0` lists no members at all is an ordinary state of
/// this Mac, and in it `SCNetworkServiceCreate` refuses with
/// `kSCStatusFailed` — configd will not put a service on an interface that a
/// stored bridge still claims. So stored membership is read as a fact in its
/// own right, never inferred from the kernel.
public struct StoredBridgeReading: Sendable, Equatable {
    /// Which read answered. Recorded rather than assumed, because the first
    /// one rests on a private SPI that a future macOS may drop.
    public enum Source: String, Sendable, Equatable, CaseIterable, CustomStringConvertible {
        /// `SCBridgeInterfaceCopyAll` on an unprivileged `SCPreferences` handle.
        case bridgeSPI
        /// `/Library/Preferences/SystemConfiguration/preferences.plist`, which
        /// is world-readable, parsed directly.
        case preferencesFile
        /// Neither answered. Not the same as "there are no bridges".
        case unavailable

        public var description: String {
            switch self {
            case .bridgeSPI: "the bridge SPI"
            case .preferencesFile: "the preferences file"
            case .unavailable: "nothing — neither the bridge SPI nor the preferences file answered"
            }
        }
    }

    /// Every bridge the stored configuration has, members included.
    public var bridges: [BridgeSPI.Membership]
    public var source: Source

    public init(bridges: [BridgeSPI.Membership], source: Source) {
        self.bridges = bridges
        self.source = source
    }

    /// The BSD names of every stored bridge listing `bsdName` as a member.
    public func names(containing bsdName: String) -> [String] {
        StoredBridges.names(in: bridges, containing: bsdName)
    }
}

/// Reads bridge membership out of the stored network configuration, without
/// any privilege at all.
///
/// `SCPreferencesCreate` with no `AuthorizationRef` opens a handle that can
/// only read, and the preferences file it reads is world-readable — so this is
/// as harmless as `ifconfig` and is used wherever membership is a question,
/// including inside `Inventory`.
public enum StoredBridges {
    /// Where macOS keeps the network configuration.
    public static let preferencesFileURL = URL(
        fileURLWithPath: "/Library/Preferences/SystemConfiguration/preferences.plist")

    /// The stored bridges, from the SPI when it is there and from the
    /// preferences file when it is not.
    ///
    /// The SPI is tried first because it is the same object the writes edit;
    /// the file is the fallback that keeps membership a known fact on a macOS
    /// that has dropped `SCBridgeInterfaceCopyAll` (`docs/ARCHITECTURE.md`,
    /// rule 5).
    public static func read(
        clientName: String = "RDMALink",
        fileURL: URL = preferencesFileURL
    ) -> StoredBridgeReading {
        if let preferences = SCPreferencesCreate(nil, clientName as CFString, nil),
           let bridges = try? BridgeSPI.bridges(in: preferences) {
            return StoredBridgeReading(bridges: bridges, source: .bridgeSPI)
        }
        if let data = try? Data(contentsOf: fileURL),
           let bridges = try? parsePreferences(data) {
            return StoredBridgeReading(bridges: bridges, source: .preferencesFile)
        }
        return StoredBridgeReading(bridges: [], source: .unavailable)
    }

    /// The BSD names of every bridge in `bridges` that lists `bsdName`.
    public static func names(
        in bridges: [BridgeSPI.Membership],
        containing bsdName: String
    ) -> [String] {
        guard !bsdName.isEmpty else { return [] }
        return bridges.filter { $0.members.contains(bsdName) }.map(\.bsdName)
    }

    /// Parses `VirtualNetworkInterfaces` → `Bridge` out of a preferences plist.
    ///
    /// The shape this Mac has:
    ///
    /// ```
    /// VirtualNetworkInterfaces → Bridge → bridge0 → {
    ///     Interfaces      = [ en5 ]
    ///     UserDefinedName = Thunderbolt Bridge
    /// }
    /// ```
    ///
    /// A bridge with no `Interfaces` array is a bridge with no members, which
    /// is a real state and not a read failure. Bridges come back sorted by
    /// name so two reads of the same file are the same value.
    static func parsePreferences(_ data: Data) throws -> [BridgeSPI.Membership] {
        let root = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let top = root as? [String: Any],
              let virtual = top["VirtualNetworkInterfaces"] as? [String: Any],
              let bridges = virtual["Bridge"] as? [String: Any]
        else { return [] }
        return bridges.keys.sorted().compactMap { name in
            guard let entry = bridges[name] as? [String: Any] else { return nil }
            return BridgeSPI.Membership(
                bsdName: name,
                displayName: entry["UserDefinedName"] as? String,
                members: entry["Interfaces"] as? [String] ?? [])
        }
    }
}
