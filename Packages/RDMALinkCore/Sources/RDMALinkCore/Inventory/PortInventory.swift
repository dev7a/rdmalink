import Foundation
import IOKit

/// Reads this Mac's Thunderbolt receptacles.
///
/// The load-bearing part uses public IOKit keys only: `AppleThunderboltIPPort`
/// for the receptacle, its `IOLocation` and `IOLinkStatus`, and the
/// `IOEthernetInterface` child's `BSD Name`. Physical position and plug
/// presence are enrichment from ``ChassisProbe`` and are allowed to be absent,
/// and so is the Thunderbolt domain identity that says whose cable this is.
public enum PortInventory {
    /// The facts about one receptacle, before enrichment.
    struct PortRow: Sendable, Equatable {
        var receptacle: Int
        var bsdName: String
        var linkStatus: Int
        /// This receptacle's own Thunderbolt domain, from the private
        /// `IOThunderboltLocalNode` above the port. `nil` when the Mac did
        /// not say.
        var domainUUID: String? = nil
        /// The domain on the far end of every cross-domain link under this
        /// receptacle's controller, from the private `IOThunderboltXDomainLink`
        /// nodes. Empty for a dock, an empty receptacle, or a Mac that does
        /// not publish the key.
        var peerDomainUUIDs: [String] = []
    }

    private static let portClass = "AppleThunderboltIPPort"
    private static let receptacleKey = "IOLocation"
    private static let linkStatusKey = "IOLinkStatus"
    private static let ethernetInterfaceClass = "IOEthernetInterface"
    private static let bsdNameKey = "BSD Name"
    /// Private `IOThunderboltFamily` classes and their key (`docs/ARCHITECTURE.md`,
    /// rule 5: enrichment, never load-bearing, nil when absent).
    private static let localNodeClass = "IOThunderboltLocalNode"
    private static let crossDomainLinkClass = "IOThunderboltXDomainLink"
    private static let domainUUIDKey = "Domain UUID"
    /// How far above the port the local node may be. On macOS 27.2 it is two
    /// hops: port → `AppleThunderboltIPService` → `IOThunderboltLocalNode`.
    private static let localNodeSearchDepth = 4

    /// Every Thunderbolt receptacle on this Mac, in receptacle order.
    ///
    /// `archetype` is required rather than defaulted: it decides whether a port
    /// gets a physical name or a number, and a silent default would name ports
    /// on a Mac nobody has checked.
    ///
    /// An empty result means macOS is reporting no Thunderbolt-IP ports, which
    /// is R24. A throw means the registry itself refused, which is also R24 but
    /// carries a reason for `Copy Details`.
    public static func read(archetype: Archetype) throws -> [ThunderboltPort] {
        assemble(
            rows: try readRows(), archetype: archetype,
            enrichment: ChassisProbe.read().byReceptacle
        )
    }

    /// The public-key pass. A receptacle with no BSD name is skipped: every
    /// other module in the app keys on `enN`, and a port without one cannot be
    /// configured, restored or even named in a refusal.
    static func readRows() throws -> [PortRow] {
        var rows: [PortRow] = []
        try IORegistry.forEachService(matchingClass: portClass) { entry in
            guard let receptacle = IORegistry.integer(entry, receptacleKey) else { return }
            let bsdName = IORegistry.firstDescendant(of: entry, plane: kIOServicePlane) { child in
                IOObjectConformsTo(child, ethernetInterfaceClass) != 0
                    ? IORegistry.string(child, bsdNameKey)
                    : nil
            }
            guard let bsdName else { return }
            let identity = domainIdentity(above: entry, hops: localNodeSearchDepth)
            rows.append(PortRow(
                receptacle: receptacle,
                bsdName: bsdName,
                linkStatus: IORegistry.integer(entry, linkStatusKey) ?? 0,
                domainUUID: identity?.own,
                peerDomainUUIDs: identity?.peers ?? []
            ))
        }
        return rows
    }

