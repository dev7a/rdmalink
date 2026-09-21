//
//  StageMesh.swift
//
//  The geometry and textures the stage generates at runtime. Nothing is loaded
//  from an asset: a USDZ of a Mac is trade dress, and a procedural rounded box
//  with the right holes in it is not (UX_SPEC §3.4).
//

import CoreGraphics
import Foundation
import Metal
import RDMALinkCore
import RealityKit
import simd

enum StageMesh {
    /// Catalogue numbers are centimetres; RealityKit is metres.
    static func metres(_ centimetres: Double) -> Float { Float(centimetres * 0.01) }

    // MARK: - Extrusions

    /// A rounded-rectangle prism: the profile `width × height` with corner
    /// radius `cornerRadius`, extruded `depth` along `-z` with its front face
    /// at `z = 0`, and `bevel` rounding the two end edges.
    ///
    /// This is `docs/prototype/stage.html`'s `slab()`. The outline is shrunk by
    /// the bevel and the bevel puts it back, so the side band lands exactly at
    /// ±`width`/2 and ±`height`/2 and **the face stays flat for its whole
    /// extent**.
    ///
    /// `MeshResource.generateBox(cornerRadius:)` cannot do this, twice over. It
    /// fillets all twelve edges by one radius, which turns a 9.5 cm Mac Studio
    /// carrying a 2.4 cm plan corner into a bar of soap and pulls the face out
    /// from under every receptacle placed on it; and it clamps that radius to
    /// half the *smallest* dimension, so a 0.16 cm-deep opening could never be
    /// the circle the catalogue asks for. A profile extruded here is clamped
    /// only by its own two in-plane extents, which is the correct clamp.
    @MainActor
    static func prism(
        width: Double, height: Double, cornerRadius: Double, depth: Double,
        bevel: Double = 0, cornerSegments: Int = 8, bevelSegments: Int = 4
    ) throws -> MeshResource {
        let depth = max(depth, 0.0001)
        let bevel = max(min(bevel, min(depth, min(width, height)) / 2 - 0.0001), 0)
        let path = StageMath.roundedRectPath(
            width: width - 2 * bevel, height: height - 2 * bevel,
            cornerRadius: max(cornerRadius - bevel, 0), cornerSegments: cornerSegments
        )
        // `roundedRectPath` closes the loop by repeating its first point.
        let loop = Array(path.dropLast())
        guard loop.count >= 3, let perimeter = path.last?.distance, perimeter > 0 else {
            throw StageMeshError.degenerateRing
        }

        // Each ring is an outward offset from the shrunk profile, a distance
        // back from the front face, and the angle its normals are tilted by.
        var rings: [(offset: Double, back: Double, tilt: Double)] = []
        if bevel > 0 {
            let steps = max(bevelSegments, 1)
            for step in 0...steps {
                let angle = -Double.pi / 2 * (1 - Double(step) / Double(steps))
                rings.append((bevel * cos(angle), bevel * (1 + sin(angle)), angle))
            }
            for step in 0...steps {
                let angle = Double.pi / 2 * Double(step) / Double(steps)
                rings.append((bevel * cos(angle), depth - bevel + bevel * sin(angle), angle))
            }
        } else {
            rings = [(0, 0, 0), (0, depth, 0)]
        }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for ring in rings {
            let tilt = SIMD2(cos(ring.tilt), sin(ring.tilt))
            for sample in loop {
                let planar = sample.point + sample.normal * ring.offset
                positions.append(
                    SIMD3(metres(planar.x), metres(planar.y), metres(-ring.back))
                )
                normals.append(
                    simd_normalize(
                        SIMD3(
                            Float(sample.normal.x * tilt.x),
                            Float(sample.normal.y * tilt.x),
                            Float(-tilt.y)
                        )
                    )
                )
                coordinates.append(
                    SIMD2(Float(sample.distance / perimeter), Float(ring.back / depth))
                )
            }
        }

        let ringStride = UInt32(loop.count)
        for level in 0..<(rings.count - 1) {
            let near = UInt32(level) * ringStride
            let far = UInt32(level + 1) * ringStride
            for index in 0..<loop.count {
                let next = UInt32((index + 1) % loop.count)
                let a = near + UInt32(index), b = near + next
                let d = far + UInt32(index), c = far + next
                indices.append(contentsOf: [a, d, c, a, c, b])
            }
        }

        // The two flat caps, wound so the front one faces `+z`.
        for (back, facing) in [(0.0, Float(1)), (depth, Float(-1))] {
            let centre = UInt32(positions.count)
            positions.append(SIMD3(0, 0, metres(-back)))
            normals.append(SIMD3(0, 0, facing))
            coordinates.append(SIMD2(0.5, 0.5))
            let base = UInt32(positions.count)
            for sample in loop {
                positions.append(
                    SIMD3(metres(sample.point.x), metres(sample.point.y), metres(-back))
                )
                normals.append(SIMD3(0, 0, facing))
                coordinates.append(SIMD2(Float(sample.distance / perimeter), 0))
            }
            for index in 0..<loop.count {
                let next = UInt32((index + 1) % loop.count)
                indices.append(
                    contentsOf: facing > 0
                        ? [centre, base + UInt32(index), base + next]
                        : [centre, base + next, base + UInt32(index)]
                )
            }
        }

        var descriptor = MeshDescriptor(name: "prism")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(coordinates)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    /// The quarter turn that stands a ``prism`` on end: its `+z` becomes `+y`,
    /// so a footprint extruded along `-z` rises out of the ground plane.
    static let standing = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))

    // MARK: - Ring tracks

    /// One ring's shape, so the identical tracks on a chassis's identical
    /// receptacles are generated once and shared.
    ///
    /// `MeshResource` is a value-semantics handle onto a resource the renderer
    /// owns, so handing the same one to twenty entities is what it is for. A
    /// `studioSix` asks for 114 ring and thread meshes and there are 19
    /// distinct ones; an appearance change replays the whole set, which is a
    /// visible hitch without this.
    private struct RingKey: Hashable {
        var width: Double
        var height: Double
        var cornerRadius: Double
        var thickness: Double
        var pattern: StageMath.RingPattern
    }

    @MainActor private static var rings: [RingKey: MeshResource] = [:]
    @MainActor private static var threadMesh: MeshResource?
    @MainActor private static var threadFadeRamp: TextureResource?
    @MainActor private static var grilleTile: TextureResource?

    /// A flat rounded-rectangle outline in the XY plane, facing `+z`.
    ///
    /// Every state on the model is a distinct ring **geometry** (§4.6), so the
    /// pattern — solid, four arcs with four gaps, or dashed — is the signal,
    /// and the material only decides whether it is `.secondary` or accent.
    @MainActor
    static func ring(
        width: Double, height: Double, cornerRadius: Double, thickness: Double,
        pattern: StageMath.RingPattern
    ) throws -> MeshResource {
        let key = RingKey(
            width: width, height: height, cornerRadius: cornerRadius,
            thickness: thickness, pattern: pattern
        )
        if let cached = rings[key] { return cached }
        let mesh = try makeRing(
            width: width, height: height, cornerRadius: cornerRadius,
            thickness: thickness, pattern: pattern
        )
        rings[key] = mesh
        return mesh
    }

    @MainActor
    private static func makeRing(
        width: Double, height: Double, cornerRadius: Double, thickness: Double,
        pattern: StageMath.RingPattern
    ) throws -> MeshResource {
        let path = StageMath.roundedRectPath(
            width: width, height: height, cornerRadius: cornerRadius, cornerSegments: 8
        )
        guard let perimeter = path.last?.distance, perimeter > 0 else {
            throw StageMeshError.degenerateRing
        }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        let half = thickness / 2

        for span in StageMath.spans(for: pattern) {
            let start = span.start * perimeter
            let end = min(span.end, 1.0) * perimeter
            let length = end - start
            guard length > 0 else { continue }
            let steps = max(Int((length / perimeter) * Double(path.count) * 1.5), 2)
            let base = UInt32(positions.count)

            for step in 0...steps {
                let sample = StageMath.sample(
                    path, at: start + length * Double(step) / Double(steps)
                )
                let inner = sample.point - sample.normal * half
                let outer = sample.point + sample.normal * half
                positions.append(SIMD3(metres(inner.x), metres(inner.y), 0))
                positions.append(SIMD3(metres(outer.x), metres(outer.y), 0))
                normals.append(SIMD3(0, 0, 1))
                normals.append(SIMD3(0, 0, 1))
                let u = Float(step) / Float(steps)
                coordinates.append(SIMD2(u, 0))
                coordinates.append(SIMD2(u, 1))
            }
            for step in 0..<steps {
                let inner = base + UInt32(step * 2)
                // Counter-clockwise seen from +z: the ring faces the viewer.
                indices.append(contentsOf: [
                    inner, inner + 1, inner + 3, inner, inner + 3, inner + 2,
                ])
            }
        }

        guard !indices.isEmpty else { throw StageMeshError.degenerateRing }
        var descriptor = MeshDescriptor(name: "ring")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(coordinates)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    // MARK: - The bridge ribbon

    /// One segment of UX_SPEC §4.4's ribbon: a flat quad from `from` to `to`,
    /// lying **against the chassis surface** rather than standing on edge.
    ///
    /// The width runs across the curve and tangent to the surface, which for a
    /// ribbon arcing along a face is the vertical, and for one wrapping a
    /// corner turns with it. Both positions are in centimetres in the chassis's
    /// own frame, the way `StageMath.ribbonPath` produces them.
    @MainActor
    static func ribbonSegment(
        from: SIMD3<Double>, to: SIMD3<Double>, width: Double
    ) throws -> MeshResource {
        let direction = to - from
        let length = simd_length(direction)
        guard length > 1e-9 else { throw StageMeshError.degenerateRing }
        let along = direction / length
        // Straight out of the chassis's vertical axis at the segment's middle:
        // the ribbon's own face normal.
        let middle = (from + to) / 2
        let radial = SIMD3(middle.x, 0, middle.z)
        let outward = simd_length(radial) > 1e-9
            ? simd_normalize(radial)
            : SIMD3<Double>(0, 0, 1)
        var across = simd_cross(along, outward)
        if simd_length(across) < 1e-6 { across = SIMD3(0, 1, 0) }
        across = simd_normalize(across) * (width / 2)

        let corners = [from - across, from + across, to - across, to + across]
        let positions = corners.map {
            SIMD3(metres($0.x), metres($0.y), metres($0.z))
        }
        let normal = SIMD3(Float(outward.x), Float(outward.y), Float(outward.z))
        var descriptor = MeshDescriptor(name: "ribbon")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(Array(repeating: normal, count: 4))
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates([
            SIMD2(0, 0), SIMD2(0, 1), SIMD2(1, 0), SIMD2(1, 1),
        ])
        descriptor.primitives = .triangles([0, 1, 3, 0, 3, 2])
        return try MeshResource.generate(from: [descriptor])
    }

    /// The soft bloom behind a selected or ready receptacle (§4.3, §4.6).
    @MainActor
    static func bloom(width: Double, height: Double, cornerRadius: Double) -> MeshResource {
        .generatePlane(
            width: metres(width), height: metres(height), cornerRadius: metres(cornerRadius)
        )
    }

    // MARK: - The light thread

    /// UX_SPEC §4.2 and §9.7: a short thread of light leaving a receptacle in
    /// the cable's direction, fading out. It is the only ornament in the scene
    /// and it exists only when a real Mac is really linked.
    ///
    /// **One** mesh with **one** material: §4.2 asks for "one continuous tube
    /// — a smooth curve with the sag of a real cable, tapering gently and
    /// fading along its length — never a chain of visible segments". So the
    /// taper is in the geometry (`StageMath.threadTaper`) and the fade is in
    /// ``threadFade()``, a gradient the material reads by the tube's own `u`.
    /// A chain of cylinders at stepped opacities has a joint and a step at
    /// every seam, which is an insect's antenna rather than light.
    ///
    /// The thread is the same curve on every receptacle — it is drawn in the
    /// receptacle's own frame — so it is built once and shared.
    @MainActor
    static func thread() -> MeshResource? {
        if let threadMesh { return threadMesh }
        let spine = StageMath.threadPath().map {
            SIMD3(metres($0.x), metres($0.y), metres($0.z))
        }
        guard
            let tube = StageMath.sweep(along: spine, radius: {
                metres(threadRadius) * StageMath.threadTaper(at: $0)
            }),
            let mesh = try? tubeMesh(tube, name: "thread")
        else { return nil }
        threadMesh = mesh
        return mesh
    }

    /// The light thread's own opacity where it leaves the receptacle, and
    /// its radius there. §6.2 R2's loop is drawn at the same values from end
    /// to end, so the two threads are recognisably the same light.
    static let threadPeakOpacity: Float = 0.35
    static let threadRadius = 0.09

    /// The thread's fade, as the one texture its one material reads: white at
    /// `threadPeakOpacity × StageMath.threadFade(at:)`, 256 samples across and
    /// one high, addressed by the `u` the sweep writes along the tube's
    /// length. Read as an opacity map, so the ink tone stays the palette's.
    ///
    /// No mipmaps: this is a 256-pixel ramp read along a thread a few points
    /// wide on screen, and the first mip would flatten the whole fade into its
    /// average. Generated once, in both appearances — the fade is a shape, not
    /// a colour.
    @MainActor
    static func threadFade() throws -> TextureResource {
        if let threadFadeRamp { return threadFadeRamp }
        let width = 256
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: 1, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw StageMeshError.textureUnavailable }
        context.clear(CGRect(x: 0, y: 0, width: width, height: 1))
        for step in 0..<width {
            let u = Float(step) / Float(width - 1)
            let alpha = CGFloat(threadPeakOpacity * StageMath.threadFade(at: u))
            // Premultiplied white: every channel carries the same number, so
            // it reads the same whichever one the opacity semantic samples.
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha))
            context.fill(CGRect(x: step, y: 0, width: 1, height: 1))
        }
        guard let image = context.makeImage() else { throw StageMeshError.textureUnavailable }
        let ramp = try TextureResource(
            image: image, withName: "thread.fade",
            options: .init(
                semantic: PhysicallyBasedMaterial.Opacity.textureSemantic,
                mipmapsMode: .none
            )
        )
        threadFadeRamp = ramp
        return ramp
    }

    /// One tube of constant `radius`, swept end to end along `path` in
    /// centimetres in the chassis's own frame. No taper and no fade: both
    /// ends of this one are attached to something.
    ///
    /// Two lines in the app are drawn this way, and both are drawn as **one**
    /// mesh for the same reason ``thread()`` is — §4.2's "one continuous tube
    /// … never a chain of visible segments". §6.2 R2's loop between two ports
    /// of this Mac (StageLoop) walks the ribbon's path lifted off the surface;
    /// §S8's "single thin connecting line" to the ghost second Mac
    /// (StageGhostNode) walks out of the near face, across and back in. A
    /// cylinder per leg would put a flat cap and a visible joint at every turn
    /// — exactly where a line between two machines is looked at.
    @MainActor
    static func tube(along path: [SIMD3<Double>], radius: Double, name: String) -> MeshResource? {
        let spine = path.map { SIMD3(metres($0.x), metres($0.y), metres($0.z)) }
        guard
            let swept = StageMath.sweep(along: spine, radius: { _ in metres(radius) })
        else { return nil }
        return try? tubeMesh(swept, name: name)
    }

    @MainActor
    private static func tubeMesh(_ tube: StageMath.SweptTube, name: String) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(tube.positions)
        descriptor.normals = MeshBuffers.Normals(tube.normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(tube.coordinates)
        descriptor.primitives = .triangles(tube.indices)
        return try MeshResource.generate(from: [descriptor])
    }

    // MARK: - The grille

    /// The hole pattern of a `Chassis.grille`, in centimetres: the prototype's
    /// `grilleTexture()`, which draws a 640 × 512 px tile at 100 px/cm.
    ///
    /// These are renderer numbers, like the 0.16 and 0.22 cm recess depths:
    /// the catalogue says where the grille is, and this says what it is made
    /// of. One tile is an exact number of periods — 64 columns by 64 rows,
    /// the row count even so the half-pitch stagger of the odd rows continues
    /// across both wrap edges — which is what lets the strip repeat it a
    /// fractional number of times with no seam.
    enum GrillePattern {
        /// Hole pitch across a row.
        static let pitch = 0.10
        /// Pitch between rows.
        static let rowPitch = 0.08
        /// The hole's radius.
        static let radius = 0.032
        static let columns = 64
        static let rows = 64
        /// One tile, across and up.
        static var tileWidth: Double { pitch * Double(columns) }
        static var tileHeight: Double { rowPitch * Double(rows) }
        /// How far the strip stands proud of the shell. Scenery holes stand at
        /// 0.01, which is why the catalogue keeps the two apart in the plane.
        static let standoff = 0.02
        static let pixelsPerCentimetre = 100.0
    }

    /// The grille tile: one texture, generated the first time a chassis with a
    /// grille is built and shared by every one after it, in both appearances.
    ///
    /// White holes on transparent, so the tint comes from the palette and the
    /// same tile serves light and dark. It is read as an opacity mask with a
    /// threshold, which makes the material a cut-out: the aluminium shows
    /// through between the holes. Mipmapped, so the field does not moiré at
    /// the resting distance, where a 0.1 cm pitch is under a point.
    @MainActor
    static func grille() throws -> TextureResource {
        if let grilleTile { return grilleTile }
        let tile = try makeGrilleTile()
        grilleTile = tile
        return tile
    }

    @MainActor
    private static func makeGrilleTile() throws -> TextureResource {
        let scale = GrillePattern.pixelsPerCentimetre
        let width = Int((GrillePattern.tileWidth * scale).rounded())
        let height = Int((GrillePattern.tileHeight * scale).rounded())
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw StageMeshError.textureUnavailable }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let step = GrillePattern.pitch * scale
        let rowStep = GrillePattern.rowPitch * scale
        let radius = GrillePattern.radius * scale
        // One column and one row past each edge, so a hole that crosses the
        // tile's edge is completed on the other side and the wrap is exact.
        for row in -1...GrillePattern.rows {
            for column in -1...GrillePattern.columns {
                let stagger = row & 1 == 0 ? 0 : step / 2
                let x = Double(column) * step + stagger + step / 4
                let y = Double(row) * rowStep + rowStep / 2
                context.fillEllipse(
                    in: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)
                )
            }
        }
        guard let image = context.makeImage() else { throw StageMeshError.textureUnavailable }
        return try TextureResource(
            image: image, withName: "grille",
            options: .init(
                semantic: PhysicallyBasedMaterial.Opacity.textureSemantic,
                mipmapsMode: .allocateAndGenerateAll
            )
        )
    }

    /// How the tile is sampled: repeating, so the strip's UVs can run past 1,
    /// and anisotropic, because the back face is seen at a slant from the
    /// resting pose.
    @MainActor
    static func grilleSampler() -> MaterialParameters.Texture.Sampler {
        let descriptor = MTLSamplerDescriptor()
        descriptor.sAddressMode = .repeat
        descriptor.tAddressMode = .repeat
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.maxAnisotropy = 8
        return .init(descriptor)
    }

    /// The strip a grille is drawn on: a vertical band on the shell's own
    /// outline, standing `GrillePattern.standoff` proud of it, in the chassis's
    /// frame with `y` up and the base band already added.
    ///
    /// The prototype draws its grille as a flat plane, and its rectangle
    /// reaches past the flat part of the back face into both corners, where a
    /// plane floats up to 0.35 cm off the shell. This follows the corner
    /// instead: it walks the same `roundedRectPath` the shell is extruded
    /// from, so the strip lies on the aluminium for its whole length. The
    /// tile's repeat is baked into the texture coordinates — one tile per
    /// `GrillePattern.tileWidth` of arc and `tileHeight` of rise — so the
    /// hole pitch is the same centimetre everywhere on the curve.
    @MainActor
    static func grilleStrip(
        face: PortFace, u0: Double, u1: Double, y0: Double, y1: Double,
        width: Double, depth: Double, cornerRadius: Double, samples: Int = 64
    ) throws -> MeshResource {
        // The same outline, in the same chords, the shell's side band is
        // extruded from (`prism`), so every point here lies on the aluminium.
        let cornerSegments = 8
        let path = StageMath.roundedRectPath(
            width: width, height: depth, cornerRadius: cornerRadius, cornerSegments: cornerSegments
        )
        guard let perimeter = path.last?.distance, perimeter > 0, u1 > u0, y1 > y0 else {
            throw StageMeshError.degenerateRing
        }
        let across = (face == .back || face == .front) ? width : depth
        let radius = min(max(cornerRadius, 0), min(width, depth) / 2)
        let centres = StageMath.faceCentreDistances(
            width: width, depth: depth, cornerRadius: radius, cornerSegments: cornerSegments
        )
        let centre = switch face {
        case .back: centres.back
        case .right: centres.right
        case .front: centres.front
        case .left: centres.left
        }
        // `u` runs from the viewer's left, which is against the path's
        // direction on every face. `arc` is the path distance from the
        // face's middle to the point across from `u`, through the corner
        // where the rectangle reaches one.
        func arc(_ u: Double) -> Double {
            StageMath.arcOffset(
                fromFaceCentre: -(u - 0.5) * across, across: across, cornerRadius: radius,
                cornerSegments: cornerSegments
            )
        }
        let start = arc(u0), end = arc(u1)
        let (first, last) = start < end ? (start, end) : (end, start)
        let steps = max(samples, 1)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for step in 0...steps {
            let along = first + (last - first) * Double(step) / Double(steps)
            var distance = (centre + along).truncatingRemainder(dividingBy: perimeter)
            if distance < 0 { distance += perimeter }
            let sample = StageMath.sample(path, at: distance)
            let planar = sample.point + sample.normal * GrillePattern.standoff
            // Profile `x` is the chassis's `x`, and profile `y` is its `z`:
            // the same quarter turn `standing` gives the shell.
            let normal = SIMD3(Float(sample.normal.x), 0, Float(sample.normal.y))
            let u = Float((along - first) / GrillePattern.tileWidth)
            for (y, v) in [(y0, Float(0)), (y1, Float((y1 - y0) / GrillePattern.tileHeight))] {
                positions.append(SIMD3(metres(planar.x), metres(y), metres(planar.y)))
                normals.append(normal)
                coordinates.append(SIMD2(u, v))
            }
        }
        for step in 0..<steps {
            let a = UInt32(step * 2), d = a + 1, b = a + 2, c = a + 3
            // The path is counter-clockwise seen from above, so `along × up`
            // points into the box; wound the other way, the strip faces out.
            indices.append(contentsOf: [a, c, b, a, d, c])
        }

        var descriptor = MeshDescriptor(name: "grille")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(coordinates)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    // MARK: - The surround

    /// The stage's surround: `.windowBackground` everywhere the camera can
    /// look, lifting a shade toward the zenith so the key light has something
    /// neutral to bounce (§3.4). It is both the skybox and the IBL, which is
    /// why the stage follows the system theme instead of being a dark slab.
    @MainActor
    static func environment(background: CGColor, lift: CGColor) throws -> EnvironmentResource {
        let width = 128, height = 64
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let gradient = CGGradient(
                colorsSpace: space, colors: [lift, background] as CFArray,
                locations: [0, 0.52]
            )
        else { throw StageMeshError.textureUnavailable }

        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // The image's top row is the zenith; the fade reaches the background by
        // the horizon, so everything the camera can actually see is flat.
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0),
            options: []
        )
        guard let image = context.makeImage() else { throw StageMeshError.textureUnavailable }
        return try EnvironmentResource(
            equirectangular: image, options: .init(samplingQuality: .normal)
        )
    }
}

enum StageMeshError: Error {
    case degenerateRing
    case textureUnavailable
}
