import Foundation
import SystemConfiguration

/// Everything one read can say about this Mac: what it is, what is plugged into
/// it, and whether RDMA over Thunderbolt is switched on.
///
/// This is the aggregate from ARCHITECTURE.md's Core contracts and the single
/// entry point both the app and the command-line tool use. It is the one place
/// the two halves of a port meet: ``PortInventory`` reads hardware through
/// IOKit, ``InterfaceSnapshot`` reads kernel bridge membership and live
/// addresses out of `ifconfig`, and the merge happens here so neither module
/// has to know the other's shape.
///
/// Nothing here writes. There is no authorization, no `SCPreferences` lock and
/// no subprocess beyond the read-only tools ``InterfaceSnapshot`` and
/// ``RDMAStatus`` already run.
public struct Inventory: Sendable, Equatable {
    /// What this Mac is.
    public var model: HardwareModel
    /// Every Thunderbolt receptacle, in physical order — see ``read(runner:)``.
    public var ports: [ThunderboltPort]
    /// The RDMA switch and the devices it produced.
    public var rdma: RDMAStatus

    /// Public so the app can build fixtures for screen states it has no
    /// hardware for. A public struct's memberwise initializer is internal.
    public init(model: HardwareModel, ports: [ThunderboltPort], rdma: RDMAStatus) {
        self.model = model
        self.ports = ports
        self.rdma = rdma
    }

    /// Reads this Mac.
    ///
    /// Ports come back in **physical order** — left to right along the back,
    /// then left to right along the front, which is the order UX_SPEC §4.7
    /// lists them in and the order the port list and the stage draw them in.
    /// That is not receptacle order: on Mac15,14 receptacle 1 is the *rightmost*
    /// back port. Receptacle order is kept as a tie-break, so a Mac that
    /// publishes no positions at all comes back in the order macOS reports.
    ///
    /// On a recognized Mac the list also carries the **USB-only receptacles**
    /// from ``ReceptacleCatalogue``, interleaved in the same physical order.
    /// They have no BSD name and no Thunderbolt-IP port behind them; they are
    /// in the list because UX_SPEC §4.5 and §S1 put them there, dimmed and
    /// unselectable, so that a cable in the wrong hole has somewhere to be
    /// seen.
    ///
    /// - Throws: ``InventoryError`` when the registry itself refused (R24 with
    ///   a reason for `Copy Details`), or ``InterfaceReadFailure`` when
    ///   `ifconfig` did. Bridge membership is not optional enrichment: a port
    ///   listed with no bridges when the read failed would be a claim the app
    ///   has not observed, which the tone rules forbid.
    ///
    /// An empty ``ports`` array is not an error. It is R24's other half: this
    /// Mac reports no Thunderbolt-IP ports.
    public static func read(runner: CommandRunner = CommandRunner()) throws -> Inventory {
        let model = HardwareModel.read()
        return Inventory(
            model: model,
            ports: try readPorts(archetype: model.archetype, runner: runner),
            rdma: RDMAStatus.read(runner: runner)
        )
    }

    /// The port half on its own, for the cheap re-read a link event wants: the
    /// RDMA switch cannot change without a restart, and the hardware model
    /// cannot change at all.
    public static func readPorts(
        archetype: Archetype,
        runner: CommandRunner = CommandRunner()
    ) throws -> [ThunderboltPort] {
        let rows = try PortInventory.readRows()
        let enrichment = ChassisProbe.read()
        var ports = PortInventory.assemble(
            rows: rows, archetype: archetype, enrichment: enrichment.byReceptacle
        )
        let interfaces = try InterfaceSnapshot.read(using: runner)
        // Resolved once, and only if some port is in a bridge at all: on a Mac
        // with no bridges this opens no preferences session.
        var displayNames: [String: String]?
        for index in ports.indices {
            let name = ports[index].bsdName
            let bridges = interfaces.bridges(containing: name)
            if !bridges.isEmpty, displayNames == nil { displayNames = bridgeDisplayNames() }
            ports[index].apply(
                bridges: bridges.map { bridge in
                    ThunderboltPort.BridgeMembership(
                        name: bridge,
                        displayName: displayNames?[bridge],
                        isUp: interfaces[bridge].map { $0.isUp && $0.isActive } ?? false
                    )
                },
                linkLocal: interfaces[name]?.linkLocalAddresses ?? []
            )
        }
        return ReceptacleCatalogue.portRows(
            realPorts: sortedPhysically(ports, enrichment: enrichment.byReceptacle),
            archetype: archetype,
            cabledPositions: enrichment.cabledPositions
        )
    }

