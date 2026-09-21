/// What each chassis RDMALink can draw looks like, and where its receptacles
/// are.
///
/// Every number here is transcribed from the three.js prototype's `MODELS`
/// catalogue (`docs/prototype/stage.html`), which is the geometry reference
/// for the stage, and every receptacle name is verbatim from UX_SPEC §4.7.
/// Pure data and pure functions: nothing here reads hardware.
///
/// ``Archetype/studioFour`` is the one chassis the prototype does not carry.
/// It is the same box as ``Archetype/studioSix`` with the two front
/// receptacles carrying USB only, which is exactly what UX_SPEC §4.7 says
/// about it, so the two share one transcription.
public enum ReceptacleCatalogue {

    /// The chassis for an archetype, or `nil` for ``Archetype/unknown``.
    ///
    /// There is no stand-in (UX_SPEC §3.4, §6.2 R31): a Mac neither rule in
    /// §4.7 recognizes gets no chassis at all, because "a plain box would
    /// still be a picture of a Mac the app does not know, and every hole on
    /// it a claim." The stage draws R31's block in its place.
    public static func chassis(for archetype: Archetype) -> Chassis? {
        switch archetype {
        case .studioFour: studioFour
        case .studioSix: studioSix
        case .mini: mini
        case .notebook: notebook
        case .unknown: nil
        }
    }

    // MARK: - Mac Studio

    /// Mac Studio, four Thunderbolt receptacles on the back and two USB-only
    /// ones on the front (M4 Max / M5 Max).
    static let studioFour = studio(archetype: .studioFour, frontKind: .usbC)

    /// Mac Studio, the same back four plus two more Thunderbolt receptacles on
    /// the front (M3 Ultra / M5 Ultra). The prototype's `studio`.
    static let studioSix = studio(archetype: .studioSix, frontKind: .thunderbolt)

    /// The one Mac Studio box. The archetypes differ only in what the two
    /// front receptacles carry.
    private static func studio(archetype: Archetype, frontKind: FeatureKind) -> Chassis {
        Chassis.make(
            archetype: archetype,
            width: 19.7, height: 9.5, depth: 19.7,
            cornerRadius: 2.4, bevel: 0.22, baseBand: 1.0,
            verticalReceptacles: true,
            resting: RestingPose(yaw: .pi - 0.55, pitch: 0.30, radiusScale: 1.0),
            // The prototype's `grille`: the whole back above the port row,
            // from corner to corner. The other chassis carry `grille: null`.
            grille: Grille(face: .back, u0: 0.06, u1: 0.94, v0: 0.40, v1: 0.94),
            rows: [
                .init(.thunderbolt, .back, u: 0.157, v: 0.20, "Back, far left"),
                .init(.thunderbolt, .back, u: 0.207, v: 0.20, "Back, middle left"),
                .init(.thunderbolt, .back, u: 0.258, v: 0.20, "Back, middle right"),
                .init(.thunderbolt, .back, u: 0.309, v: 0.20, "Back, far right"),
                .init(.ethernet, .back, u: 0.38, v: 0.20),
                .init(.power, .back, u: 0.508, v: 0.20),
                .init(.usbA, .back, u: 0.616, v: 0.20),
                .init(.usbA, .back, u: 0.68, v: 0.20),
                .init(.hdmi, .back, u: 0.77, v: 0.20),
                .init(.headphones, .back, u: 0.85, v: 0.20),
                .init(.powerButton, .back, u: 0.92, v: 0.20),
                .init(frontKind, .front, u: 0.165, v: 0.20, "Front, left"),
                .init(frontKind, .front, u: 0.24, v: 0.20, "Front, right"),
                .init(.sdCard, .front, u: 0.38, v: 0.20),
                .init(.indicator, .front, u: 0.85, v: 0.20),
            ]
        )
    }

    // MARK: - Mac mini

    /// Mac mini: three Thunderbolt receptacles on the back, two USB-only ones
    /// on the front.
    static let mini = Chassis.make(
        archetype: .mini,
        width: 12.7, height: 5.0, depth: 12.7,
        cornerRadius: 1.4, bevel: 0.16, baseBand: 0.7,
        verticalReceptacles: true,
        resting: RestingPose(yaw: .pi - 0.55, pitch: 0.34, radiusScale: 1.0),
        rows: [
            .init(.powerEight, .back, u: 0.246, v: 0.35),
            .init(.ethernet, .back, u: 0.418, v: 0.35),
            .init(.hdmi, .back, u: 0.57, v: 0.35),
            .init(.thunderbolt, .back, u: 0.684, v: 0.35, "Back, left"),
            .init(.thunderbolt, .back, u: 0.754, v: 0.35, "Back, middle"),
            .init(.thunderbolt, .back, u: 0.822, v: 0.35, "Back, right"),
            .init(.usbC, .front, u: 0.206, v: 0.35, "Front, left"),
            .init(.usbC, .front, u: 0.325, v: 0.35, "Front, right"),
            .init(.indicator, .front, u: 0.69, v: 0.35),
            .init(.headphones, .front, u: 0.79, v: 0.35),
        ]
    )

    // MARK: - MacBook Pro

    /// MacBook Pro 14/16: two receptacles on the left side, one on the right.
    /// On a side face `u` ascends towards the front of the machine, which is
    /// why `Left side, rear` comes first.
    static let notebook = Chassis.make(
        archetype: .notebook,
        width: 31.26, height: 1.55, depth: 22.12,
        cornerRadius: 1.0, bevel: 0.22, baseBand: 0,
        verticalReceptacles: false,
        resting: RestingPose(yaw: -.pi / 2 + 0.75, pitch: 0.32, radiusScale: 1.05),
        lid: Lid(depth: 22.0, thickness: 0.42, openAngle: 104),
        rows: [
            .init(.magSafe, .left, u: 0.154, v: 0.5),
            .init(.thunderbolt, .left, u: 0.228, v: 0.5, "Left side, rear"),
            .init(.thunderbolt, .left, u: 0.303, v: 0.5, "Left side, front"),
            .init(.headphones, .left, u: 0.339, v: 0.5),
            .init(.sdCard, .right, u: 0.675, v: 0.5),
            .init(.thunderbolt, .right, u: 0.787, v: 0.5, "Right side"),
            .init(.hdmi, .right, u: 0.869, v: 0.5),
        ]
    )
}
