/// One thing on the outside of a chassis: a receptacle, a socket, a button or
/// a light.
///
/// The cases are the prototype's own kinds (`docs/prototype/stage.html`,
/// `MODELS`), which is the geometry reference for the stage. Only
/// ``thunderbolt`` and ``usbC`` are receptacles the user can point at; the rest
/// exist so the model looks like the Mac on the desk and for no other reason.
public enum FeatureKind: Sendable, Equatable, CaseIterable {
    /// A Thunderbolt receptacle. Prototype `tb`.
    case thunderbolt
    /// A USB-C receptacle that carries USB only, never Thunderbolt.
    /// Prototype `usb`. UX_SPEC §4.5: never a ring, never selectable.
    case usbC
    /// USB-A. Prototype `usba`.
    case usbA
    case hdmi
    /// Ethernet. Prototype `eth`.
    case ethernet
    /// The Mac Studio's inset power socket. Prototype `power`.
    case power
    /// The Mac mini's figure-of-eight power socket. Prototype `power8`.
    case powerEight
    /// The headphone jack. Prototype `jack`.
    case headphones
    /// The SDXC slot. Prototype `sd`.
    case sdCard
    /// MagSafe. Prototype `magsafe`.
    case magSafe
    /// The Mac mini's power button. Prototype `button`.
    case powerButton
    /// A status light. Prototype `led`.
    case indicator

    /// The opening's size in centimetres: what the stage cuts into the face.
    public struct Opening: Sendable, Equatable {
        public var width: Double
        public var height: Double
        /// The corner radius of the opening's outline. It is what makes a
        /// USB-C receptacle a stadium and the Mac Studio's power socket a
        /// circle, and it is the prototype's third `PORT_DIMS` number: that
        /// table feeds `roundedRect(pw, ph, r)`, and the extrusion depth there
        /// is a separate constant. How deep the recess goes is the renderer's
        /// business, not the catalogue's.
        public var cornerRadius: Double

        public init(width: Double, height: Double, cornerRadius: Double) {
            self.width = width
            self.height = height
            self.cornerRadius = cornerRadius
        }

        /// The same opening turned a quarter turn. The radius is a radius, so
        /// only the two extents swap.
        public var rotated: Opening {
            Opening(width: height, height: width, cornerRadius: cornerRadius)
        }
    }

    /// Transcribed from the prototype's `PORT_DIMS`, in centimetres.
    public var opening: Opening {
        switch self {
        case .thunderbolt: Opening(width: 0.95, height: 0.35, cornerRadius: 0.17)
        case .usbC: Opening(width: 0.95, height: 0.35, cornerRadius: 0.08)
        case .usbA: Opening(width: 1.3, height: 0.6, cornerRadius: 0.12)
        case .hdmi: Opening(width: 1.5, height: 0.55, cornerRadius: 0.15)
        case .ethernet: Opening(width: 1.25, height: 1.35, cornerRadius: 0.2)
        case .power: Opening(width: 1.9, height: 1.9, cornerRadius: 0.95)
        case .powerEight: Opening(width: 1.9, height: 1.1, cornerRadius: 0.5)
        case .headphones: Opening(width: 0.55, height: 0.55, cornerRadius: 0.27)
        case .sdCard: Opening(width: 2.6, height: 0.22, cornerRadius: 0.1)
        case .magSafe: Opening(width: 1.3, height: 0.42, cornerRadius: 0.2)
        case .powerButton: Opening(width: 1.1, height: 1.1, cornerRadius: 0.55)
        case .indicator: Opening(width: 0.28, height: 0.28, cornerRadius: 0.14)
        }
    }

    /// True for the two kinds the port list has a row for and the stage lets
    /// the pointer reach: Thunderbolt and USB-only.
    public var isReceptacle: Bool { self == .thunderbolt || self == .usbC }
}

/// Where a feature is on the chassis, and — for the two receptacle kinds —
/// which port in the spec's order it is.
///
/// `u` and `v` are the prototype's face coordinates: `u` runs 0…1 across the
/// face from the viewer's left as they look at that face, `v` runs 0…1 up it.
/// They are fractions of the face, not centimetres, so one table serves every
/// size of the same chassis.
public struct ChassisFeature: Sendable, Equatable, Identifiable {
    /// Stable within a chassis: the face and the feature's rank along it.
    public var id: String
    public var kind: FeatureKind
    public var face: PortFace
    public var u: Double
    public var v: Double
    /// The opening is turned a quarter turn — what the prototype's `dimsFor`
    /// does to `tb` and `usb` on a `vertical` model.
    public var isVertical: Bool
    /// Receptacles only: the rank among the receptacles on this face, 0-based,
    /// in the viewer's left-to-right order. `nil` for everything else.
    public var index: Int?
    /// Receptacles only: the position name from UX_SPEC §4.7, verbatim.
    public var positionName: String?

    init(
        id: String,
        kind: FeatureKind,
        face: PortFace,
        u: Double,
        v: Double,
        isVertical: Bool,
        index: Int? = nil,
        positionName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.face = face
        self.u = u
        self.v = v
        self.isVertical = isVertical
        self.index = index
        self.positionName = positionName
    }

    /// The opening this feature cuts, already turned if it is vertical.
    public var opening: FeatureKind.Opening {
        isVertical ? kind.opening.rotated : kind.opening
    }
}

