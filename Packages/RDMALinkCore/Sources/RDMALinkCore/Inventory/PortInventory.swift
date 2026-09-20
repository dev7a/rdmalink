import Foundation
import IOKit

/// Reads this Mac's Thunderbolt receptacles.
///
/// The load-bearing part uses public IOKit keys only: `AppleThunderboltIPPort`
/// for the receptacle, its `IOLocation` and `IOLinkStatus`, and the
/// `IOEthernetInterface` child's `BSD Name`. Physical position and plug
/// presence are enrichment from ``ChassisProbe`` and are allowed to be absent.
public enum PortInventory {
    /// The public-key facts about one receptacle, before enrichment.
    struct PortRow: Sendable, Equatable {
        var receptacle: Int
        var bsdName: String
        var linkStatus: Int
    }

    private static let portClass = "AppleThunderboltIPPort"
    private static let receptacleKey = "IOLocation"
    private static let linkStatusKey = "IOLinkStatus"
    private static let ethernetInterfaceClass = "IOEthernetInterface"
    private static let bsdNameKey = "BSD Name"

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
            rows.append(PortRow(
                receptacle: receptacle,
                bsdName: bsdName,
                linkStatus: IORegistry.integer(entry, linkStatusKey) ?? 0
            ))
        }
        return rows
    }

    /// Joins the public-key rows with the best-effort enrichment.
    ///
    /// Pure, so the whole join — naming, masking, the dock-versus-empty
    /// decision — is testable against recorded hardware without hardware.
    static func assemble(
        rows: [PortRow],
        archetype: Archetype,
        enrichment: [Int: ReceptacleEnrichment]
    ) -> [ThunderboltPort] {
        rows.sorted { $0.receptacle < $1.receptacle }.map { row in
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
                )
            )
        }
    }
}
