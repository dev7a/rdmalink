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
    /// Bridge membership as the stored network configuration has it, and which
    /// read answered. Merged into ``ports`` already; kept whole so a
    /// diagnostic can name the source rather than imply one.
    public var storedBridges: StoredBridgeReading

    /// Public so the app can build fixtures for screen states it has no
    /// hardware for. A public struct's memberwise initializer is internal.
    public init(
        model: HardwareModel,
        ports: [ThunderboltPort],
        rdma: RDMAStatus,
        storedBridges: StoredBridgeReading = StoredBridgeReading(bridges: [], source: .unavailable)
    ) {
        self.model = model
        self.ports = ports
        self.rdma = rdma
        self.storedBridges = storedBridges
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
        // One pass over the registry serves both halves: the model is decided
        // from the receptacles macOS reports and the positions the device tree
        // gives them (UX_SPEC §4.7, Recognition), and the ports are then named
        // for the archetype that decision produced.
        let rows = try PortInventory.readRows()
        let enrichment = ChassisProbe.read()
        let model = resolveModel(HardwareModel.read(), rows: rows, enrichment: enrichment)
        let stored = StoredBridges.read()
        return Inventory(
            model: model,
            ports: try readPorts(rows: rows, archetype: model.archetype, runner: runner,
                                 storedBridges: stored, enrichment: enrichment),
            rdma: RDMAStatus.read(runner: runner),
            storedBridges: stored
        )
    }

    /// What this Mac is, decided the way ``read(runner:)`` decides it, without
    /// the `ifconfig` and NVRAM reads underneath — for the window subtitle and
    /// the stage, which UX_SPEC §S0 wants "as soon as the model is known".
    /// Never fails: when the registry refuses the receptacle list, the layout
    /// is unknown and only the identifier catalogue decides, which is what
    /// ``read(runner:)``'s failure path leaves the caller with too.
    ///
    /// A Mac the catalogue lists is decided by three `sysctl` calls and
    /// nothing else: the registry is walked only when the identifier rule
    /// has already failed, so the subtitle on a known Mac is as quick as it
    /// was before the second rule existed.
    public static func readModel() -> HardwareModel {
        let model = HardwareModel.read()
        guard model.archetype == .unknown else { return model }
        return resolveModel(model, rows: try? PortInventory.readRows(), enrichment: ChassisProbe.read())
    }

    /// Both rules of UX_SPEC §4.7's recognition: the identifier catalogue
    /// first, then the product family with the Thunderbolt layout this Mac
    /// reports. A Mac the catalogue lists is never re-decided.
    ///
    /// - Parameter model: the identifier half, ``HardwareModel/read()``.
    /// - Parameter rows: every Thunderbolt receptacle macOS reports, or `nil`
    ///   when that read failed and the layout cannot be known.
    static func resolveModel(
        _ model: HardwareModel,
        rows: [PortInventory.PortRow]?,
        enrichment: ChassisEnrichment
    ) -> HardwareModel {
        guard let rows else { return model }
        return model.recognizing(
            thunderboltPositions: thunderboltPositions(rows: rows, enrichment: enrichment)
        )
    }

    /// One position per Thunderbolt receptacle macOS reports, `nil` for a
    /// receptacle the device-tree probe could not place.
    ///
    /// Keyed on the receptacle list rather than on the probe's own map: the
    /// probe holds an entry only for the receptacles whose `port-location`
    /// node it joined to a Thunderbolt-IP port, so a receptacle it missed is
    /// absent from the map, not nil in it. Read from the map alone, a Studio
    /// whose two front nodes failed to join would show exactly the back four
    /// and match the four-port Studio — the wrong picture §4.7 forbids ("no
    /// table position is missing"). Every receptacle counts, and one the
    /// probe did not place refuses.
    static func thunderboltPositions(
        rows: [PortInventory.PortRow],
        enrichment: ChassisEnrichment
    ) -> [PortPosition?] {
        rows.map { enrichment.byReceptacle[$0.receptacle]?.position }
    }

    /// The port half on its own, for the cheap re-read a link event wants: the
    /// RDMA switch cannot change without a restart, and the hardware model
    /// cannot change at all.
    ///
    /// - Parameter storedBridges: the stored bridges, when the caller has
    ///   already read them. `nil` reads them here.
    public static func readPorts(
        archetype: Archetype,
        runner: CommandRunner = CommandRunner(),
        storedBridges: StoredBridgeReading? = nil
    ) throws -> [ThunderboltPort] {
        try readPorts(
            rows: try PortInventory.readRows(), archetype: archetype, runner: runner,
            storedBridges: storedBridges, enrichment: ChassisProbe.read()
        )
    }

    /// ``readPorts(archetype:runner:storedBridges:)`` with the registry passes
    /// already made, so ``read(runner:)`` walks it once and the model and the
    /// ports are decided from the same receptacle list.
    static func readPorts(
        rows: [PortInventory.PortRow],
        archetype: Archetype,
        runner: CommandRunner,
        storedBridges: StoredBridgeReading?,
        enrichment: ChassisEnrichment
    ) throws -> [ThunderboltPort] {
        var ports = PortInventory.assemble(
            rows: rows, archetype: archetype, enrichment: enrichment.byReceptacle
        )
        let interfaces = try InterfaceSnapshot.read(using: runner)
        // Read once, always: the kernel is not the whole truth about bridge
        // membership, and a port the preferences still list is a port configd
        // will not put a service on however empty `ifconfig` says the bridge
        // is. Both reads are unprivileged and neither can write.
        //
        // This runs on the app's one-second state diff, so the cost was
        // measured on this Mac rather than guessed: `SCPreferencesCreate` plus
        // `SCBridgeInterfaceCopyAll` is 0.83 ms, and the `ifconfig -a` spawn
        // three lines up — which this function has always made — is 75 ms.
        // The read is 1% of what the enclosing call already spends, and
        // caching it would buy that back by letting the port rows keep saying
        // a port is in a bridge after System Settings took it out. So it is
        // read every time, and `storedBridges` exists only so one burst
        // measures everything against one snapshot.
        let stored = storedBridges ?? StoredBridges.read()
        for index in ports.indices {
            let name = ports[index].bsdName
            ports[index].apply(
                bridges: membership(of: name, kernel: interfaces, stored: stored.bridges),
                linkLocal: interfaces[name]?.linkLocalAddresses ?? []
            )
        }
        return ReceptacleCatalogue.portRows(
            realPorts: sortedPhysically(ports, enrichment: enrichment.byReceptacle),
            archetype: archetype,
            cabledPositions: enrichment.cabledPositions
        )
    }

    /// Every bridge one port belongs to, merged from the two reads.
    ///
    /// Kernel memberships come first, in the order `ifconfig` printed them,
    /// then the ones only the stored configuration knows about. A bridge both
    /// reads agree on appears once, with
    /// ``ThunderboltPort/BridgeMembership/Source/both``.
    ///
    /// `isUp` stays the kernel's answer and nothing else: a bridge the
    /// preferences describe but the kernel is not running is not "in use", and
    /// saying otherwise would be a claim about traffic that is not flowing.
    /// The display name comes from the stored configuration, which is the only
    /// place macOS keeps one — an absent entry leaves it nil rather than
    /// guessed (`docs/ARCHITECTURE.md`, rule 5).
    static func membership(
        of bsdName: String,
        kernel: InterfaceSnapshot,
        stored: [BridgeSPI.Membership]
    ) -> [ThunderboltPort.BridgeMembership] {
        guard !bsdName.isEmpty else { return [] }
        let kernelNames = kernel.bridges(containing: bsdName)
        let storedNames = StoredBridges.names(in: stored, containing: bsdName)
        let ordered = kernelNames + storedNames.filter { !kernelNames.contains($0) }
        return ordered.map { name in
            let live = kernel[name]
            return ThunderboltPort.BridgeMembership(
                name: name,
                displayName: stored.first { $0.bsdName == name }?.displayName,
                isUp: live.map { $0.isUp && $0.isActive } ?? false,
                source: .of(kernel: kernelNames.contains(name),
                            stored: storedNames.contains(name)))
        }
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
            hasLinkedMac: link == .macLinked,
            bridges: bridges.map(\.name),
            loopedBackTo: loopedBackTo
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
