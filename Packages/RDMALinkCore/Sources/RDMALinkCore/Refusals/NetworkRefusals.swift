import Foundation

/// The hard rules the configure path rests on, as pure functions over observed
/// state. Each returns `nil` when the rule is satisfied and a ``Refusal``
/// carrying the spec's own strings when it is not. There is no override.
public enum Refusals {
    /// How much room the undo note needs. The copy in ``baselineWritable(_:)``
    /// says so out loud: "2 KB is all it needs."
    public static let baselineByteEstimate: Int64 = 2048

    /// Interfaces that can never be a way to reach this Mac from elsewhere:
    /// loopback, tunnels, Apple-internal and peer-to-peer links.
    private static let ignoredPrefixes = [
        "lo", "gif", "stf", "utun", "awdl", "llw", "nan", "ap", "anpi", "anri",
        "p2p", "pflog", "vmenet", "XHC",
    ]

    /// Member names that make a bridge a virtual one rather than a way in.
    ///
    /// `bridge100` with `vmenet0` in it is the host side of a
    /// Virtualization.framework guest: it is `UP`, it carries a routable
    /// `192.168.64.1`, and it reaches nothing but the VM. `bridge` itself is
    /// not in ``ignoredPrefixes`` because a bridge over real Ethernet is a
    /// route like any other — it is the membership that decides.
    private static let virtualMemberPrefixes = ["vmenet", "feth", "vlan", "utun", "gif", "stf"]

    // MARK: - R31

    /// **R31 — RDMALink doesn't recognize this Mac.** Read-only mode, not an
    /// error (UX_SPEC §6.2 R31): fires when neither rule in §4.7 recognizes
    /// the Mac, and never on one the identifier catalogue lists.
    ///
    /// Every operation evaluates it **before any other refusal**, in preview
    /// and in perform, so the command-line tool's previews and `refusals`
    /// say the same thing the app does — "the app hiding the buttons is not
    /// the only guard." RDMALink writes nothing on a Mac it does not
    /// recognize, notes included.
    public static func macRecognized(_ model: HardwareModel) -> Refusal? {
        guard !model.isRecognized else { return nil }
        return Refusal(
            code: .macNotRecognized,
            headline: "RDMALink doesn't recognize this Mac",
            body: """
            RDMALink only draws, and only changes, Macs it knows — and this \
            isn't one of them. So there's no picture, and nothing here will be \
            changed. The ports below are listed the way macOS reports them, and \
            everything you see is real.
            """
        )
    }

    // MARK: - R1

    /// **R1 — Two Macs are connected (loop risk).** Blocks preflight and any apply.
    ///
    /// Thunderbolt Bridge forwards Ethernet between Macs, so two cables between
    /// the same pair can put traffic in a loop. Self-clearing: it has no button.
    ///
    /// The loop needs a bridge to forward between the two cables, so a linked
    /// Mac counts only through a bridge: the rule fires when two or more ports
    /// with a Mac on the end are members of the **same** bridge, in the kernel
    /// or in the saved settings. Two cables on two standalone ports are two
    /// point-to-point links — what a finished set-up looks like — and pass.
    public static func oneCableOnly(_ ports: [ObservedPort]) -> Refusal? {
        let candidates = ports.filter(\.hasLinkedMac)
        var linkedMembers: [String: Int] = [:]
        for port in candidates {
            for bridge in Set(port.bridges) { linkedMembers[bridge, default: 0] += 1 }
        }
        let linked = candidates.filter { port in
            port.bridges.contains { linkedMembers[$0, default: 0] > 1 }
        }
        guard linked.count > 1 else { return nil }
        return Refusal(
            code: .twoMacsConnected,
            headline: "Two Macs are connected",
            body: """
            Thunderbolt Bridge forwards Ethernet between Macs, and two cables \
            between the same pair can send traffic around in a loop. Unplug one \
            cable and RDMALink will pick this back up — the other one can go back \
            in when you're done.
            """,
            detail: "\(englishList(linked.map(\.positionName))) each have a Mac on the end.",
            subjects: linked.map(\.bsdName)
        )
    }