    /// The domain this port belongs to and the domains linked to its
    /// controller, or `nil` when no `IOThunderboltLocalNode` sits above it.
    ///
    /// The shape on Mac15,14 (macOS 27.2, `IOThunderboltFamily` 9.3.3):
    ///
    /// ```
    /// IOThunderboltControllerType7
    ///   +-o IOThunderboltLocalNode              "Domain UUID" = own
    ///   | +-o AppleThunderboltIPService
    ///   |   +-o AppleThunderboltIPPort          ← entry
    ///   +-o IOThunderboltPort@7
    ///     +-o IOThunderboltSwitchType7          the local router
    ///       +-o IOThunderboltPort@1
    ///         +-o IOThunderboltXDomainLink      "Domain UUID" = peer
    /// ```
    ///
    /// The local node is found by class, not by counting hops, and the links
    /// are collected from the whole controller subtree: a Mac behind a dock
    /// puts its link one switch deeper, and a dock with two cables back into
    /// Macs puts two links under one controller.
    private static func domainIdentity(
        above entry: io_registry_entry_t, hops: Int
    ) -> (own: String?, peers: [String])? {
        guard hops > 0 else { return nil }
        return IORegistry.withParent(of: entry, plane: kIOServicePlane) { parent in
            guard IOObjectConformsTo(parent, localNodeClass) != 0 else {
                return domainIdentity(above: parent, hops: hops - 1)
            }
            let own = IORegistry.string(parent, domainUUIDKey).flatMap(domainUUID)
            let peers = IORegistry.withParent(of: parent, plane: kIOServicePlane) { controller in
                IORegistry.descendants(of: controller, plane: kIOServicePlane) { node in
                    IOObjectConformsTo(node, crossDomainLinkClass) != 0
                        ? IORegistry.string(node, domainUUIDKey).flatMap(domainUUID)
                        : nil
                }
            }
            return (own, peers ?? [])
        }
    }

    /// A `Domain UUID` as it is compared: the canonical upper-case form, or
    /// `nil` for anything that is not a UUID at all.
    ///
    /// R2 rests on an exact equality between what this Mac says about itself
    /// and what it says about the far end, so the two are put in one spelling
    /// first — a case difference between the two nodes would otherwise hide a
    /// loop, and a value that is not a UUID would otherwise be compared as if
    /// it were one.
    static func domainUUID(_ raw: String) -> String? {
        UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines))?.uuidString
    }

    /// Joins the public-key rows with the best-effort enrichment.
    ///
    /// Pure, so the whole join — naming, masking, the dock-versus-empty
    /// decision, the looped-cable pairing — is testable against recorded
    /// hardware without hardware.
    static func assemble(
        rows: [PortRow],
        archetype: Archetype,
        enrichment: [Int: ReceptacleEnrichment]
    ) -> [ThunderboltPort] {
        let partners = loopedBackPartners(rows)
        return rows.sorted { $0.receptacle < $1.receptacle }.map { row in
            let facts = enrichment[row.receptacle]
            let position = facts?.position
            return ThunderboltPort(
                id: row.bsdName,
                receptacle: row.receptacle,
                bsdName: row.bsdName,
                face: position?.face,
                positionName: position?.name(archetype: archetype)
                    ?? ThunderboltPort.numberedName(receptacle: row.receptacle),
                isThunderbolt: true,
                link: LinkState.from(
                    linkStatus: row.linkStatus,
                    deviceAttached: facts?.deviceAttached
                ),
                domainUUID: row.domainUUID,
                peerDomainUUIDs: row.peerDomainUUIDs,
                loopedBackTo: partners[row.bsdName]
            )
        }
    }

    /// Which receptacle each receptacle's cable comes back into, by BSD name —
    /// R2's input.
    ///
    /// A cable whose both ends are in this Mac shows up as port P linked to
    /// the domain that port Q calls its own, **and** Q linked to P's. The
    /// match has to be mutual and unique: a port with two candidate partners,
    /// or a domain two receptacles both claim as their own (one controller
    /// serving two receptacles — not seen on any Apple Silicon Mac, but rule
    /// 5 says not to assume), sets nothing for the ports involved. A miss is
    /// never a false positive; it only means R2 stays quiet.
    static func loopedBackPartners(_ rows: [PortRow]) -> [String: String] {
        var owners: [String: [String]] = [:]
        for row in rows {
            if let own = row.domainUUID { owners[own, default: []].append(row.bsdName) }
        }
        let byName = Dictionary(rows.map { ($0.bsdName, $0) }, uniquingKeysWith: { first, _ in first })
        var candidates: [String: Set<String>] = [:]
        for row in rows {
            guard let own = row.domainUUID, owners[own]?.count == 1 else { continue }
            for peer in Set(row.peerDomainUUIDs) {
                guard let holders = owners[peer], holders.count == 1,
                      let other = byName[holders[0]], other.bsdName != row.bsdName,
                      other.peerDomainUUIDs.contains(own) else { continue }
                candidates[row.bsdName, default: []].insert(other.bsdName)
            }
        }
        var partners: [String: String] = [:]
        for (name, others) in candidates where others.count == 1 {
            let other = others.first!
            if candidates[other] == [name] { partners[name] = other }
        }
        return partners
    }
}
