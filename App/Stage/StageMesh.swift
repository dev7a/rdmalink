//
//  StageMesh.swift
//
//  The geometry and textures the stage generates at runtime. Nothing is loaded
//  from an asset: a USDZ of a Mac is trade dress, and a procedural rounded box
//  with the right holes in it is not (UX_SPEC §3.4).
//

import CoreGraphics
import Foundation
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
    @MainActor private static var threadSegments: [ThreadSegment]?

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
    /// Returned as segments so the fade is a gradient of opacities — one mesh
    /// would need a shader, and a single `OpacityComponent` would fade the
    /// whole thread evenly, which reads as a rod rather than as light.
    struct ThreadSegment {
        var mesh: MeshResource
        var transform: Transform
        var opacity: Float
    }

    /// The thread is the same curve on every receptacle — it is drawn in the
    /// receptacle's own frame — so it is built once and shared.
    @MainActor
    static func thread() -> [ThreadSegment] {
        if let threadSegments { return threadSegments }
        let segments = makeThread()
        threadSegments = segments
        return segments
    }

    @MainActor
    private static func makeThread(
        segments count: Int = 8, peakOpacity: Float = 0.35
    ) -> [ThreadSegment] {
        let start = SIMD3<Float>(0, 0, metres(0.4))
        let control = SIMD3<Float>(0, metres(-0.5), metres(6))
        let end = SIMD3<Float>(metres(0.6), metres(-7), metres(10))

        func point(_ t: Float) -> SIMD3<Float> {
            let inverse = 1 - t
            return inverse * inverse * start + 2 * inverse * t * control + t * t * end
        }

        return (0..<count).map { index in
            let t0 = Float(index) / Float(count)
            let t1 = Float(index + 1) / Float(count)
            let a = point(t0), b = point(t1)
            let axis = b - a
            let length = simd_length(axis)
            let radius = metres(0.09) * (1 - 0.75 * t0)
            let mesh = MeshResource.generateCylinder(height: length, radius: max(radius, 0.0002))
            // generateCylinder is built along +y; aim it along the segment.
            // `simd_quatf(from:to:)` is undefined for antiparallel vectors, so
            // a segment that happens to point straight down gets the half turn
            // spelled out rather than a NaN transform.
            let direction = simd_normalize(axis)
            let rotation = direction.y < -0.9999
                ? simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
                : simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction)
            let transform = Transform(
                scale: .one, rotation: rotation, translation: (a + b) / 2
            )
            let fade = 1 - Float(index) / Float(count)
            return ThreadSegment(
                mesh: mesh, transform: transform, opacity: peakOpacity * fade * fade
            )
        }
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