    // MARK: - R2

    /// **R2 — Both ends of one cable are in this Mac.** Blocks preflight.
    ///
    /// Fires when a receptacle's cable comes back into another receptacle of
    /// this Mac: ``ObservedPort/loopedBackTo`` names the partner and the
    /// partner names it back. The pairing is made in the inventory from the
    /// Thunderbolt domain identities, so this only has to find a mutual pair;
    /// a one-sided claim is not one. Self-clearing: it has no button.
    ///
    /// Evaluated **before** R1 everywhere both are: a looped cable on two
    /// bridged ports would otherwise be reported as two Macs.
    ///
    /// The spec writes one sentence for one cable, so when more than one pair
    /// is looped the first pair in the order given — physical order — is the
    /// one named; the rest clear the same way, one unplugged end at a time.
    /// The detail is §S3's own finding for the row, which is the only other
    /// sentence the spec writes for this state.
    public static func loopedBackIntoThisMac(_ ports: [ObservedPort]) -> Refusal? {
        let byName = Dictionary(ports.map { ($0.bsdName, $0) }, uniquingKeysWith: { first, _ in first })
        for port in ports {
            guard let partner = port.loopedBackTo.flatMap({ byName[$0] }),
                  partner.bsdName != port.bsdName,
                  partner.loopedBackTo == port.bsdName else { continue }
            let named = englishList([port.positionName, partner.positionName])
            return Refusal(
                code: .loopedBackIntoThisMac,
                headline: "Both ends of that cable are in this Mac",
                body: """
                \(named) are talking to each other — the cable goes out of this \
                Mac and straight back in. It's harmless, but it isn't a link to \
                anywhere. Unplug one end and put it in the other Mac.
                """,
                detail: "Both ends of one cable are in this Mac, on \(named). "
                    + "Unplug one end and put it in the other Mac.",
                subjects: [port.bsdName, partner.bsdName]
            )
        }
        return nil
    }

    // MARK: - R9

    /// **R9 — macOS wouldn't release the port from the bridge.**
    ///
    /// A port has to be out of *every* kernel bridge, including one that is
    /// down, before it can carry RDMA.
    ///
    /// **Precondition only.** R9's body promises "it stopped and changed
    /// nothing at all", which is only true before anything has been written.
    /// The read-back after a member removal is a different situation and has
    /// its own copy: ``rolledBack(port:bridgeName:)`` (R10) once the port is
    /// back in its bridge, and ``rollbackFailed(port:bridge:)`` (R11) when it
    /// could not be put back.
    ///
    /// Membership is read from **both** places it is real. A bridge whose
    /// stored `Interfaces` array still lists the port while the kernel bridge
    /// has no members is not a port that is free: `SCNetworkServiceCreate`
    /// refuses on it with `kSCStatusFailed`, so the rule is unsatisfied and
    /// the spec's own sentence is the right one to print.
    ///
    /// - Parameters:
    ///   - storedBridges: every bridge in the stored configuration, from
    ///     ``StoredBridges/read(clientName:fileURL:)`` or
    ///     ``ObservedWorld/bridges``.
    ///   - bridgeNames: BSD name to human name, e.g.
    ///     `["bridge0": "Thunderbolt Bridge"]`. Missing entries fall back to
    ///     the BSD name rather than guessing.
    public static func portStillBridged(
        _ port: ObservedPort,
        in snapshot: InterfaceSnapshot,
        storedBridges: [BridgeSPI.Membership],
        bridgeNames: [String: String] = [:]
    ) -> Refusal? {
        let kernel = snapshot.bridges(containing: port.bsdName)
        let stored = StoredBridges.names(in: storedBridges, containing: port.bsdName)
        let bridges = kernel + stored.filter { !kernel.contains($0) }
        guard !bridges.isEmpty else { return nil }
        let named = englishList(bridges.map { bridgeNames[$0] ?? $0 })
        return Refusal(
            code: .portStillInBridge,
            headline: "macOS wouldn't let go of that port",
            body: """
            RDMALink couldn't remove \(port.positionName) from \(named), so it \
            stopped and changed nothing at all. You can take it out by hand in \
            System Settings, under Network — open the three-dot menu, choose \
            Manage Virtual Interfaces, open Thunderbolt Bridge and remove just \
            this port. Come back after that and RDMALink will offer to adopt it.
            """,
            detail: "\(port.bsdName) is still a member of \(englishList(bridges)).",
            subjects: [port.bsdName]
        )
    }

