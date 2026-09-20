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
}
