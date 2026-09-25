import Darwin
import Foundation

/// The chassis families RDMALink knows how to draw and how to name ports on.
///
/// An archetype is about *geometry*, not about the chip: it decides which
/// receptacles exist, which of them are USB-only, and which position names from
/// UX_SPEC §4.7 apply. A Mac that neither the identifier catalogue nor the
/// family-and-layout rule of §4.7 recognizes is ``Archetype/unknown``, and the
/// app is read-only there (UX_SPEC §6.2 R31): no chassis is drawn, the ports
/// are numbered the way macOS reports them, and every operation refuses.
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
    /// Not recognized. Nothing is guessed and nothing is written: the app
    /// is in R31's read-only mode, and ``ReceptacleCatalogue`` has no chassis
    /// for it.
    case unknown
}

/// How this Mac came to be recognized — UX_SPEC §4.7's "Recognition"
/// paragraph, as a fact the diagnostics can state.
public enum Recognition: String, Sendable, Equatable, CaseIterable, CustomStringConvertible {
    /// The identifier catalogue lists `hw.model`.
    case identifier
    /// The product family macOS publishes for this Mac, together with a
    /// Thunderbolt layout that matches that family's table exactly.
    case familyAndLayout
    /// Neither. The archetype is ``Archetype/unknown``.
    case none

    /// Payload text for a diagnostic or the command-line tool, never interface
    /// copy.
    public var description: String {
        switch self {
        case .identifier: "by identifier"
        case .familyAndLayout: "by product family and layout"
        case .none: "not recognized"
        }
    }
}

/// What this Mac is, in the words the app uses everywhere else.
///
/// The window subtitle in UX_SPEC S0 reads `Studio — Mac Studio (M3 Ultra)`,
/// which is ``marketingName`` and ``chip``.
public struct HardwareModel: Sendable, Equatable {
    /// `hw.model`, for example `Mac15,14`. Empty only if `sysctl` refused.
    public var identifier: String
    /// `Mac Studio`, `Mac mini`, `MacBook Pro`: the catalogue's name for the
    /// identifier, or the product family macOS itself publishes for the Mac
    /// when the catalogue has none, and plain `Mac` only when neither exists
    /// (UX_SPEC §2.1).
    public var marketingName: String
    /// `M3 Ultra`, from `machdep.cpu.brand_string` with the `Apple ` prefix off.
    public var chip: String
    /// The chassis family, or ``Archetype/unknown``.
    public var archetype: Archetype
    /// Which of UX_SPEC §4.7's two rules decided ``archetype``, or neither.
    public var recognition: Recognition

    /// - Parameter recognition: `nil` derives it from the archetype — a known
    ///   archetype was recognized by identifier, an unknown one not at all —
    ///   which is what every fixture built before family-and-layout
    ///   recognition existed means.
    public init(
        identifier: String,
        marketingName: String,
        chip: String,
        archetype: Archetype,
        recognition: Recognition? = nil
    ) {
        self.identifier = identifier
        self.marketingName = marketingName
        self.chip = chip
        self.archetype = archetype
        self.recognition = recognition ?? (archetype == .unknown ? Recognition.none : .identifier)
    }

    /// Reads this Mac's identity. Never fails: an unreadable `sysctl` leaves the
    /// field empty and the archetype ``Archetype/unknown``.
    ///
    /// This is the identifier half of UX_SPEC §4.7's recognition. The other
    /// half, ``recognizing(thunderboltPositions:)``, needs the Thunderbolt
    /// layout, which ``Inventory`` reads; ``Inventory/readModel()`` does both.
    public static func read() -> HardwareModel {
        let identifier = sysctlString("hw.model") ?? ""
        let known = catalog[identifier]
        return HardwareModel(
            identifier: identifier,
            marketingName: known?.marketingName
                ?? productFamily(fromProductName: DeviceTreeProduct.name())
                ?? "Mac",
            chip: chipName(fromBrandString: sysctlString("machdep.cpu.brand_string") ?? ""),
            archetype: known?.archetype ?? .unknown,
            recognition: known == nil ? Recognition.none : .identifier
        )
    }

    /// True when either of §4.7's rules recognized this Mac.
    public var isRecognized: Bool { archetype != .unknown }
}

extension HardwareModel {
    /// One catalogue row: what to call the Mac and how it is shaped.
    struct KnownMac: Sendable, Equatable {
        var marketingName: String
        var archetype: Archetype
    }