    // MARK: - R5

    /// **R5 — This is how you're connected right now.** Hard refusal at
    /// preflight and at review; at review the default button is removed entirely.
    ///
    /// Returns `nil` when some route that is not Thunderbolt is up, because
    /// removing a port from a bridge can briefly interrupt the whole bridge —
    /// not just that port. The refusal covers *any* Thunderbolt-bridge route,
    /// not only the chosen port.
    ///
    /// - Parameters:
    ///   - thunderboltPorts: BSD names of this Mac's Thunderbolt ports.
    ///   - primaryInterfaces: what macOS itself says the default route is on,
    ///     from ``NetworkGlobals/primaryInterfaces(clientName:)``. When it says
    ///     anything at all that is the answer, because it is the only signal
    ///     that means *reachable* rather than *configured*. Empty means macOS
    ///     did not say, and the observed fallback below decides instead.
    public static func managementPathExists(
        in snapshot: InterfaceSnapshot,
        thunderboltPorts: [String],
        primaryInterfaces: [String] = []
    ) -> Refusal? {
        let ports = Set(thunderboltPorts)
        let thunderboltBridges = snapshot.interfaces
            .filter { !$0.members.isEmpty && !ports.isDisjoint(with: $0.members) }
            .map(\.name)
        let excluded = ports.union(thunderboltBridges)

        if !primaryInterfaces.isEmpty {
            if primaryInterfaces.contains(where: { !excluded.contains($0) }) { return nil }
        } else if snapshot.interfaces.contains(where: { carriesManagement($0, excluded: excluded) }) {
            return nil
        }

        return Refusal(
            code: .onlyRouteIsThunderbolt,
            headline: "This is how you're connected right now",
            body: """
            Right now, Thunderbolt is the only way this Mac is reachable. \
            Removing a port from a bridge can briefly interrupt the whole bridge \
            — not just that one port — so this would cut you off half-way \
            through. Connect Wi-Fi or Ethernet first, then come straight back.
            """,
            subjects: thunderboltBridges + thunderboltPorts.filter {
                snapshot[$0]?.isActive == true
            }
        )
    }

    /// Whether one interface could be carrying the connection you are on.
    ///
    /// `isUp` on its own is not evidence: on macOS practically every interface
    /// carries the `UP` flag whatever its carrier state — `en8`–`en12`,
    /// `bridge0` and `ap1` are all `UP` with `status: inactive` on a Mac Studio
    /// — and an unplugged Ethernet port with a Manual address keeps both the
    /// flag and the address. `status: active` is the signal that means a link.
    static func carriesManagement(_ interface: InterfaceState, excluded: Set<String>) -> Bool {
        guard !excluded.contains(interface.name) else { return false }
        guard interface.isUp, interface.isActive else { return false }
        guard !ignoredPrefixes.contains(where: { interface.name.hasPrefix($0) }) else { return false }
        if interface.isBridge, interface.members.allSatisfy(isVirtualMember) { return false }
        return interface.addresses.contains(where: isRoutable)
    }

    /// A member that cannot carry a connection from anywhere else.
    static func isVirtualMember(_ bsdName: String) -> Bool {
        virtualMemberPrefixes.contains { bsdName.hasPrefix($0) }
    }

    /// An address that could carry a management connection: not link-local,
    /// not loopback, not IPv4 self-assigned.
    static func isRoutable(_ address: String) -> Bool {
        if address.hasPrefix("fe80:") { return false }
        if address == "::1" || address.hasPrefix("127.") { return false }
        if address.hasPrefix("169.254.") { return false }
        return true
    }

    // MARK: - R14

