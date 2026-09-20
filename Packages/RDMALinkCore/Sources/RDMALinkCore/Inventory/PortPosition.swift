/// The lateral half of an `IODeviceTree` `port-location` value.
///
/// The tokens are the machine's own words (`back-left-middle`), not the app's.
/// Anything not listed here parses to nil, so an unfamiliar spelling produces a
/// numbered port name rather than a wrong physical one.
enum PortSlot: Sendable, Equatable {
    case left, leftMiddle, middle, rightMiddle, right
    /// Notebook side faces, where the qualifier is fore-and-aft.
    case rear, front
    /// A face with only one receptacle, which needs no qualifier.
    case unspecified
}

/// Where a receptacle sits on the chassis, as far as this Mac will say.
struct PortPosition: Sendable, Equatable {
    var face: PortFace
    var slot: PortSlot

    /// Parses a `port-location` value such as `back-left-middle`.
    ///
    /// Verified on Mac15,14, which publishes `back-left`, `back-left-middle`,
    /// `back-right-middle`, `back-right`, `front-left` and `front-right`.
    /// Other spellings are accepted where they are unambiguous; everything else
    /// is nil.
    static func parse(_ location: String) -> PortPosition? {
        let tokens = location.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
            .map(String.init)
        guard let head = tokens.first, let face = face(head) else { return nil }
        guard let slot = slot(Array(tokens.dropFirst())) else { return nil }
        return PortPosition(face: face, slot: slot)
    }

    private static func face(_ token: String) -> PortFace? {
        switch token {
        case "back", "rear": .back
        case "front": .front
        case "left": .left
        case "right": .right
        default: nil
        }
    }

    private static func slot(_ tokens: [String]) -> PortSlot? {
        switch tokens {
        case []: .unspecified
        case ["left"]: .left
        case ["right"]: .right
        case ["middle"], ["center"], ["centre"]: .middle
        case ["left", "middle"], ["middle", "left"]: .leftMiddle
        case ["right", "middle"], ["middle", "right"]: .rightMiddle
        case ["rear"], ["back"]: .rear
        case ["front"]: .front
        default: nil
        }
    }
}

extension PortPosition {
    /// The name from the UX_SPEC §4.7 table, or nil when this archetype has no
    /// name for this position.
    ///
    /// An unrecognized Mac never gets a physical name: the spec numbers its
    /// ports and promotes Identify instead, which is honest, and a wrong
    /// "Back, far left" would send someone to the wrong cable.
    func name(archetype: Archetype) -> String? {
        switch (archetype, face, slot) {
        case (.studioFour, .back, .left), (.studioSix, .back, .left):
            "Back, far left"
        case (.studioFour, .back, .leftMiddle), (.studioSix, .back, .leftMiddle):
            "Back, middle left"
        case (.studioFour, .back, .rightMiddle), (.studioSix, .back, .rightMiddle):
            "Back, middle right"
        case (.studioFour, .back, .right), (.studioSix, .back, .right):
            "Back, far right"
        case (.studioFour, .front, .left), (.studioSix, .front, .left), (.mini, .front, .left):
            "Front, left"
        case (.studioFour, .front, .right), (.studioSix, .front, .right), (.mini, .front, .right):
            "Front, right"
        case (.mini, .back, .left):
            "Back, left"
        case (.mini, .back, .middle):
            "Back, middle"
        case (.mini, .back, .right):
            "Back, right"
        case (.notebook, .left, .rear):
            "Left side, rear"
        case (.notebook, .left, .front):
            "Left side, front"
        case (.notebook, .right, _):
            "Right side"
        default:
            nil
        }
    }
}
