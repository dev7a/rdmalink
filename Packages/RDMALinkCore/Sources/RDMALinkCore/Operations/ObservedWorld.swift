import Foundation
import SystemConfiguration

/// Everything an operation's ``preview()`` needs, read once and then never
/// read again inside that preview.
///
/// Preview is pure so the review screen and the last gate can be shown the
/// same evidence and be guaranteed to agree; this is that evidence. It is read
/// again **inside** the burst, immediately before the first write, and the two
/// are compared — a cable that moved while the review was on screen is R17.
public struct ObservedWorld: Sendable {
    /// The kernel, from `ifconfig -a`. The only place bridge membership is real.
    public var snapshot: InterfaceSnapshot
    /// Every network service in the current location.
    public var services: [NetworkServiceInfo]
    /// Service identifiers in the order macOS keeps them, for the undo note.
    public var serviceOrder: [String]
    /// The bridges as the stored configuration has them, for their display
    /// names and their own service identifiers.
    public var bridges: [BridgeSPI.Membership]
    /// R1 and R5, which no single port can see.
    public var context: PreflightContext
    /// The RDMA switch, for S5's warning row. Not RDMALink's to change.
    public var rdma: RDMAStatus
    /// Volumes mounted over the ports in question — R4.
    public var mountedVolumes: [MountedVolume]
    /// R14, evaluated against the notes folder. `nil` means a note can be saved.
    public var notesAreWritable: Refusal?

    public init(
        snapshot: InterfaceSnapshot,
        services: [NetworkServiceInfo],
        serviceOrder: [String] = [],
        bridges: [BridgeSPI.Membership] = [],
        context: PreflightContext,
        rdma: RDMAStatus = .unknown,
        mountedVolumes: [MountedVolume] = [],
        notesAreWritable: Refusal? = nil
    ) {
        self.snapshot = snapshot
        self.services = services
        self.serviceOrder = serviceOrder
        self.bridges = bridges
        self.context = context
        self.rdma = rdma
        self.mountedVolumes = mountedVolumes
        self.notesAreWritable = notesAreWritable
    }

    /// Reads this Mac. **Read-only**: IOKit, `ifconfig -a`, `mount`, an
    /// unauthorized `SCPreferences` (which can only read) and `SCDynamicStore`.
    /// No credential, no lock, no write.
    public static func read(
        ports: [OperationPort],
        archetype: Archetype,
        notesDirectory: URL = BaselineStore.defaultDirectory,
        clientName: String = "RDMALink",
        runner: CommandRunner = CommandRunner()
    ) throws -> ObservedWorld {
        guard let preferences = SCPreferencesCreate(nil, clientName as CFString, nil) else {
            throw NetworkConfigurationError.preferencesUnavailable(SCError())
        }
        return ObservedWorld(
            snapshot: try InterfaceSnapshot.read(using: runner),
            services: NetworkServices.read(from: preferences),
            serviceOrder: NetworkServices.serviceOrder(in: preferences),
            bridges: (try? BridgeSPI.bridges(in: preferences)) ?? [],
            context: try PreflightContext.read(archetype: archetype, runner: runner),
            rdma: RDMAStatus.read(runner: runner),
            mountedVolumes: (try? MountedVolumes.over(ports, runner: runner)) ?? [],
            notesAreWritable: Refusals.baselineWritable(notesDirectory))
    }

    /// The same read, taken through the writer so it happens inside the burst
    /// and on the same preferences handle the writes will use.
    static func reread(
        ports: [OperationPort],
        writer: NetworkWriter,
        archetype: Archetype,
        notesDirectory: URL,
        runner: CommandRunner
    ) throws -> ObservedWorld {
        ObservedWorld(
            snapshot: try writer.readKernel(),
            services: try writer.services(),
            serviceOrder: try writer.serviceOrder(),
            bridges: (try? writer.bridges()) ?? [],
            context: try PreflightContext.read(archetype: archetype, runner: runner),
            rdma: RDMAStatus.read(runner: runner),
            mountedVolumes: (try? MountedVolumes.over(ports, runner: runner)) ?? [],
            notesAreWritable: Refusals.baselineWritable(notesDirectory))
    }

