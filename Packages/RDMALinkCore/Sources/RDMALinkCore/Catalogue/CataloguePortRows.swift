extension ReceptacleCatalogue {

    /// The port list UX_SPEC §S1 asks for: every receptacle on the chassis in
    /// physical order, the real ones macOS reported interleaved with the
    /// USB-only ones only the catalogue knows about.
    ///
    /// The join is on the position name, because that is the one fact both
    /// sides produce from the same table in UX_SPEC §4.7 — the hardware read
    /// derives it from `port-location`, the catalogue carries it verbatim.
    /// Matching on it also means a real port always wins over a catalogue row
    /// for the same receptacle: the app shows what it observed, and invents a
    /// row only where it observed nothing and the chassis says there is
    /// something there.
    ///
    /// A Thunderbolt receptacle in the catalogue that macOS did not report is
    /// simply absent from the list. The app does not claim a port exists
    /// because the chassis usually has one.
    ///
    /// - Parameter realPorts: what ``PortInventory`` read, already in physical
    ///   order. Any port that does not match the catalogue keeps that order
    ///   and follows the ones that do — the same rule
    ///   ``Inventory/sortedPhysically(_:enrichment:)`` uses for a receptacle
    ///   this Mac would not place.
    /// - Parameter cabledPositions: the USB-only receptacles ``ChassisProbe``
    ///   found something plugged into. They have no receptacle index and no
    ///   network interface, so this is the only thing anywhere that can say a
    ///   cable is in one — which is what UX_SPEC §4.5's plug stub and §S1's
    ///   "There's a cable in a front port" row are waiting on.
    static func portRows(
        realPorts: [ThunderboltPort],
        archetype: Archetype,
        cabledPositions: Set<PortPosition> = []
    ) -> [ThunderboltPort] {
        // An unrecognized Mac has no chassis and gets no catalogue rows. Its
        // ports are the ones macOS reported, numbered the way macOS reports
        // them (§4.7, §6.2 R31).
        guard let chassis = chassis(for: archetype) else { return realPorts }
        let cabledNames = Set(cabledPositions.compactMap { $0.name(archetype: archetype) })
        var remaining = realPorts
        var rows: [ThunderboltPort] = []
        var placedSomething = false
        for receptacle in chassis.receptacles {
            guard let name = receptacle.positionName else { continue }
            if let match = remaining.firstIndex(where: { $0.positionName == name }) {
                rows.append(remaining.remove(at: match))
                placedSomething = true
            } else if receptacle.kind == .usbC {
                rows.append(
                    usbOnlyRow(receptacle, positionName: name, hasCable: cabledNames.contains(name))
                )
            }
        }
        // Not one receptacle the catalogue names was there. This Mac published
        // no positions at all, so its ports are numbered and nothing knows
        // where the USB-only receptacles sit among them — putting them at the
        // top of the list would be a guess. The read stands as it is.
        guard placedSomething else { return realPorts }
        return rows + remaining
    }

    /// A USB-only receptacle as a port-list row.
    ///
    /// It has no BSD name because it has no network interface — there is no
    /// Thunderbolt-IP port behind it to have one — so nothing that keys on
    /// `enN` can ever reach it, which is the point: UX_SPEC §4.5 makes these
    /// rows unselectable, ringless and dimmed.
    ///
    /// ``ThunderboltPort/link`` is ``LinkState/device`` when ``ChassisProbe``
    /// saw `ConnectionActive` on the position node behind this receptacle, and
    /// ``LinkState/empty`` otherwise. It is never ``LinkState/macLinked``:
    /// there is no Thunderbolt-IP port here, so the app cannot know and does
    /// not guess. That one bit is what UX_SPEC §4.5's plug stub and §S1's
    /// "There's a cable in a front port" row run on.
    private static func usbOnlyRow(
        _ receptacle: ChassisFeature,
        positionName: String,
        hasCable: Bool
    ) -> ThunderboltPort {
        let index = receptacle.index ?? 0
        return ThunderboltPort(
            id: "usb.\(receptacle.face.rawValue).\(index)",
            receptacle: index,
            bsdName: "",
            face: receptacle.face,
            positionName: positionName,
            isThunderbolt: false,
            link: hasCable ? .device : .empty
        )
    }
}