    /// Every Mac RDMALink can draw by identifier. Deliberately short: an
    /// identifier that is missing from here is given the family-and-layout
    /// rule below, and a Mac that fails that too degrades to a numbered,
    /// generic presentation rather than to a wrong picture.
    ///
    /// Every identifier is transcribed from Apple's own "Identify your … model"
    /// pages, which list the Model Identifier per machine:
    /// MacBook Pro <https://support.apple.com/en-us/108052> (read 2026-09-20),
    /// Mac Studio <https://support.apple.com/en-us/102231> and
    /// Mac mini <https://support.apple.com/en-us/102852> (read 2026-09-20, and
    /// again 2026-09-25 for the 2026 rows). Where an Identify page gives no
    /// port sentence for a machine, its archetype is taken from Apple's specs
    /// page for that chip — <https://www.apple.com/mac-studio/specs/> and
    /// <https://www.apple.com/mac-mini/specs/>, read 2026-09-25 — never from
    /// the chip's name alone. `Mac15,14` is also verified on this hardware
    /// and `Mac17,7` on the rig's MacBook Pro. A new Mac needs no row to be
    /// recognized — the family-and-layout rule covers it — so a row is only
    /// ever added from those pages, never from a third-party listing.
    static let catalog: [String: KnownMac] = [
        // Mac Studio (2025).
        "Mac15,14": KnownMac(marketingName: "Mac Studio", archetype: .studioSix),   // M3 Ultra
        "Mac16,9": KnownMac(marketingName: "Mac Studio", archetype: .studioFour),   // M4 Max
        // Mac Studio (M5 Max) and (M5 Ultra), 2026. Both: "Four Thunderbolt 5
        // (USB-C) ports" on the back. The front is "Two USB-C ports" on the
        // M5 Max, as on `Mac16,9`, and "Two Thunderbolt 5 ports" on the
        // M5 Ultra, as on `Mac15,14`.
        "Mac17,14": KnownMac(marketingName: "Mac Studio", archetype: .studioFour),  // M5 Max
        "Mac17,15": KnownMac(marketingName: "Mac Studio", archetype: .studioSix),   // M5 Ultra
        // Mac mini (2024) — both share one chassis and one port layout.
        "Mac16,10": KnownMac(marketingName: "Mac mini", archetype: .mini),          // M4
        "Mac16,11": KnownMac(marketingName: "Mac mini", archetype: .mini),          // M4 Pro
        // Mac mini (M5 Pro) and (M6), 2026: the same chassis — three
        // Thunderbolt receptacles on the back, "Two USB-C ports with support
        // for USB 3" on the front. The M5 Pro's back three are Thunderbolt 5.
        "Mac17,16": KnownMac(marketingName: "Mac mini", archetype: .mini),          // M5 Pro
        // The M6's back three are "Three Thunderbolt 4 (USB-C) ports". The
        // chassis is the mini's all the same; whether set-up is offered is not
        // decided here or at run time, but by R23's generation table
        // (App/Presentation/ThunderboltGeneration.swift), keyed on the
        // identifier. `Mac18,5` is in it as Thunderbolt 4, because Apple names
        // one chip per identifier for it, so this Mac opens read-only.
        // `Mac16,10` is not: Apple's 2024 page lists it together with
        // `Mac16,11`, so the M4 mini's generation reads unknown and R23 never
        // shows there.
        "Mac18,5": KnownMac(marketingName: "Mac mini", archetype: .mini),           // M6
        // MacBook Pro (14-inch, 2024) M4; (14-inch, 2024) M4 Pro / M4 Max;
        // (16-inch, 2024) M4 Pro / M4 Max.
        "Mac16,1": KnownMac(marketingName: "MacBook Pro", archetype: .notebook),
        "Mac16,6": KnownMac(marketingName: "MacBook Pro", archetype: .notebook),
        "Mac16,8": KnownMac(marketingName: "MacBook Pro", archetype: .notebook),
        "Mac16,5": KnownMac(marketingName: "MacBook Pro", archetype: .notebook),
        "Mac16,7": KnownMac(marketingName: "MacBook Pro", archetype: .notebook),
        // MacBook Pro (14-inch, M5), 2025.
        "Mac17,2": KnownMac(marketingName: "MacBook Pro", archetype: .notebook),
        // MacBook Pro (14-inch, M5 Pro or M5 Max) and (16-inch, M5 Pro or
        // M5 Max), 2026. `Mac17,7` verified on the rig 2026-09-20:
        // `product-name` "MacBook Pro (14-inch, M5 Max)", `port-location`
        // right, left-back, left-front — recognized by family and layout
        // before this row existed.
        "Mac17,7": KnownMac(marketingName: "MacBook Pro", archetype: .notebook),
        "Mac17,9": KnownMac(marketingName: "MacBook Pro", archetype: .notebook),
        "Mac17,6": KnownMac(marketingName: "MacBook Pro", archetype: .notebook),
        "Mac17,8": KnownMac(marketingName: "MacBook Pro", archetype: .notebook),
    ]