    /// **R14 — RDMALink can't save its undo note.** The hard gate that protects
    /// every other promise: it fires at preflight and again immediately before
    /// the first write. If the note cannot be saved, nothing is changed at all.
    ///
    /// Read-only — it inspects the nearest existing ancestor of `url` and never
    /// creates or writes anything.
    public static func baselineWritable(_ url: URL) -> Refusal? {
        var directory = url.standardizedFileURL
        var isDirectory = ObjCBool(false)
        while !FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            || !isDirectory.boolValue {
            let parent = directory.deletingLastPathComponent().standardizedFileURL
            if parent == directory { return baselineUnwritable(detail: "The folder isn't writable.") }
            directory = parent
        }
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            return baselineUnwritable(detail: "The folder isn't writable.")
        }
        let values = try? directory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeNameKey,
        ])
        guard let free = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        guard free < baselineByteEstimate else { return nil }
        let amount = free.formatted(.byteCount(style: .file, spellsOutZero: false))
        let volume = values?.volumeName ?? directory.path
        return baselineUnwritable(detail: "2 KB is all it needs. There's \(amount) free on \(volume).")
    }

    /// **R14**, ready-made. The hard gate also fires immediately before the
    /// first write, when the note itself fails to save.
    public static func baselineUnwritable(detail: String? = nil) -> Refusal {
        Refusal(
            code: .baselineUnwritable,
            headline: "RDMALink can't write down how things are right now",
            body: """
            RDMALink's notes live in your Library folder, and it can't save \
            there at the moment — which means it couldn't put things back \
            afterwards. It won't change anything it can't undo.
            """,
            detail: detail
        )
    }

    // MARK: - R16

    /// **R16 — This port already has a setup RDMALink didn't make.** Blocks
    /// selection, and is distinct from Adopt: there is no path anywhere in the
    /// app that rewrites a service the app did not create.
    public static func foreignService(_ port: ObservedPort, reason: ForeignReason) -> Refusal {
        let found: String
        switch reason {
        case .staticIPv4Address:
            found = "a service on \(port.positionName) with a fixed IPv4 address on it"
        }
        return Refusal(
            code: .foreignService,
            headline: "This port already has a setup RDMALink didn't make",
            body: """
            There's \(found). It isn't RDMALink's and it isn't what a link \
            needs, and RDMALink won't quietly rewrite something you or someone \
            else set up on purpose. Remove it in Network settings if it's \
            stale, or choose another port.
            """,
            subjects: [port.bsdName]
        )
    }

    // MARK: - R8

    /// **R8 — The permission expired mid-burst.**
    ///
    /// The credential `AuthorizationCopyRights` hands back is non-shared and
    /// lasts about thirty seconds, so a burst that runs past it cannot commit.
    /// The port is put back first and the rollback is stated first (§6.1 rule
    /// 7), exactly as R10's is.
    public static func credentialExpired(port: ObservedPort? = nil) -> Refusal {
        Refusal(
            code: .credentialExpired,
            headline: "That took a moment too long",
            body: """
            The permission macOS gives RDMALink lasts about thirty seconds, and \
            it ran out before every change went through — so RDMALink put the \
            port back exactly as it was. Try again; it usually flies through.
            """,
            subjects: port.map { [$0.bsdName] } ?? []
        )
    }

    // MARK: - R12

    /// **R12 — Another app is editing the network.**
    ///
    /// Two writers is how configurations get mangled, so RDMALink refuses
    /// rather than waits. It polls quietly and the refusal clears when the
    /// lock does.
    public static func networkIsBusy(port: ObservedPort? = nil) -> Refusal {
        Refusal(
            code: .networkBusy,
            headline: "Something else has the network open",
            body: """
            System Settings, or another app, is editing the network \
            configuration right now. RDMALink won't write over it — two things \
            writing network settings at once is how configurations get mangled. \
            Close that and RDMALink will try again.
            """,
            subjects: port.map { [$0.bsdName] } ?? []
        )
    }

    // MARK: - R10 and R11

    /// **R10 — The service couldn't be created; rolled back.**
    ///
    /// The refusal for a failure *after* something was written and then undone.
    /// Every refusal that follows a partial write states the rollback first
    /// (UX_SPEC §6.1 rule 7), which is exactly what separates this from R9.
    ///
    /// - Parameters:
    ///   - bridgeName: the bridge the port went back into, named the way
    ///     System Settings names it when that is known.
    ///   - cause: the first clause of the body. The default is the spec's own
    ///     sentence for the case it describes — the service failing to create.
    ///     The other caller is the bridge read-back, where the spec's wording
    ///     would be a claim about a step that was never reached.
    public static func rolledBack(
        port: ObservedPort,
        bridgeName: String,
        cause: String = "The new service wouldn't create"
    ) -> Refusal {
        Refusal(
            code: .rolledBack,
            headline: "Put back, safely",
            body: """
            \(cause), so RDMALink returned the port to \(bridgeName). Nothing \
            has been left half-done, and it checked before telling you.
            """,
            subjects: [port.bsdName]
        )
    }

    /// **R11 — Rollback itself failed.** The most serious state in the app, and
    /// the only one that asks the user to do something by hand.
    ///
    /// The undo note is **kept**: the hub carries "… needs putting back by
    /// hand" until membership is seen again.
    ///
    /// - Parameters:
    ///   - bridgeDisplayName: `Thunderbolt Bridge`, or the BSD name when macOS
    ///     offers no display name.
    ///   - membersBefore: the member list the undo note recorded.
    ///   - membersNow: what the kernel lists right now.
    public static func rollbackFailed(
        port: ObservedPort,
        bridgeBSDName: String,
        bridgeDisplayName: String? = nil,
        membersBefore: [String],
        membersNow: [String]
    ) -> Refusal {
        let named = bridgeDisplayName ?? bridgeBSDName
        return Refusal(
            code: .rollbackFailed,
            headline: "One thing needs your hand",
            body: """
            RDMALink took \(port.positionName) out of \(named), then couldn't \
            finish — and couldn't put it back either. Nothing is broken, but the \
            port is currently in neither place. Open System Settings, under \
            Network, choose Manage Virtual Interfaces, open \(named), and add \
            the port back. Here is exactly how it was.
            """,
            detail: "Bridge: \(named) (\(bridgeBSDName)) · "
                + "Members before: \(membersBefore.joined(separator: ", ")) · "
                + "Members now: \(membersNow.joined(separator: ", ")) · "
                + "The port to add back: \(port.bsdName) — \(port.positionName)",
            subjects: [port.bsdName]
        )
    }

    // MARK: - R15 and R17

    /// **R15 — There's a bridge here RDMALink can't read.** Blocks review for
    /// that port.
    ///
    /// Raised when the kernel lists the port in a bridge the stored
    /// configuration does not have, so there is no object to edit and no
    /// member list to put back. RDMALink won't guess at it.
    ///
    /// - Parameters:
    ///   - kernelBridges: every bridge `ifconfig` says the port is in.
    ///   - configuredBridges: every bridge the SPI can see and edit.
    public static func everyBridgeIsReadable(
        _ port: ObservedPort,
        kernelBridges: [String],
        configuredBridges: [String]
    ) -> Refusal? {
        let unreadable = kernelBridges.filter { !configuredBridges.contains($0) }
        guard !unreadable.isEmpty else { return nil }
        return Refusal(
            code: .bridgeUnreadable,
            headline: "There's a bridge here RDMALink can't make sense of",
            body: """
            \(port.positionName) belongs to a bridge whose settings RDMALink \
            can't read properly, and a port has to be out of every bridge — \
            even one that isn't switched on — before it can carry RDMA. It \
            won't guess at this. Have a look in Network settings, under Manage \
            Virtual Interfaces, and it'll check again when you're back.
            """,
            detail: "\(port.bsdName) is a member of \(englishList(unreadable)), "
                + "which the network configuration doesn't list.",
            subjects: [port.bsdName]
        )
    }

    /// **R17 — The arrangement changed while you were reading.**
    ///
    /// The review screen is a promise about a particular Mac at a particular
    /// moment. When the world re-read inside the burst no longer matches the
    /// one the promise was made about, nothing is written.
    public static func topologyChanged(subjects: [String] = [], detail: String? = nil) -> Refusal {
        Refusal(
            code: .topologyChanged,
            headline: "Something moved",
            body: """
            A cable changed while this was on screen, so what you just read \
            isn't true any more. RDMALink stopped before doing anything rather \
            than act on old information.
            """,
            detail: detail,
            subjects: subjects
        )
    }

    // MARK: - R4

    /// **R4 — Something is still mounted over Thunderbolt.** Blocks preflight
    /// and blocks Restore: a file server reached down the link is the one
    /// thing that would notice the interruption.
    ///
    /// Self-clearing — the check clears on unmount, and the only button is
    /// `Show in Finder`.
    ///
    /// - Parameter volumes: from ``MountedVolumes/over(_:runner:)-(([OperationPort]),_)``.
    ///   Empty means the rule is satisfied.
    public static func nothingMountedOverThunderbolt(_ volumes: [MountedVolume]) -> Refusal? {
        guard let first = volumes.first else { return nil }
        let names = volumes.map(\.name)
        return Refusal(
            code: .volumeMounted,
            headline: "Something is still using this link",
            body: """
            The volume \(first.name) is mounted over Thunderbolt. Eject it in \
            Finder so nothing gets interrupted, then RDMALink will carry on.
            """,
            // The spec gives the plural its own line rather than bending the
            // body, so a second volume is named in the detail and nowhere else.
            detail: names.count > 1
                ? "\(englishList(names)) are mounted over Thunderbolt."
                : nil,
            subjects: Array(Set(volumes.map(\.portBSDName))).sorted()
        )
    }

    // MARK: - R19, R20 and R21

    /// **R19 — The undo note is missing or unreadable.** At Restore.
    ///
    /// RDMALink will not guess at network settings it did not write down.
    /// `Stop Managing This Port` clears only RDMALink's own record.
    public static func undoNoteMissing(port: ObservedPort) -> Refusal {
        Refusal(
            code: .undoNoteMissing,
            headline: "RDMALink can't remember how this looked",
            body: """
            The note RDMALink wrote down for \(port.positionName) is missing, \
            and it won't guess at your network settings. You can remove the \
            service in System Settings, under Network, and add the port back to \
            Thunderbolt Bridge yourself.
            """,
            subjects: [port.bsdName]
        )
    }

    /// **R20 — The bridge doesn't have it back yet.** At Restore, after the
    /// service has gone, and at Return to Bridge (§7.5 step 4).
    ///
    /// The undo note is **never** deleted until verification passes, so this
    /// refusal always leaves something to try again with.
    ///
    /// - Parameter removedService: whether a service was deleted on the way.
    ///   §S10's no-service form omits every sentence about a service (§7.5
    ///   step 2), so on a port that was bare the body opens without the
    ///   clause — it never claims a deletion that did not happen. **The
    ///   no-service body is owed a sentence of its own from the spec owner.**
    public static func notBackInBridge(
        port: ObservedPort, bridgeName: String, removedService: Bool
    ) -> Refusal {
        Refusal(
            code: .notBackInBridge,
            headline: "Not quite back yet",
            body: removedService
                ? """
                The service is gone, but \(bridgeName) isn't listing \
                \(port.positionName) yet. RDMALink has kept your undo note, so \
                nothing is lost and it can try again whenever you like.
                """
                : """
                \(bridgeName) isn't listing \(port.positionName) yet. RDMALink \
                has kept your undo note, so nothing is lost and it can try again \
                whenever you like.
                """,
            detail: """
            Try Again usually does it: RDMALink waits for the port to settle \
            and writes the membership afresh. If it still isn't back, open \
            System Settings › Network, choose Manage Virtual Interfaces, open \
            \(bridgeName) and add \(port.positionName) yourself.
            """,
            subjects: [port.bsdName]
        )
    }

    /// **R21 — The bridge it came from doesn't exist any more.** At Restore.
    ///
    /// The offer is `Remove Service Only`: deleting its own service is
    /// squarely RDMALink's own business, and recreating a bridge is not.
    public static func originalBridgeGone(port: ObservedPort, bridgeName: String) -> Refusal {
        Refusal(
            code: .originalBridgeGone,
            headline: "The bridge it came from doesn't exist any more",
            body: """
            \(bridgeName) has been removed since RDMALink set this port up. It \
            can still delete the service it made — that part is squarely its \
            own — but it won't recreate a bridge, because that's a bigger \
            decision than undoing its own work.
            """,
            subjects: [port.bsdName]
        )
    }

    // MARK: - R29

    /// **There's no Thunderbolt Bridge to return it to.** At Return to Bridge
    /// (UX_SPEC §S10, §7.5 step 3). Nothing is written.
    ///
    /// §6.2 numbers it R29 and points at §S10 for the copy, which is what
    /// the strings below are, verbatim.
    public static func noBridgeToReturnTo(port: ObservedPort) -> Refusal {
        Refusal(
            code: .noBridgeToReturnTo,
            headline: "There's no Thunderbolt Bridge to return it to",
            body: """
            This Mac has no Thunderbolt Bridge at the moment. RDMALink never \
            creates one — recreate it in System Settings, under Network › \
            Manage Virtual Interfaces, and RDMALink will offer the return the \
            moment it exists.
            """,
            subjects: [port.bsdName]
        )
    }

    // MARK: - R30

    /// **R30 — That note only records a return.** At Restore, reached only
    /// from the command line or a stale sheet: the hub never offers `Restore…`
    /// for a return record (§7.5).
    ///
    /// The note is kept and nothing is written. R19 is not this — its body
    /// says the note is missing, and here it is sitting there intact.
    ///
    /// - Parameter bridgeName: the bridge as it is shown to a person —
    ///   ``BridgeReturn/name``.
    public static func noteIsAReturnRecord(port: ObservedPort, bridgeName: String) -> Refusal {
        Refusal(
            code: .noteIsAReturnRecord,
            headline: "Nothing to put back",
            body: """
            RDMALink's note for \(port.positionName) only records that it put \
            the port back in \(bridgeName). There's nothing to undo — Set It Up \
            Again takes the port out of the bridge, and Stop Managing forgets \
            the note.
            """,
            subjects: [port.bsdName]
        )
    }

    /// **R30's adopted form** — the note only records an adoption. Same
    /// number, same headline, §6.2's other body: an adopted port has no
    /// bridge history and nothing to put back (§7.3), and the port keeps its
    /// setup. Its row is `Stop Managing…` and `Cancel`; there is no `Set It
    /// Up Again`, because the port is set up.
    ///
    /// The note is kept and nothing is written. R19 is not this either.
    public static func noteIsAnAdoptionRecord(port: ObservedPort) -> Refusal {
        Refusal(
            code: .noteIsAReturnRecord,
            headline: "Nothing to put back",
            body: """
            RDMALink's note for \(port.positionName) only records that it \
            adopted the port as it found it. There's nothing to undo — Stop \
            Managing forgets the note, and the port keeps its setup.
            """,
            subjects: [port.bsdName]
        )
    }

    // MARK: - R28

    /// **R28 — the service RDMALink made is not the one it made any more.**
    /// At Restore, before anything is deleted.
    ///
    /// RDMALink matches its own service by identifier and never by name, so a
    /// service the user renames is still recognised — but a service the user
    /// has taken over, given a fixed address and routed real traffic through
    /// is not RDMALink's work any more, whatever its identifier says. Deleting
    /// it would take the addresses with it.
    public static func createdServiceEdited(
        port: ObservedPort,
        differences: [String]
    ) -> Refusal {
        Refusal(
            code: .createdServiceEdited,
            headline: "This port's service isn't the one RDMALink made any more",
            body: """
            The service RDMALink created on \(port.positionName) has been \
            changed since — it's carrying settings RDMALink didn't put there, \
            and it won't quietly delete something you've made your own. Remove \
            it yourself in Network settings if you're done with it, or tell \
            RDMALink to stop looking after this port and it'll leave everything \
            exactly where it is.
            """,
            detail: differences.isEmpty ? nil : englishList(differences) + ".",
            subjects: [port.bsdName]
        )
    }
}
