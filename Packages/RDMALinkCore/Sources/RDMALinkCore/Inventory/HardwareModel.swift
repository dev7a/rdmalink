import Darwin
import Foundation

/// The chassis families RDMALink knows how to draw and how to name ports on.
///
/// An archetype is about *geometry*, not about the chip: it decides which
/// receptacles exist, which of them are USB-only, and which position names from
/// UX_SPEC §4.7 apply. A Mac whose identifier is not in the catalogue is
/// ``Archetype/unknown`` and still works — the picture is a stand-in and the
/// ports are numbered the way macOS reports them.
public enum Archetype: String, Sendable, CaseIterable {
    /// Mac Studio with four Thunderbolt receptacles on the back and two
    /// USB-only receptacles on the front.
    case studioFour
    /// Mac Studio with four Thunderbolt receptacles on the back and two more on
    /// the front.
    case studioSix
    /// Mac mini: three Thunderbolt receptacles on the back, two USB-only on the
    /// front.
    case mini
    /// MacBook Pro 14/16: two receptacles on the left side, one on the right.
    case notebook
    /// Not recognized. Everything still works; nothing is guessed.
    case unknown
}

/// What this Mac is, in the words the app uses everywhere else.
///
/// The window subtitle in UX_SPEC S0 reads `Studio — Mac Studio (M3 Ultra)`,
/// which is ``marketingName`` and ``chip``.
public struct HardwareModel: Sendable, Equatable {
    /// `hw.model`, for example `Mac15,14`. Empty only if `sysctl` refused.
    public var identifier: String
    /// `Mac Studio`, `Mac mini`, `MacBook Pro` — or `Mac` when unrecognized.
    public var marketingName: String
    /// `M3 Ultra`, from `machdep.cpu.brand_string` with the `Apple ` prefix off.
    public var chip: String
    /// The chassis family, or ``Archetype/unknown``.
    public var archetype: Archetype

    public init(identifier: String, marketingName: String, chip: String, archetype: Archetype) {
        self.identifier = identifier
        self.marketingName = marketingName
        self.chip = chip
        self.archetype = archetype
    }

    /// Reads this Mac's identity. Never fails: an unreadable `sysctl` leaves the
    /// field empty and the archetype ``Archetype/unknown``.
    public static func read() -> HardwareModel {
        let identifier = sysctlString("hw.model") ?? ""
        let known = catalog[identifier]
        return HardwareModel(
            identifier: identifier,
            marketingName: known?.marketingName ?? "Mac",
            chip: chipName(fromBrandString: sysctlString("machdep.cpu.brand_string") ?? ""),
            archetype: known?.archetype ?? .unknown
        )
    }

    /// True when the catalogue recognized ``identifier``.
    public var isRecognized: Bool { archetype != .unknown }
}

extension HardwareModel {
    /// One catalogue row: what to call the Mac and how it is shaped.
    struct KnownMac: Sendable, Equatable {
        var marketingName: String
        var archetype: Archetype
    }

    /// Every Mac RDMALink can draw. Deliberately short: an identifier that is
    /// missing from here degrades to a numbered, generic presentation rather
    /// than to a wrong picture.
    ///
    /// `Mac15,14` is verified on this hardware. The rest are the published
    /// identifiers for the machines UX_SPEC §4.7 names.
    static let catalog: [String: KnownMac] = [
        // Mac Studio (2025).
        "Mac15,14": KnownMac(marketingName: "Mac Studio", archetype: .studioSix),   // M3 Ultra
        "Mac16,9": KnownMac(marketingName: "Mac Studio", archetype: .studioFour),   // M4 Max
        // Mac mini (2024) — both share one chassis and one port layout.
        "Mac16,10": KnownMac(marketingName: "Mac mini", archetype: .mini),          // M4
        "Mac16,11": KnownMac(marketingName: "Mac mini", archetype: .mini),          // M4 Pro
        // MacBook Pro 14/16.
        "Mac16,1": KnownMac(marketingName: "MacBook Pro", archetype: .notebook),
        "Mac16,5": KnownMac(marketingName: "MacBook Pro", archetype: .notebook),
        "Mac16,6": KnownMac(marketingName: "MacBook Pro", archetype: .notebook),
        "Mac16,7": KnownMac(marketingName: "MacBook Pro", archetype: .notebook),
        "Mac16,8": KnownMac(marketingName: "MacBook Pro", archetype: .notebook),
        "Mac17,1": KnownMac(marketingName: "MacBook Pro", archetype: .notebook),
    ]

    /// `Apple M3 Ultra` → `M3 Ultra`. Anything else is passed through trimmed,
    /// because a chip name nobody recognizes is still better than none.
    static func chipName(fromBrandString brand: String) -> String {
        let trimmed = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("Apple ") else { return trimmed }
        return String(trimmed.dropFirst("Apple ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension HardwareModel {
    /// Reads a string `sysctl` by name, or nil when the name is absent.
    static func sysctlString(_ name: String) -> String? {
        var probe = 0
        guard sysctlbyname(name, nil, &probe, nil, 0) == 0, probe > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: probe)
        var length = probe
        let status = bytes.withUnsafeMutableBufferPointer { buffer in
            sysctlbyname(name, buffer.baseAddress, &length, nil, 0)
        }
        guard status == 0 else { return nil }
        let text = bytes.prefix { $0 != 0 }
        return text.isEmpty ? nil : String(decoding: text, as: UTF8.self)
    }
}
