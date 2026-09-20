import Foundation

/// One bridge a port belonged to, with the whole member list as it was found.
///
/// The app never creates or deletes a bridge; it only removes a member and only
/// puts a member back. The member list is recorded so a restore can say — and
/// check — exactly what it is putting back.
public struct BridgeMembership: Sendable, Codable, Equatable {
    /// The kernel interface name, such as `bridge0`.
    public var bridgeName: String
    /// The identifier of the bridge's network service, when it has one.
    /// Matching is by identifier, never by name.
    public var serviceIdentifier: String?
    /// The name shown in System Settings, such as `Thunderbolt Bridge`,
    /// recorded for the copy and the diagnostics file only.
    public var displayName: String?
    /// Every member of the bridge before the change, in the order found.
    public var members: [String]
    /// Whether the bridge was up. A port has to leave even an inactive bridge.
    public var isActive: Bool

    public init(
        bridgeName: String,
        serviceIdentifier: String? = nil,
        displayName: String? = nil,
        members: [String],
        isActive: Bool
    ) {
        self.bridgeName = bridgeName
        self.serviceIdentifier = serviceIdentifier
        self.displayName = displayName
        self.members = members
        self.isActive = isActive
    }
}

/// A network service as it was found: identified by its identifier, with its
/// name and service-order position kept for the copy and the diagnostics file.
public struct ServiceRecord: Sendable, Codable, Equatable {
    /// `SCNetworkServiceGetServiceID`. The only thing ever matched on.
    public var identifier: String
    /// The service name at the time the note was taken. Never matched on: a
    /// service the user renames afterwards is still the same service.
    public var name: String?
    /// The service's position in the set's service order, when it had one.
    public var orderIndex: Int?

    public init(identifier: String, name: String? = nil, orderIndex: Int? = nil) {
        self.identifier = identifier
        self.name = name
        self.orderIndex = orderIndex
    }
}

/// The service RDMALink created, as it was the moment it was created.
///
/// Restore matches it by ``identifier`` and never by ``name`` — a service the
/// user renames is still the same service (`docs/ARCHITECTURE.md`, rule 2).
/// The rest of the snapshot is what makes the deletion safe: months later that
/// same identifier may be carrying a fixed address and real traffic, and a
/// service somebody has taken over is not RDMALink's work any more, whatever
/// its identifier says.
public struct CreatedServiceRecord: Sendable, Codable, Equatable {
    /// `SCNetworkServiceGetServiceID`. The only thing ever matched on.
    public var identifier: String
    /// The interface the service was created on. Checked before any deletion,
    /// so a note carrying someone else's identifier cannot delete Wi-Fi.
    public var interfaceBSDName: String
    /// The name RDMALink gave it, e.g. `RDMA — Back, far left`.
    public var name: String?
    /// Whether the service was enabled when it was made.
    public var isEnabled: Bool?
    /// IPv4 as RDMALink left it: off.
    public var ipv4: ProtocolConfiguration?
    /// IPv6 as RDMALink left it: link-local only.
    public var ipv6: ProtocolConfiguration?

    public init(
        identifier: String,
        interfaceBSDName: String,
        name: String? = nil,
        isEnabled: Bool? = nil,
        ipv4: ProtocolConfiguration? = nil,
        ipv6: ProtocolConfiguration? = nil
    ) {
        self.identifier = identifier
        self.interfaceBSDName = interfaceBSDName
        self.name = name
        self.isEnabled = isEnabled
        self.ipv4 = ipv4
        self.ipv6 = ipv6
    }

    /// How a live service differs from the one RDMALink made, in the app's own
    /// words. Empty means it is still RDMALink's own work and safe to delete.
    ///
    /// Compared by **meaning, not by bytes**: macOS normalises a stored
    /// configuration after a commit, so a field-for-field match would refuse
    /// every restore. What matters is whether the service is still what a link
    /// needs and nothing else — on this port, IPv4 off, IPv6 link-local. The
    /// name is deliberately not compared: a service the user renames is still
    /// the same service (`docs/ARCHITECTURE.md`, rule 2).
    public func differences(from live: NetworkServiceInfo) -> [String] {
        var found: [String] = []
        if live.interfaceBSDName != interfaceBSDName {
            found.append("it's on \(live.interfaceBSDName ?? "no interface") now, "
                + "not \(interfaceBSDName)")
        }
        if !NetworkServices.isOff(live.ipv4) {
            found.append("IPv4 has been turned back on"
                + (live.ipv4?.hasManualAddresses == true ? ", with an address of its own" : ""))
        }
        if let ipv6 = live.ipv6 {
            if !ipv6.isEnabled {
                found.append("IPv6 has been turned off")
            } else if ipv6.configMethod != NetworkServices.linkLocalMethod {
                found.append("IPv6 is set to \(ipv6.configMethod ?? "something else") now")
            }
        } else {
            found.append("IPv6 has been turned off")
        }
        return found
    }
}

/// The undo note for one port: everything needed to put it back the way it was,
/// written **before** the first write. If it cannot be written, nothing is
/// changed at all (R14).
public struct PortBaseline: Sendable, Codable, Equatable {

    /// The schema this build writes and the only one it reads.
    public static let currentVersion = 1

