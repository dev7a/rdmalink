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
    /// The bridges as the stored configuration has them: their display names,
    /// their own service identifiers, and — the fact the kernel cannot be
    /// asked for — their **stored** member lists.
    ///
    /// Membership here is not a weaker copy of `ifconfig`'s. A bridge whose
    /// stored `Interfaces` array still lists a port while the kernel bridge
    /// has no members at all is an ordinary state of a Mac, and in it
    /// `SCNetworkServiceCreate` refuses with `kSCStatusFailed`: configd will
    /// not put a service on an interface a stored bridge still claims.
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
        // Stored membership decides whether a service can be created at all,
        // so it is never allowed to degrade silently to "no bridges": when the
        // SPI will not answer, the world-readable preferences file does.
        let stored = StoredBridges.read(clientName: clientName)
        return ObservedWorld(
            snapshot: try InterfaceSnapshot.read(using: runner),
            services: NetworkServices.read(from: preferences),
            serviceOrder: NetworkServices.serviceOrder(in: preferences),
            bridges: stored.bridges,
            context: try PreflightContext.read(archetype: archetype, runner: runner,
                                               storedBridges: stored),
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
        // The session's own handle first — it is the object the writes will
        // edit — and the world-readable preferences file when the SPI refuses,
        // because a burst that read "no bridges" from a failure would plan no
        // removal and then fail at `SCNetworkServiceCreate`.
        let stored = (try? writer.bridges()).map {
            StoredBridgeReading(bridges: $0, source: .bridgeSPI)
        } ?? StoredBridges.read()
        return ObservedWorld(
            snapshot: try writer.readKernel(),
            services: try writer.services(),
            serviceOrder: try writer.serviceOrder(),
            bridges: stored.bridges,
            context: try PreflightContext.read(archetype: archetype, runner: runner,
                                               storedBridges: stored),
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

    /// The undo note's record of one bridge, member list included.
    ///
    /// The member list is the **union** of the stored and kernel lists, stored
    /// order first. It is the list the SPI's remove and add are checked
    /// against (``BridgeSPI/resolveRecorded(_:in:)``), and a kernel bridge
    /// that has forgotten its members while the preferences still hold them
    /// would otherwise make every stored member look like a stranger's.
    func membership(ofBridge bsdName: String) -> BridgeMembership {
        let stored = bridges.first { $0.bsdName == bsdName }
        let live = snapshot[bsdName]
        let storedMembers = stored?.members ?? []
        let liveMembers = live?.members ?? []
        return BridgeMembership(
            bridgeName: bsdName,
            // A bridge has a service of its own, and that identifier is how it
            // is found again: `bridgeN` names are kernel-allocated and are not
            // stable across a delete and recreate.
            serviceIdentifier: services.first { $0.interfaceBSDName == bsdName }?.serviceID,
            displayName: stored?.displayName,
            members: storedMembers + liveMembers.filter { !storedMembers.contains($0) },
            isActive: live?.isActive ?? false)
    }

    /// Every bridge a port is a member of — kernel first, then the ones only
    /// the stored configuration knows about. Down bridges included.
    ///
    /// This is the list an operation plans its removals from. A port the
    /// preferences still list is a port configd will not create a service on,
    /// however empty `ifconfig` says the bridge is.
    public func bridges(containing bsdName: String) -> [String] {
        let kernel = snapshot.bridges(containing: bsdName)
        let stored = StoredBridges.names(in: bridges, containing: bsdName)
        return kernel + stored.filter { !kernel.contains($0) }
    }

    /// Only what `ifconfig` says, for the places that have to tell the two
    /// reads apart.
    public func kernelBridges(containing bsdName: String) -> [String] {
        snapshot.bridges(containing: bsdName)
    }

    /// Only what the stored configuration says.
    public func storedBridges(containing bsdName: String) -> [String] {
        StoredBridges.names(in: bridges, containing: bsdName)
    }
}

/// The undo note, built out of the world as it is at this moment.
enum BaselineCapture {
    /// Everything UX_SPEC §7.1 says a note records, except the created service
    /// — which does not exist yet, because the note is written first.
    ///
    /// - Parameter returnedTo: the bridge Return to Bridge is about to put the
    ///   port into (§7.5). The note it writes first is a return record.
    static func note(
        port: OperationPort,
        world: ObservedWorld,
        isAdopted: Bool = false,
        returnedTo: BridgeReturn? = nil
    ) -> PortBaseline {
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
            ipv6: existing?.ipv6,
            returnedToBridge: returnedTo)
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
