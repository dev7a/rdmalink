import Foundation
import SystemConfiguration

/// One IP protocol of one network service, as the stored preferences describe it.
public struct ProtocolConfiguration: Sendable, Equatable, Codable {
    public var isEnabled: Bool
    /// The `ConfigMethod` value, e.g. `DHCP`, `Manual`, `LinkLocal`, `Automatic`.
    public var configMethod: String?
    /// True when the configuration carries addresses of its own.
    public var hasManualAddresses: Bool

    public init(isEnabled: Bool, configMethod: String?, hasManualAddresses: Bool) {
        self.isEnabled = isEnabled
        self.configMethod = configMethod
        self.hasManualAddresses = hasManualAddresses
    }
}

/// A network service in the current location, flattened to plain values.
///
/// Matching is by ``serviceID``, never by ``name`` (`docs/ARCHITECTURE.md`,
/// rule 2): a service the user renames is still recognised, and a service that
/// happens to share RDMALink's name is never mistaken for one of its own.
public struct NetworkServiceInfo: Sendable, Equatable, Codable, Identifiable {
    public var serviceID: String
    public var name: String
    public var interfaceBSDName: String?
    public var isEnabled: Bool
    public var ipv4: ProtocolConfiguration?
    public var ipv6: ProtocolConfiguration?

    public var id: String { serviceID }

    public init(
        serviceID: String,
        name: String,
        interfaceBSDName: String?,
        isEnabled: Bool,
        ipv4: ProtocolConfiguration? = nil,
        ipv6: ProtocolConfiguration? = nil
    ) {
        self.serviceID = serviceID
        self.name = name
        self.interfaceBSDName = interfaceBSDName
        self.isEnabled = isEnabled
        self.ipv4 = ipv4
        self.ipv6 = ipv6
    }
}

/// One way a hand-made service differs from what RDMALink would have made.
public enum ConfigurationDifference: Sendable, Equatable {
    case stillInBridge(String)
    case serviceDisabled
    case ipv4NotOff(method: String?)
    case ipv6NotLinkLocal(method: String?)
    case ipv6Disabled
    /// The interface carries more than one service. macOS allows it, and it is
    /// not what RDMALink would have made, so the port is never rewritten.
    case severalServices(count: Int)
}

/// Why a service is one RDMALink will not touch.
public enum ForeignReason: Sendable, Equatable {
    /// A fixed IPv4 address someone set on purpose — R16.
    case staticIPv4Address
}

/// What a port's configuration is, read off observed state alone.
///
/// This says nothing about *who* made a service — that is the baseline's job,
/// by identifier. A port that matches is offered Adopt, never reconfiguration.
public enum PortConfiguration: Sendable, Equatable {
    /// No service of its own. `bridges` is every kernel bridge it is a member of.
    case unconfigured(bridges: [String])
    /// Exactly what RDMALink would have made: out of every bridge, its own
    /// service, IPv4 off, IPv6 link-local only. Offered Adopt (S9, full match).
    case readyForRDMA(serviceID: String)
    /// Its own service, but something differs. Shown as S9's near match and
    /// never adjusted: RDMALink did not create it and will not rewrite it.
    case nearMatch(serviceID: String, differences: [ConfigurationDifference])
    /// A setup RDMALink didn't make and won't quietly rewrite — R16.
    case foreign(serviceID: String, reason: ForeignReason)
}

/// Reads network services out of the stored configuration, and classifies a port.
public enum NetworkServices {
    /// `ConfigMethod` values that mean "link-local only".
    static let linkLocalMethod = kSCValNetIPv6ConfigMethodLinkLocal as String
    /// `ConfigMethod` values some releases use to mean "off".
    static let offMethods: Set<String> = ["None", "Off"]

    /// Opens the stored network preferences read-only and lists every service.
    ///
    /// No authorization, no lock, no write. `SCPreferencesCreate` without an
    /// `AuthorizationRef` can only read.
    public static func read(clientName: String = "RDMALink") throws -> [NetworkServiceInfo] {
        guard let preferences = SCPreferencesCreate(nil, clientName as CFString, nil) else {
            throw NetworkConfigurationError.preferencesUnavailable(SCError())
        }
        return read(from: preferences)
    }