    /// What System Settings calls each bridge, keyed by BSD name.
    ///
    /// Read-only: `SCPreferencesCreate` without an `AuthorizationRef` cannot
    /// write, and ``BridgeSPI/displayNames(in:)`` degrades to an empty map
    /// when the private symbols are not there, which leaves every
    /// ``ThunderboltPort/BridgeMembership/displayName`` nil rather than
    /// guessed.
    private static func bridgeDisplayNames() -> [String: String] {
        guard let preferences = SCPreferencesCreate(nil, "RDMALink" as CFString, nil) else {
            return [:]
        }
        return BridgeSPI.displayNames(in: preferences)
    }

    /// Sorts by where the receptacles actually are, falling back to receptacle
    /// order for anything this Mac would not place.
    ///
    /// Kept internal and keyed on the enrichment map rather than on
    /// ``ThunderboltPort`` itself: the contract type carries `face` and
    /// `positionName` but no lateral rank, and inventing one would be a
    /// contract change for something only this function needs.
    static func sortedPhysically(
        _ ports: [ThunderboltPort],
        enrichment: [Int: ReceptacleEnrichment]
    ) -> [ThunderboltPort] {
        ports.sorted { left, right in
            let a = sortKey(left, enrichment: enrichment)
            let b = sortKey(right, enrichment: enrichment)
            if a == b { return left.receptacle < right.receptacle }
            return a < b
        }
    }

    /// `(face rank, lateral rank)`. An unplaced port sorts after every placed
    /// one rather than in among them, so a partial probe never interleaves a
    /// numbered port with named ones.
    private static func sortKey(
        _ port: ThunderboltPort,
        enrichment: [Int: ReceptacleEnrichment]
    ) -> (face: Int, lateral: Int) {
        guard let position = enrichment[port.receptacle]?.position else {
            return (.max, .max)
        }
        return (position.face.physicalRank, position.slot.physicalRank)
    }
}

extension Inventory {
    /// The minimal view the refusal functions take. They stay pure and
    /// hardware-free; this is the one adapter between the two.
    public var observedPorts: [ObservedPort] {
        ports.map(\.observed)
    }

    /// BSD names of the Thunderbolt ports, which is what
    /// ``Refusals/managementPathExists(in:thunderboltPorts:)`` needs to know to
    /// exclude them from the routes it counts.
    public var thunderboltBSDNames: [String] {
        ports.filter(\.isThunderbolt).map(\.bsdName)
    }
}

extension ThunderboltPort {
    /// This port as the refusal functions see it.
    public var observed: ObservedPort {
        ObservedPort(
            bsdName: bsdName,
            positionName: positionName,
            hasLinkedMac: link == .macLinked
        )
    }
}

extension PortFace {
    /// Back before front, then the notebook's two sides. UX_SPEC §4.7 lists
    /// every archetype in this order.
    var physicalRank: Int {
        switch self {
        case .back: 0
        case .front: 1
        case .left: 2
        case .right: 3
        }
    }
}

extension PortSlot {
    /// Left to right across a back or front face; rear to front along a side.
    /// A face with one receptacle needs no qualifier and sorts first.
    var physicalRank: Int {
        switch self {
        case .unspecified: 0
        case .left: 0
        case .leftMiddle: 1
        case .middle: 2
        case .rightMiddle: 3
        case .right: 4
        case .rear: 0
        case .front: 1
        }
    }
}
