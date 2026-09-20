import Foundation
import IOKit

/// What only undocumented registry keys can say about a receptacle.
///
/// Every field is optional and nil means "this Mac did not say", never a guess.
struct ReceptacleEnrichment: Sendable, Equatable {
    /// Where the receptacle is on the chassis.
    var position: PortPosition?
    /// Whether anything at all is plugged in — the one signal that separates a
    /// dock from an empty receptacle, both of which read `IOLinkStatus` 1.
    var deviceAttached: Bool?
}

/// Everything one pass over the device tree can say about this chassis.
struct ChassisEnrichment: Sendable, Equatable {
    /// The Thunderbolt receptacles, keyed by receptacle index.
    var byReceptacle: [Int: ReceptacleEnrichment] = [:]
    /// The positions with no `AppleThunderboltIPPort` behind them — the
    /// USB-only receptacles — and whether something is plugged into each.
    ///
    /// These have no receptacle index to join on, so nothing else in the read
    /// can reach them; the chassis catalogue owns their rows, and this is the
    /// only signal anywhere that says a cable is in one. UX_SPEC §4.5 and §S1
    /// need exactly that and nothing more.
    var cabledPositions: Set<PortPosition> = []
}

/// Reads physical position and plug presence out of the device tree.
///
/// This is best-effort enrichment behind the public-key read, exactly as
/// ARCHITECTURE.md requires: the whole probe is allowed to return nothing, and
/// on a Mac that publishes none of these keys it does.
///
/// The shape on Mac15,14, verified 2026-09-19:
///
/// - `hpm0…hpm5` (`AppleARMSPMIDevice`) each carry `port-location`
///   (`back-left`, `front-right`, …) and `acio-parent`, a four-byte phandle.
/// - `acio0…acio5` (`AppleARMIODevice`) carry the matching `AAPL,phandle`.
/// - The `AppleThunderboltIPPort` in an `acio` node's IOService subtree gives
///   the receptacle index, which is the key everything else joins on.
/// - The `AppleHPMInterfaceType10` node under an `hpm` node carries
///   `ConnectionActive`.
enum ChassisProbe {
    /// The `AppleARMSPMIDevice` nodes carrying a `port-location`.
    private static let positionNodeClass = "AppleARMSPMIDevice"
    /// The `AppleARMIODevice` nodes named `acioN`.
    private static let acioNodeClass = "AppleARMIODevice"
    private static let portLocationKey = "port-location"
    private static let acioParentKey = "acio-parent"
    private static let phandleKey = "AAPL,phandle"
    private static let connectionActiveKey = "ConnectionActive"
    private static let thunderboltPortClass = "AppleThunderboltIPPort"
    private static let receptacleKey = "IOLocation"

    /// Facts about one receptacle, before the phandle has been resolved.
    private struct Unresolved {
        var position: PortPosition?
        var deviceAttached: Bool?
    }

    /// Reads the enrichment. Returns an empty value rather than throwing: a
    /// Mac with none of these keys is a supported Mac.
    static func read() -> ChassisEnrichment {
        let byPhandle = positionNodes()
        guard !byPhandle.isEmpty else { return ChassisEnrichment() }
        let receptacles = receptacles(forAcioPhandles: Set(byPhandle.keys))
        var result = ChassisEnrichment()
        for (phandleValue, facts) in byPhandle {
            // A position node with no Thunderbolt port behind it is a USB-only
            // receptacle. It has no receptacle index to be joined on, so its
            // position is all there is — and its `ConnectionActive` is the one
            // thing that can say a cable is in one.
            guard let receptacle = receptacles[phandleValue] else {
                if let position = facts.position, facts.deviceAttached == true {
                    result.cabledPositions.insert(position)
                }
                continue
            }
            result.byReceptacle[receptacle] = ReceptacleEnrichment(
                position: facts.position,
                deviceAttached: facts.deviceAttached
            )
        }
        return result
    }

    /// Every `port-location` node, keyed by the phandle of its `acio` parent.
    private static func positionNodes() -> [UInt32: Unresolved] {
        var result: [UInt32: Unresolved] = [:]
        try? IORegistry.forEachService(matchingClass: positionNodeClass) { entry in
            guard let location = IORegistry.string(entry, portLocationKey),
                  let parent = IORegistry.data(entry, acioParentKey),
                  let parentPhandle = DeviceTree.phandle(parent)
            else { return }
            // Two nodes claiming one acio parent would make the join ambiguous.
            // Drop both rather than pick one.
            if result[parentPhandle] != nil {
                result[parentPhandle] = Unresolved(position: nil, deviceAttached: nil)
                return
            }
            result[parentPhandle] = Unresolved(
                position: PortPosition.parse(location),
                deviceAttached: IORegistry.firstDescendant(of: entry, plane: kIOServicePlane) {
                    IORegistry.boolean($0, connectionActiveKey)
                }
            )
        }
        return result
    }

    /// Receptacle index for each `acioN` node whose phandle is wanted.
    private static func receptacles(forAcioPhandles wanted: Set<UInt32>) -> [UInt32: Int] {
        var result: [UInt32: Int] = [:]
        try? IORegistry.forEachService(matchingClass: acioNodeClass) { entry in
            guard let name = IORegistry.name(entry, plane: kIODeviceTreePlane),
                  isAcioNodeName(name),
                  let phandleData = IORegistry.data(entry, phandleKey),
                  let value = DeviceTree.phandle(phandleData),
                  wanted.contains(value)
            else { return }
            let receptacle = IORegistry.firstDescendant(of: entry, plane: kIOServicePlane) { child in
                IOObjectConformsTo(child, thunderboltPortClass) != 0
                    ? IORegistry.integer(child, receptacleKey)
                    : nil
            }
            if let receptacle { result[value] = receptacle }
        }
        return result
    }

    /// `acio0` yes, `acio-cpu0` and `acio-phy-cpu3` no.
    static func isAcioNodeName(_ name: String) -> Bool {
        guard name.hasPrefix("acio") else { return false }
        let suffix = name.dropFirst("acio".count)
        return !suffix.isEmpty && suffix.allSatisfy(\.isASCII) && suffix.allSatisfy(\.isNumber)
    }
}