    /// What System Settings calls each bridge, for the copy that names one.
    public var bridgeDisplayNames: [String: String] {
        bridges.reduce(into: [:]) { names, bridge in
            names[bridge.bsdName] = bridge.displayName
        }
    }

    /// The name to put in front of a user: what System Settings calls the
    /// bridge, or its kernel name when macOS offers nothing. Never a guess.
    public func name(ofBridge bsdName: String) -> String {
        bridgeDisplayNames[bsdName] ?? bsdName
    }

    /// The undo note's record of one kernel bridge, member list included.
    func membership(ofBridge bsdName: String) -> BridgeMembership {
        let stored = bridges.first { $0.bsdName == bsdName }
        let live = snapshot[bsdName]
        return BridgeMembership(
            bridgeName: bsdName,
            // A bridge has a service of its own, and that identifier is how it
            // is found again: `bridgeN` names are kernel-allocated and are not
            // stable across a delete and recreate.
            serviceIdentifier: services.first { $0.interfaceBSDName == bsdName }?.serviceID,
            displayName: stored?.displayName,
            members: live?.members ?? stored?.members ?? [],
            isActive: live?.isActive ?? false)
    }

    /// Every kernel bridge a port is a member of, down ones included.
    public func bridges(containing bsdName: String) -> [String] {
        snapshot.bridges(containing: bsdName)
    }
}

/// The undo note, built out of the world as it is at this moment.
enum BaselineCapture {
    /// Everything UX_SPEC §7.1 says a note records, except the created service
    /// — which does not exist yet, because the note is written first.
    static func note(port: OperationPort, world: ObservedWorld, isAdopted: Bool = false) -> PortBaseline {
        let existing = NetworkServices.services(for: port.bsdName, in: world.services).first
        let service = existing.map {
            ServiceRecord(identifier: $0.serviceID, name: $0.name,
                          orderIndex: world.serviceOrder.firstIndex(of: $0.serviceID))
        }
        if isAdopted {
            // An adopted note has no bridge history: RDMALink never saw which
            // bridge the port came from and will not invent one (§7.3).
            return PortBaseline.adopted(
                bsdName: port.bsdName, receptacle: port.receptacle,
                positionName: port.positionName, existingService: service,
                ipv4: existing?.ipv4, ipv6: existing?.ipv6)
        }
        return PortBaseline(
            bsdName: port.bsdName,
            receptacle: port.receptacle,
            positionName: port.positionName,
            bridges: world.bridges(containing: port.bsdName).map(world.membership(ofBridge:)),
            existingService: service,
            ipv4: existing?.ipv4,
            ipv6: existing?.ipv6)
    }
}

extension BaselineRecorder {
    /// The recorder the operations write their notes through.
    ///
    /// `notes` is captured inside the burst, from the re-read world, so the
    /// note describes the Mac as it is at the moment of the first write and
    /// not as it was when the review screen was drawn.
    static func live(store: BaselineStore, notes: [String: PortBaseline]) -> BaselineRecorder {
        BaselineRecorder(
            checkWritable: {
                switch store.checkWritable() {
                case .writable:
                    return nil
                case let .outOfSpace(available, volume):
                    let amount = available.formatted(.byteCount(style: .file, spellsOutZero: false))
                    return Refusals.baselineUnwritable(
                        detail: "2 KB is all it needs. There's \(amount) free on "
                            + "\(volume ?? store.directory.path).")
                case let .notWritable(reason):
                    return Refusals.baselineUnwritable(detail: "The folder isn't writable. \(reason)")
                }
            },
            record: { bsdName in
                guard let note = notes[bsdName] else {
                    throw BaselineStoreError.missing(bsdName)
                }
                try store.save(note)
                return BaselineToken(portBSDName: bsdName, recordedAt: note.recordedAt)
            },
            recordCreatedService: { service, token in
                var note = try store.load(port: token.portBSDName)
                note.createdService = service
                try store.save(note)
            })
    }
}
