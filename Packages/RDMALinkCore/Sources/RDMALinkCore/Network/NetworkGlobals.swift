import Foundation
import SystemConfiguration

/// What macOS itself says this Mac's route to the outside is, right now.
///
/// `State:/Network/Global/IPv4` and `State:/Network/Global/IPv6` carry
/// `PrimaryInterface`, which is the interface the default route is on — the
/// literal answer to "how are you connected right now", and the one R5 needs.
/// Inferring it from addresses instead over-counts: on macOS practically every
/// interface carries the `UP` flag whatever its carrier state, and a
/// Virtualization.framework host bridge (`bridge100`, `inet 192.168.64.1`)
/// looks exactly like a route it can never be.
///
/// Read-only: it opens an `SCDynamicStore` and copies two keys.
public enum NetworkGlobals {
    /// The primary IPv4 and IPv6 interfaces, de-duplicated, in that order.
    ///
    /// Empty means macOS has no default route at all — which is not the same
    /// as "no route", so the callers treat it as *unknown* and fall back to
    /// what they can observe rather than refusing on it.
    public static func primaryInterfaces(clientName: String = "RDMALink") -> [String] {
        guard let store = SCDynamicStoreCreate(nil, clientName as CFString, nil, nil) else {
            return []
        }
        var found: [String] = []
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            let value = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
            guard let name = value?[kSCDynamicStorePropNetPrimaryInterface as String] as? String,
                  !name.isEmpty, !found.contains(name) else { continue }
            found.append(name)
        }
        return found
    }

    /// What kind of interface a route is on, and what macOS calls it.
    ///
    /// §S3 row 3's satisfied finding names **Wi-Fi** by name, so the row needs
    /// more than a BSD name to print it. `SCNetworkInterfaceGetInterfaceType`
    /// is public API and answers exactly this.
    public struct RouteKind: Sendable, Equatable {
        public var bsdName: String
        /// `kSCNetworkInterfaceTypeIEEE80211`.
        public var isWiFi: Bool
        /// What System Settings calls it — "Wi-Fi", "Ethernet", "Thunderbolt
        /// Bridge". `nil` when macOS offers no name.
        public var displayName: String?

        public init(bsdName: String, isWiFi: Bool, displayName: String?) {
            self.bsdName = bsdName
            self.isWiFi = isWiFi
            self.displayName = displayName
        }
    }

    /// Describes one interface by BSD name. Read-only, public API only.
    public static func routeKind(of bsdName: String) -> RouteKind? {
        let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        guard let interface = all.first(where: {
            (SCNetworkInterfaceGetBSDName($0) as String?) == bsdName
        }) else { return nil }
        let type = SCNetworkInterfaceGetInterfaceType(interface) as String?
        return RouteKind(
            bsdName: bsdName,
            isWiFi: type == (kSCNetworkInterfaceTypeIEEE80211 as String),
            displayName: SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?)
    }
}
