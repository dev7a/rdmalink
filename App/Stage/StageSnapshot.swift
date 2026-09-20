//
//  StageSnapshot.swift
//
//  How the review hook gets a picture of the 3D stage.
//
//  `NSView.cacheDisplay(in:to:)` draws the AppKit view tree and nothing else.
//  A `RealityView` is a Metal layer, so a window bitmap taken that way has a
//  hole where the stage is — verified on this Mac: the render loop ticks at
//  60 fps with the whole chassis in frame and the captured PNG is empty there.
//  ScreenCaptureKit would see the real pixels but wants Screen Recording,
//  which a headless review run cannot ask for, and `CGWindowListCreateImage`
//  is unavailable in macOS 27.
//
//  So the stage is rendered a second time, off screen, with `RealityRenderer`:
//  the same builder, the same palette, the same appearance and the same camera
//  pose the live scene is holding, into an `MTLTexture` the hook composites
//  into the window bitmap. Entities belong to exactly one scene, which is why
//  a fresh graph is built rather than the live one borrowed.
//
//  Nothing in this file runs unless `RDMALINK_SNAPSHOT` is set.
//

import CoreImage
import Foundation
import Metal
import RealityKit
import RDMALinkCore

/// Where the camera is: the spherical rig `StageScene` drives, as a value.
struct StageCameraPose: Equatable {
    var yaw: Double
    var pitch: Double
    var radius: Double
    var target: SIMD3<Float>
}

@MainActor
enum StageSnapshot {
    /// Installed by `StageView` while the hook is armed. It answers with the
    /// stage as it is right now, and where in the window it sits.
    static var capture: ((CGFloat) async -> (image: CGImage, frameInWindow: CGRect)?)?

    /// Renders one frame of a stage off screen.
    ///
    /// - Parameter scale: the window's backing scale, so the composited image
    ///   lands at the same resolution as the rest of the bitmap.
    static func image(
        moment: StageMoment,
        archetype: Archetype,
        palette: StagePalette,
        appearance: StageAppearance,
        pose: StageCameraPose,
        size: CGSize,
        scale: CGFloat
    ) async -> CGImage? {
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width > 0, height > 0, let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard
            let texture = device.makeTexture(descriptor: descriptor),
            let renderer = try? RealityRenderer(),
            let output = try? RealityRenderer.CameraOutput(
                .singleProjection(colorTexture: texture)
            )
        else { return nil }

        let graph = StageSceneBuilder.build(
            ports: moment.ports, archetype: archetype, palette: palette,
            appearance: appearance
        )
        // The builder leaves every ring, ribbon, stub, bloom and thread
        // disabled at opacity 0; only `StageScene.apply` ever raises them, and
        // it runs against the live graph. Without this the review render is
        // bare aluminium with the whole of §4.2, §4.3 and §4.4 missing from it.
        StageScene.settle(graph, moment: moment)
        renderer.entities.append(graph.root)

        if let environment = try? StageMesh.environment(
            background: palette.background.cgColor, lift: palette.backgroundLift.cgColor
        ) {
            renderer.lighting.resource = environment
        }
        renderer.cameraSettings.colorBackground = .color(palette.background.cgColor)

        let camera = PerspectiveCamera()
        camera.components.set(
            PerspectiveCameraComponent(
                near: 0.01, far: 12,
                fieldOfViewInDegrees: Float(StageScene.verticalFieldOfView * 180 / .pi),
                fieldOfViewOrientation: .vertical
            )
        )
        camera.look(
            at: pose.target,
            from: StageMath.orbitPosition(
                target: pose.target, yaw: pose.yaw, pitch: pose.pitch, radius: pose.radius
            ),
            relativeTo: nil
        )
        renderer.entities.append(camera)
        renderer.activeCamera = camera

        // One update to settle the transforms, then one rendered frame, waited
        // for rather than blocked on: the completion handler runs off the main
        // actor and a semaphore here would be a deadlock waiting to happen.
        let rendered: Bool = await withCheckedContinuation { continuation in
            do {
                try renderer.update(0)
                try renderer.updateAndRender(deltaTime: 1.0 / 60.0, cameraOutput: output) { _ in
                    continuation.resume(returning: true)
                }
            } catch {
                continuation.resume(returning: false)
            }
        }
        guard rendered else { return nil }

        // `RealityRenderer` writes *linear* values into the `.rgba16Float`
        // target. Declaring them sRGB here told Core Image no conversion was
        // needed and put the linear buffer straight into eight bits: measured
        // on this Mac, a 30/255 window background came out as 3 and a 212
        // chassis as 166, which is sRGB-decode applied once too few times.
        // Every judgement about dark mode, materials and ring contrast was
        // being made from that.
        guard
            let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let frame = CIImage(mtlTexture: texture, options: [.colorSpace: linear])
        else { return nil }
        // Core Image's origin is bottom-left and Metal's is top-left.
        let flipped = frame.transformed(
            by: CGAffineTransform(1, 0, 0, -1, 0, frame.extent.height)
        )
        return CIContext(mtlDevice: device).createCGImage(
            flipped, from: flipped.extent, format: .RGBA8, colorSpace: space
        )
    }
}