    /// Lists every service in an already-open preferences session.
    public static func read(from preferences: SCPreferences) -> [NetworkServiceInfo] {
        let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] ?? []
        return services.compactMap(describe)
    }

    /// Every service on one interface, in configuration order.
    ///
    /// macOS allows several: a Mac can have two "Ethernet" services on `en0`,
    /// one DHCP and one with a fixed address. So this returns all of them and
    /// ``classify(services:bridges:)`` judges the port, not one service.
    public static func services(
        for bsdName: String,
        in services: [NetworkServiceInfo]
    ) -> [NetworkServiceInfo] {
        services.filter { $0.interfaceBSDName == bsdName }
    }

    /// Flattens one `SCNetworkService` into plain values.
    static func describe(_ service: SCNetworkService) -> NetworkServiceInfo? {
        guard let serviceID = SCNetworkServiceGetServiceID(service) as String? else { return nil }
        let interface = SCNetworkServiceGetInterface(service)
        return NetworkServiceInfo(
            serviceID: serviceID,
            name: SCNetworkServiceGetName(service) as String? ?? "",
            interfaceBSDName: interface.flatMap { SCNetworkInterfaceGetBSDName($0) as String? },
            isEnabled: SCNetworkServiceGetEnabled(service),
            ipv4: describe(service, kSCNetworkProtocolTypeIPv4,
                           method: kSCPropNetIPv4ConfigMethod, addresses: kSCPropNetIPv4Addresses),
            ipv6: describe(service, kSCNetworkProtocolTypeIPv6,
                           method: kSCPropNetIPv6ConfigMethod, addresses: kSCPropNetIPv6Addresses)
        )
    }

    private static func describe(
        _ service: SCNetworkService,
        _ type: CFString,
        method: CFString,
        addresses: CFString
    ) -> ProtocolConfiguration? {
        guard let value = SCNetworkServiceCopyProtocol(service, type) else { return nil }
        let configuration = SCNetworkProtocolGetConfiguration(value) as? [String: Any]
        return ProtocolConfiguration(
            isEnabled: SCNetworkProtocolGetEnabled(value),
            configMethod: configuration?[method as String] as? String,
            hasManualAddresses: (configuration?[addresses as String] as? [Any])?.isEmpty == false
        )
    }

    // MARK: - Classification

    /// Classifies one port from the services on it and its bridge membership.
    ///
    /// Pure: it reads nothing. `bridges` comes from
    /// ``InterfaceSnapshot/bridges(containing:)`` so a bridge that is down
    /// counts exactly as much as one that is up.
    public static func classify(
        services: [NetworkServiceInfo],
        bridges: [String]
    ) -> PortConfiguration {
        if let foreign = services.first(where: { isStaticIPv4($0.ipv4) }) {
            return .foreign(serviceID: foreign.serviceID, reason: .staticIPv4Address)
        }
        guard let service = services.first else { return .unconfigured(bridges: bridges) }
        var differences: [ConfigurationDifference] = bridges.map { .stillInBridge($0) }
        if services.count > 1 { differences.append(.severalServices(count: services.count)) }
        if !service.isEnabled { differences.append(.serviceDisabled) }
        if !isOff(service.ipv4) {
            differences.append(.ipv4NotOff(method: service.ipv4?.configMethod))
        }
        if let ipv6 = service.ipv6 {
            if !ipv6.isEnabled {
                differences.append(.ipv6Disabled)
            } else if ipv6.configMethod != linkLocalMethod {
                differences.append(.ipv6NotLinkLocal(method: ipv6.configMethod))
            }
        } else {
            differences.append(.ipv6Disabled)
        }
        if differences.isEmpty { return .readyForRDMA(serviceID: service.serviceID) }
        return .nearMatch(serviceID: service.serviceID, differences: differences)
    }

    /// IPv4 is off when the protocol is absent, disabled, or explicitly off.
    static func isOff(_ configuration: ProtocolConfiguration?) -> Bool {
        guard let configuration else { return true }
        if !configuration.isEnabled { return true }
        return configuration.configMethod.map(offMethods.contains) ?? false
    }

    /// A fixed IPv4 address someone set deliberately: RDMALink won't rewrite it.
    static func isStaticIPv4(_ configuration: ProtocolConfiguration?) -> Bool {
        guard let configuration, configuration.isEnabled else { return false }
        if configuration.configMethod == (kSCValNetIPv4ConfigMethodManual as String) { return true }
        return configuration.hasManualAddresses
    }
}