    /// The schema version of this note.
    public var version: Int
    /// The kernel interface name, such as `en6`. Also the note's file name.
    public var bsdName: String
    /// `IOLocation`, the receptacle index, 1-based.
    public var receptacle: Int
    /// The position name in the same words the rest of the app uses, such as
    /// `Back, far left`.
    public var positionName: String
    /// True when the user set this port up by hand and RDMALink only adopted
    /// it. An adopted note has no bridge history and nothing to put back —
    /// the only action is Stop Managing.
    public var isAdopted: Bool
    /// Every bridge the port belonged to, active and inactive, with each
    /// bridge's full member list.
    public var bridges: [BridgeMembership]
    /// The service that already existed on this interface, if there was one.
    public var existingService: ServiceRecord?
    /// The port's IPv4 configuration as it was found, exactly as
    /// ``NetworkServices`` read it.
    public var ipv4: ProtocolConfiguration?
    /// The port's IPv6 configuration as it was found.
    public var ipv6: ProtocolConfiguration?
    /// The service RDMALink created, captured at creation time. `nil` until
    /// the service exists — the note is written first.
    public var createdService: CreatedServiceRecord?
    /// When the note was taken. The restore copy quotes it verbatim.
    public var recordedAt: Date
    /// The macOS build the note was taken on, such as `26B5086k`.
    public var systemBuild: String

    public init(
        version: Int = PortBaseline.currentVersion,
        bsdName: String,
        receptacle: Int,
        positionName: String,
        isAdopted: Bool = false,
        bridges: [BridgeMembership] = [],
        existingService: ServiceRecord? = nil,
        ipv4: ProtocolConfiguration? = nil,
        ipv6: ProtocolConfiguration? = nil,
        createdService: CreatedServiceRecord? = nil,
        recordedAt: Date = Date(),
        systemBuild: String = SystemBuild.current
    ) {
        self.version = version
        self.bsdName = bsdName
        self.receptacle = receptacle
        self.positionName = positionName
        self.isAdopted = isAdopted
        self.bridges = bridges
        self.existingService = existingService
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.createdService = createdService
        self.recordedAt = recordedAt
        self.systemBuild = systemBuild
    }

    /// The note for a port RDMALink adopted: no bridge history, because it
    /// never saw which bridge the port came from, and no created service,
    /// because it did not create one.
    public static func adopted(
        bsdName: String,
        receptacle: Int,
        positionName: String,
        existingService: ServiceRecord? = nil,
        ipv4: ProtocolConfiguration? = nil,
        ipv6: ProtocolConfiguration? = nil,
        recordedAt: Date = Date(),
        systemBuild: String = SystemBuild.current
    ) -> PortBaseline {
        PortBaseline(
            bsdName: bsdName,
            receptacle: receptacle,
            positionName: positionName,
            isAdopted: true,
            bridges: [],
            existingService: existingService,
            ipv4: ipv4,
            ipv6: ipv6,
            createdService: nil,
            recordedAt: recordedAt,
            systemBuild: systemBuild
        )
    }

    /// The identifier of the service RDMALink created, when it has one.
    public var createdServiceIdentifier: String? { createdService?.identifier }

    /// A kernel interface name RDMALink will accept as a note's name: it is
    /// also the note's file name, so nothing else may get in.
    public static func isValidBSDName(_ value: String) -> Bool {
        guard let first = value.first, first.isASCII, first.isLetter else { return false }
        guard value.utf8.count < 16 else { return false }  // IFNAMSIZ
        return value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// Checks the invariants a note must hold, on the way in and on the way out.
    ///
    /// - Throws: ``BaselineStoreError/unsupportedVersion(_:)`` or
    ///   ``BaselineStoreError/malformed(_:)``.
    public func validate() throws {
        guard version == Self.currentVersion else {
            throw BaselineStoreError.unsupportedVersion(version)
        }
        guard Self.isValidBSDName(bsdName) else {
            throw BaselineStoreError.malformed("\(bsdName) is not an interface name")
        }
        guard receptacle >= 0 else {
            throw BaselineStoreError.malformed("\(bsdName) has receptacle \(receptacle)")
        }
        if isAdopted {
            guard bridges.isEmpty else {
                throw BaselineStoreError.malformed("An adopted note for \(bsdName) carries bridge history")
            }
            guard createdService == nil else {
                throw BaselineStoreError.malformed("An adopted note for \(bsdName) claims a created service")
            }
        }
        // A created service is only ever this port's. Without this, a note
        // whose identifier has been hand-edited to the Wi-Fi service's UUID
        // decodes cleanly and Restore deletes the machine's only route.
        if let createdService {
            guard createdService.interfaceBSDName == bsdName else {
                throw BaselineStoreError.malformed(
                    "\(bsdName)'s note claims a service on \(createdService.interfaceBSDName)")
            }
            guard !createdService.identifier.isEmpty else {
                throw BaselineStoreError.malformed("\(bsdName)'s created service has no identifier")
            }
        }
        for bridge in bridges where bridge.bridgeName.isEmpty {
            throw BaselineStoreError.malformed("A bridge in \(bsdName)'s note has no name")
        }
    }
}