/// A moment the review hook can ask the stage to hold still in.
///
/// `RDMALINK_SNAPSHOT` captures the window as it is; the states below are the
/// ones that only exist while something is happening — a ring half closed, the
/// ribbon letting go, Identify listening, a change row being pointed at — and
/// which a headless run would otherwise never see. `RDMALINK_SNAPSHOT_STAGE`
/// names one, `StageView` applies it to the model before the capture, and
/// nothing here runs unless that variable is set.
///
///     RDMALINK_SNAPSHOT=/tmp/apply.png RDMALINK_SNAPSHOT_STAGE=applyHalf ./…
///
/// Each state acts on the first Thunderbolt receptacle in physical order that
/// suits it, because a review picture wants the same port every time.
enum StageSnapshotState: String, Sendable, CaseIterable {
    /// §4.4: every bridge ribbon up, the way review, apply and restore show it.
    case ribbons
    /// §S3: two receptacles named by a check, ringed together.
    case attention
    /// §S6: two of the four gaps closed, the ribbon half retracted.
    case applyHalf
    /// §S6: every gap closed — the solid accent ring.
    case applyDone
    /// §S10: the inverse, stopped half-open the way a failed verification
    /// leaves it (R20).
    case restoreHalfOpen
    /// §S4b: every eligible receptacle listening.
    case identifyWatching
    /// §S4b: the answer, with the silence around it.
    case identifyAnswer
    /// §S4b: the replug bloom.
    case identifyReplug
    /// §S5: hovering **Leave the Thunderbolt Bridge**.
    case previewLeaveBridge
    /// §S5: hovering **Get its own network service**.
    case previewService
    /// §S5: hovering **Turn IPv4 off, IPv6 to link-local**.
    case previewAddresses
    /// §S5: hovering **Save how to undo this**.
    case previewNote

    /// `RDMALINK_SNAPSHOT_STAGE`, when it names one of these.
    static var requested: StageSnapshotState? {
        ProcessInfo.processInfo.environment["RDMALINK_SNAPSHOT_STAGE"]
            .flatMap(StageSnapshotState.init(rawValue:))
    }

    /// Drives the model into this state. Intents only — the same ones the
    /// screens call — so a review picture can never show something the app
    /// cannot actually reach.
    @MainActor
    func apply(to model: StageModel) {
        let ports = model.ports.filter(\.isThunderbolt)
        guard let first = ports.first else { return }
        switch self {
        case .ribbons:
            model.ribbons = .all
        case .attention:
            model.attention(ids: Set(ports.prefix(2).map(\.id)))
        case .applyHalf:
            model.ribbons = .all
            model.select(first.id)
            model.progress(step: 2, of: 5, for: first.id)
        case .applyDone:
            model.ribbons = .all
            model.select(first.id)
            model.progress(step: 5, of: 5, for: first.id)
        case .restoreHalfOpen:
            model.ribbons = .all
            model.select(first.id)
            model.restoreProgress(step: 2, of: 3, for: first.id)
        case .identifyWatching:
            model.startIdentify()
        case .identifyAnswer:
            model.startIdentify()
            model.identify(answer: first.id)
        case .identifyReplug:
            model.startIdentify()
            model.identify(answer: first.id)
            model.identify(replug: first.id)
        case .previewLeaveBridge, .previewService, .previewAddresses, .previewNote:
            model.ribbons = .all
            model.select(first.id)
            model.preview(previewKind, for: first.id)
        }
    }

    private var previewKind: StagePreview? {
        switch self {
        case .previewLeaveBridge: .leaveBridge
        case .previewService: .service
        case .previewAddresses: .addresses
        case .previewNote: .note
        default: nil
        }
    }
}
