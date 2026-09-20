import IOKit.network

/// Which face of the chassis a receptacle is on.
public enum PortFace: String, Sendable, CaseIterable {
    case back, front, left, right
}

/// What is physically plugged into a receptacle right now — the inner track of
/// UX_SPEC §4.2. It says nothing about the port's configuration; that is the
/// outer track and a different module's job.
public enum LinkState: Sendable, Equatable {
    /// Nothing plugged in.
    case empty
    /// A device that is not a Mac: a dock, a display, a drive.
    case device
    /// A Mac is here and the link is still coming up.
    case macLinkComingUp
    /// A Mac is linked.
    case macLinked
}

/// One receptacle on this Mac.
public struct ThunderboltPort: Sendable, Identifiable, Equatable {
    /// Stable across launches and replugs. This is the BSD name: an IORegistry
    /// entry id changes when the port re-enumerates, and every other module —
    /// bridges, services, baselines — already keys on `enN`. A USB-only
    /// receptacle has no BSD name and carries the catalogue's own identifier
    /// for it instead.
    public var id: String
    /// `IOLocation`, 1-based, as the Thunderbolt-IP driver reports it. On a
    /// USB-only receptacle, which has no Thunderbolt-IP port to report one,
    /// it is the catalogue's own 0-based index for that receptacle on its face.
    public var receptacle: Int
    /// `en6`. Never derived from ``receptacle``.
    public var bsdName: String
    /// From `port-location` when this Mac publishes it, nil otherwise.
    public var face: PortFace?
    /// `Back, far left`, or `Thunderbolt port 3` when the position is unknown.
    public var positionName: String
    /// False for USB-only receptacles.
    public var isThunderbolt: Bool
    /// The inner track.
    public var link: LinkState
    /// Every kernel bridge this port is a member of, in use or not.
    public var bridges: [BridgeMembership]
    /// `fe80::` addresses on this interface, without the `%scope` suffix.
    public var linkLocal: [String]
    /// This receptacle's own Thunderbolt domain — the private
    /// `IOThunderboltLocalNode` key `Domain UUID`, one per controller and so
    /// one per receptacle on Apple Silicon. `nil` when this Mac did not say.
    public var domainUUID: String?
    /// The domain on the far end of each cross-domain link on this
    /// receptacle's controller — the same key on `IOThunderboltXDomainLink`.
    /// Another Mac's local node reports exactly this value as its own, which
    /// is what lets a cable that comes back into this Mac be recognized.
    /// Empty for a dock, an empty receptacle, or a Mac that does not publish
    /// the key.
    public var peerDomainUUIDs: [String]
    /// The BSD name of the receptacle on this Mac the same cable is plugged
    /// into, when there is one — R2's finding. Set only on a mutual, unique
    /// domain match, so it is never a guess.
    public var loopedBackTo: String?

    /// One bridge a port belongs to, as the kernel or the stored network
    /// configuration has it.
    ///
    /// The BSD name alone is not enough to say what UX_SPEC §S1 says — "In two
    /// bridges, including one that isn't in use" — so the two facts that
    /// sentence rests on travel with it.
    ///
    /// This is not ``RDMALinkCore/BridgeMembership``, which is the undo note's
    /// record of a bridge's whole member list at the moment it was changed.
    /// This one is what the port list knows about a bridge right now.
    public struct BridgeMembership: Sendable, Equatable, Identifiable {
        /// Which read said this port is in this bridge.
        ///
        /// The kernel and the stored configuration can disagree: a `bridge0`
        /// whose stored `Interfaces` array still lists a port while `ifconfig
        /// bridge0` lists no members at all is an ordinary state of a Mac. A
        /// port is in a bridge when **either** says so, because configd
        /// refuses to create a service on an interface a stored bridge still
        /// claims — so a port that is only stored-a-member is every bit as
        /// unusable as one the kernel is really bridging.
        public enum Source: String, Sendable, Equatable, CaseIterable, CustomStringConvertible {
            /// `ifconfig` lists the port here; the stored configuration does not.
            case kernel
            /// The stored configuration lists it; the kernel does not.
            case stored
            /// Both say so, which is the ordinary case.
            case both

            public var description: String {
                switch self {
                case .kernel: "kernel only"
                case .stored: "saved settings only"
                case .both: "kernel and saved settings"
                }
            }