/// A notebook's lid. Absent on every other chassis, which is also how the
/// stage tells the two shapes apart.
public struct Lid: Sendable, Equatable {
    /// How far the lid reaches from the hinge, in centimetres.
    public var depth: Double
    /// Its thickness, in centimetres.
    public var thickness: Double
    /// How far it stands open at rest, in degrees.
    public var openAngle: Double

    public init(depth: Double, thickness: Double, openAngle: Double) {
        self.depth = depth
        self.thickness = thickness
        self.openAngle = openAngle
    }
}

/// Where the camera sits when nothing has asked it to move: the resting
/// three-quarter pose of UX_SPEC §3.4, transcribed from the prototype's `rest`.
///
/// Spherical, around the chassis: ``yaw`` and ``pitch`` in radians, and
/// ``radiusScale`` multiplying whatever distance the renderer needs to fit the
/// machine — a notebook sits a shade further back than a box.
public struct RestingPose: Sendable, Equatable {
    public var yaw: Double
    public var pitch: Double
    public var radiusScale: Double

    public init(yaw: Double, pitch: Double, radiusScale: Double) {
        self.yaw = yaw
        self.pitch = pitch
        self.radiusScale = radiusScale
    }
}

/// One chassis: its box, and everything on the outside of it.
///
/// Pure data. Centimetres throughout, because that is what the product
/// dimensions are published in and a scale factor belongs to the renderer.
public struct Chassis: Sendable, Equatable {
    public var archetype: Archetype
    /// Left to right, in centimetres.
    public var width: Double
    /// Bottom to top.
    public var height: Double
    /// Front to back.
    public var depth: Double
    /// The vertical corner radius of the footprint.
    public var cornerRadius: Double
    /// How far the top and bottom edges are bevelled.
    public var bevel: Double
    /// The unbroken band along the bottom, in centimetres. 0 where there is
    /// none.
    public var baseBand: Double
    /// The lid, on a notebook only.
    public var lid: Lid?
    /// Where the camera rests on this chassis.
    public var resting: RestingPose
    /// Every feature, back face first, and left to right along each face.
    public var features: [ChassisFeature]

    /// The faces that carry something, in the order UX_SPEC §4.7 lists them:
    /// back then front, left then right. This is what the face selector shows.
    public var faces: [PortFace] {
        var seen: [PortFace] = []
        for feature in features where !seen.contains(feature.face) {
            seen.append(feature.face)
        }
        return seen
    }

    /// Every Thunderbolt and USB-only receptacle, in the order the port list
    /// draws them: the Back group, then Front, then Left and Right, each left
    /// to right.
    public var receptacles: [ChassisFeature] {
        features.filter(\.kind.isReceptacle)
    }

    /// The receptacle at a physical index on a face, or `nil` when this chassis
    /// has no such receptacle.
    public func receptacle(face: PortFace, index: Int) -> ChassisFeature? {
        features.first { $0.face == face && $0.index == index }
    }

    /// Everything on one face, left to right.
    public func features(on face: PortFace) -> [ChassisFeature] {
        features.filter { $0.face == face }
    }
}

extension Chassis {
    /// One row of the catalogue tables, before ordering.
    struct Row {
        var kind: FeatureKind
        var face: PortFace
        var u: Double
        var v: Double
        /// The UX_SPEC §4.7 name, on receptacles only.
        var name: String?

        init(_ kind: FeatureKind, _ face: PortFace, u: Double, v: Double, _ name: String? = nil) {
            self.kind = kind
            self.face = face
            self.u = u
            self.v = v
            self.name = name
        }
    }

    /// Builds a chassis from a table, putting the rows in physical order and
    /// numbering the receptacles as it goes.
    ///
    /// The ordering happens here, once, so the tables can be written in
    /// whatever order reads best and no caller has to know that `u` ascends
    /// from the viewer's left.
    ///
    /// - Parameter verticalReceptacles: the prototype's model-level `vertical`
    ///   flag, which turns `tb` and `usb` openings a quarter turn and leaves
    ///   every other kind alone.
    static func make(
        archetype: Archetype,
        width: Double,
        height: Double,
        depth: Double,
        cornerRadius: Double,
        bevel: Double,
        baseBand: Double,
        verticalReceptacles: Bool,
        resting: RestingPose,
        lid: Lid? = nil,
        rows: [Row]
    ) -> Chassis {
        let ordered = rows.sorted { left, right in
            left.face.physicalRank == right.face.physicalRank
                ? left.u < right.u
                : left.face.physicalRank < right.face.physicalRank
        }
        var rankOnFace: [PortFace: Int] = [:]
        var receptacleOnFace: [PortFace: Int] = [:]
        let features = ordered.map { row -> ChassisFeature in
            let rank = rankOnFace[row.face, default: 0]
            rankOnFace[row.face] = rank + 1
            var index: Int?
            if row.kind.isReceptacle {
                index = receptacleOnFace[row.face, default: 0]
                receptacleOnFace[row.face] = (index ?? 0) + 1
            }
            return ChassisFeature(
                id: "\(row.face.rawValue).\(rank)",
                kind: row.kind,
                face: row.face,
                u: row.u,
                v: row.v,
                isVertical: verticalReceptacles && row.kind.isReceptacle,
                index: index,
                positionName: row.name
            )
        }
        return Chassis(
            archetype: archetype,
            width: width,
            height: height,
            depth: depth,
            cornerRadius: cornerRadius,
            bevel: bevel,
            baseBand: baseBand,
            lid: lid,
            resting: resting,
            features: features
        )
    }
}