    /// The chassis the identifier catalogue lists for `identifier`, or nil
    /// when it lists none. It never recognizes *this* Mac — ``read()`` and
    /// the family-and-layout rule do that — and exists so the app can draw a
    /// Mac it is only told about: UX_SPEC §S8's other Mac, drawn as a current
    /// model of the family the user picked, by that model's identifier.
    public static func archetype(forIdentifier identifier: String) -> Archetype? {
        catalog[identifier]?.archetype
    }

    /// `Apple M3 Ultra` → `M3 Ultra`. Anything else is passed through trimmed,
    /// because a chip name nobody recognizes is still better than none.
    static func chipName(fromBrandString brand: String) -> String {
        let trimmed = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("Apple ") else { return trimmed }
        return String(trimmed.dropFirst("Apple ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `Mac Studio (2025)` → `Mac Studio`: the device tree's `product-name`
    /// with its parenthesised year or size taken off. `nil` when there is no
    /// name, or nothing before the parenthesis — a family the app cannot
    /// name is not called `(2025)`.
    static func productFamily(fromProductName name: String?) -> String? {
        guard let name else { return nil }
        let family = name.prefix { $0 != "(" }.trimmingCharacters(in: .whitespacesAndNewlines)
        return family.isEmpty ? nil : family
    }
}

// MARK: - Recognition by product family and layout

extension HardwareModel {
    /// The archetypes each product family can be, in UX_SPEC §4.7's table.
    /// Two Mac Studios share a family and differ only in whether the front
    /// receptacles carry Thunderbolt, which is exactly what the layout
    /// decides.
    static let familyArchetypes: [String: [Archetype]] = [
        "Mac Studio": [.studioFour, .studioSix],
        "Mac mini": [.mini],
        "MacBook Pro": [.notebook],
    ]

    /// UX_SPEC §4.7's second rule: a Mac the catalogue does not list is
    /// recognized when the product family macOS publishes for it and the
    /// Thunderbolt layout it reports agree on one archetype — "every reported
    /// position has a name in the table, no two share one, and no table
    /// position is missing".
    ///
    /// - Parameter thunderboltPositions: one entry per Thunderbolt receptacle
    ///   macOS reported, `nil` where it published no position or one the app
    ///   could not parse. A single nil is enough to refuse: a layout with a
    ///   hole in it is not a match, and "nothing is ever inferred from the
    ///   chip or from the port count alone".
    ///
    /// A model already recognized by identifier is returned as it is; the
    /// layout never overrules the catalogue.
    func recognizing(thunderboltPositions positions: [PortPosition?]) -> HardwareModel {
        guard archetype == .unknown,
              let candidates = Self.familyArchetypes[marketingName] else { return self }
        for candidate in candidates
        where Self.layoutNames(positions, archetype: candidate) == Self.tableNames(candidate) {
            var recognized = self
            recognized.archetype = candidate
            recognized.recognition = .familyAndLayout
            return recognized
        }
        return self
    }

    /// The names the reported positions take in `archetype`'s table, or nil
    /// when any position is absent, unnamed there, or named twice.
    private static func layoutNames(_ positions: [PortPosition?], archetype: Archetype) -> Set<String>? {
        var names: Set<String> = []
        for position in positions {
            guard let name = position?.name(archetype: archetype), names.insert(name).inserted else {
                return nil
            }
        }
        return names
    }

    /// Every Thunderbolt receptacle name in `archetype`'s table — the
    /// catalogue's own rows, so the two halves of §4.7 meet on one list. The
    /// candidates come from ``familyArchetypes`` and always have a chassis;
    /// an empty set is what a layout can never match.
    private static func tableNames(_ archetype: Archetype) -> Set<String> {
        Set(
            (ReceptacleCatalogue.chassis(for: archetype)?.receptacles ?? [])
                .filter { $0.kind == .thunderbolt }
                .compactMap(\.positionName)
        )
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

/// The device tree's `product` node: what macOS itself calls this Mac.
///
/// Verified on Mac15,14 (2026-09-20): `IODeviceTree:/product` carries
/// `product-name` and `product-description` (`Mac Studio (2025)`),
/// `product-soc-name` (`Apple M3 Ultra`), `builtin-battery` and
/// `fdr-product-type` (`Mac15,14`, the same as `hw.model`), each a
/// NUL-terminated C string in `Data`. Undocumented, so it is enrichment under
/// `docs/ARCHITECTURE.md` rule 5: absent, the name is nil and the model is
/// called `Mac`.
enum DeviceTreeProduct {
    static let path = "IODeviceTree:/product"
    static let nameKey = "product-name"

    /// `Mac Studio (2025)`, or nil when this Mac does not say.
    static func name() -> String? {
        IORegistry.withEntry(atPath: path) { IORegistry.string($0, nameKey) }
    }
}