            /// True when `ifconfig` is one of the reads that said so.
            public var includesKernel: Bool { self != .stored }
            /// True when the stored configuration is one of them.
            public var includesStored: Bool { self != .kernel }

            /// The source for a membership seen by one read, the other, or both.
            public static func of(kernel: Bool, stored: Bool) -> Source {
                switch (kernel, stored) {
                case (true, true): .both
                case (false, true): .stored
                default: .kernel
                }
            }
        }

        /// The kernel interface name, `bridge0`.
        public var name: String
        /// What System Settings calls it, `Thunderbolt Bridge`, when the
        /// bridge SPI answered. `nil` when it did not: nothing is guessed, and
        /// the copy falls back to ``name`` (`docs/ARCHITECTURE.md`, rule 5).
        public var displayName: String?
        /// Whether the kernel says this bridge is up **and** carrying
        /// something.
        ///
        /// The `UP` flag on its own is not evidence: practically every
        /// interface on macOS carries it whatever its carrier state, and an
        /// empty `bridge0` that nothing has ever used reads `UP` too. The fact
        /// underneath is `ifconfig`'s `status: active`, and both are required
        /// here, so a bridge this says is up is one the kernel is really
        /// running traffic through.
        public var isUp: Bool
        /// Which of the two reads said so.
        ///
        /// ``isUp`` stays the kernel's answer about the bridge interface
        /// itself and is not inferred from this: a bridge the kernel is
        /// running for other members, while the preferences list this port
        /// and `ifconfig` does not, is `stored` **and** up. Either way the
        /// membership blocks a service on this port.
        public var source: Source

        /// The kernel name: unique among one port's bridges, because an
        /// interface is listed once.
        public var id: String { name }

        public init(
            name: String,
            displayName: String? = nil,
            isUp: Bool,
            source: Source = .kernel
        ) {
            self.name = name
            self.displayName = displayName
            self.isUp = isUp
            self.source = source
        }
    }

    public init(
        id: String,
        receptacle: Int,
        bsdName: String,
        face: PortFace? = nil,
        positionName: String,
        isThunderbolt: Bool = true,
        link: LinkState,
        bridges: [BridgeMembership] = [],
        linkLocal: [String] = [],
        domainUUID: String? = nil,
        peerDomainUUIDs: [String] = [],
        loopedBackTo: String? = nil
    ) {
        self.id = id
        self.receptacle = receptacle
        self.bsdName = bsdName
        self.face = face
        self.positionName = positionName
        self.isThunderbolt = isThunderbolt
        self.link = link
        self.bridges = bridges
        self.linkLocal = linkLocal
        self.domainUUID = domainUUID
        self.peerDomainUUIDs = peerDomainUUIDs
        self.loopedBackTo = loopedBackTo
    }

    /// The merge point for what only `ifconfig` can say.
    ///
    /// The Inventory module reads hardware; kernel bridge membership and live
    /// addresses come from the Network module's `ifconfig -a` parse. This is
    /// where the two meet, so neither module has to know the other's shape.
    public mutating func apply(bridges: [BridgeMembership], linkLocal: [String]) {
        self.bridges = bridges
        self.linkLocal = linkLocal
    }

    /// The fallback name from UX_SPEC §4.7 when no physical position is known.
    public static func numberedName(receptacle: Int) -> String {
        "Thunderbolt port \(receptacle)"
    }
}

extension LinkState {
    /// Derives the inner-track state from `IOLinkStatus` and the best-effort
    /// "something is plugged in" signal.
    ///
    /// `IOLinkStatus` masked with `kIONetworkLinkValid | kIONetworkLinkActive`
    /// reads 3 when a Mac is linked and 1 for an empty receptacle *and* for a
    /// dock — the public key cannot tell those two apart, so ``device`` is only
    /// produced when `deviceAttached` says so. A nil `deviceAttached` means the
    /// enrichment was unavailable, and the honest answer is ``empty``.
    ///
    /// ``macLinkComingUp`` is never produced here: no public or verified
    /// undocumented key distinguishes a Mac whose link is still negotiating
    /// from any other attached device.
    static func from(linkStatus: Int, deviceAttached: Bool?) -> LinkState {
        let mask = kIONetworkLinkValid | kIONetworkLinkActive
        if linkStatus & mask == mask { return .macLinked }
        return deviceAttached == true ? .device : .empty
    }
}
