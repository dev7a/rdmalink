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
    /// bridges, services, baselines — already keys on `enN`.
    public var id: String
    /// `IOLocation`, 1-based, as the Thunderbolt-IP driver reports it.
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
    /// Every kernel bridge this port is a member of, active or not.
    public var bridges: [String]
    /// `fe80::` addresses on this interface, without the `%scope` suffix.
    public var linkLocal: [String]

    public init(
        id: String,
        receptacle: Int,
        bsdName: String,
        face: PortFace? = nil,
        positionName: String,
        isThunderbolt: Bool = true,
        link: LinkState,
        bridges: [String] = [],
        linkLocal: [String] = []
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
    }

    /// The merge point for what only `ifconfig` can say.
    ///
    /// The Inventory module reads hardware; kernel bridge membership and live
    /// addresses come from the Network module's `ifconfig -a` parse. This is
    /// where the two meet, so neither module has to know the other's shape.
    public mutating func apply(bridges: [String], linkLocal: [String]) {
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
