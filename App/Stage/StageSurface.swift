//
//  StageSurface.swift
//
//  The stage's render surface: `RealityRenderer` drawing into a `CAMetalLayer`
//  a frame at a time, and only while something on stage is moving.
//
//  `RealityView` renders on a display link for as long as it is on screen.
//  Measured on a Mac Studio with nothing moving, that was about two thirds of
//  the app's idle CPU — and it went on while the app was hidden. RealityKit
//  has no public way to pause it. `RealityRenderer` renders when asked, so
//  here the display link runs while `StageScene` reports something still
//  moving — a camera arc, a cross-fade, a breath — and pauses on the frame it
//  settles. Any input, a resize, or any change to what the scene reads from
//  `StageModel` starts it again.
//

import AppKit
import Metal
import Observation
import QuartzCore
import RealityKit
import SwiftUI

struct StageSurface: NSViewRepresentable {
    let scene: StageScene
    let model: StageModel
    let appearance: StageAppearance
    let buildKey: StageBuildKey
    /// Builds the scene for `buildKey` into a renderer. The stage view's,
    /// because it knows the chassis and the palette.
    let install: (RealityRenderer) -> Void

    func makeNSView(context: Context) -> StageSurfaceView {
        let view = StageSurfaceView(scene: scene, model: model)
        update(view)
        return view
    }

    func updateNSView(_ view: StageSurfaceView, context: Context) {
        update(view)
    }

    static func dismantleNSView(_ view: StageSurfaceView, coordinator: ()) {
        view.tearDown()
    }

    private func update(_ view: StageSurfaceView) {
        // Reduce Motion and Reduce Transparency change no geometry and no
        // material, so the scene reads them rather than being rebuilt.
        scene.appearance = appearance
        view.wanted = (buildKey, install)
        view.installIfNeeded()
    }
}

@MainActor
final class StageSurfaceView: NSView {
    /// `nil` when RealityKit would not make one: the stage is then the
    /// window background, and the port list is the whole path (§8.1).
    let renderer: RealityRenderer?
    /// What the stage view last asked this surface to show, and how to build
    /// it — kept until the surface is in a window and can take the scene.
    var wanted: (key: StageBuildKey, install: (RealityRenderer) -> Void)?
    /// What this surface's renderer was last built for.
    private var installedKey: StageBuildKey?

    private let scene: StageScene
    private let model: StageModel
    private var link: CADisplayLink?
    /// When the last frame was drawn, or `nil` while the loop is paused.
    private var lastFrame: CFTimeInterval?
    private var observing: Task<Void, Never>?

    init(scene: StageScene, model: StageModel) {
        self.scene = scene
        self.model = model
        renderer = try? RealityRenderer()
        // Four samples a pixel: ring tracks are a few points wide, and an
        // unsmoothed edge on one stair-steps.
        renderer?.cameraSettings.antialiasing = .multisample4X
        super.init(frame: .zero)
        wantsLayer = true
        // Everything the scene reads from the model, as one value: a change to
        // any of it is a frame owed, whether or not anything was moving.
        observing = Task { [weak self, model] in
            for await _ in Observations({ (model.wakeToken, model.moment()) }) {
                self?.setNeedsFrames()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = MTLCreateSystemDefaultDevice()
        // `RealityRenderer` writes linear light into a half-float target; a
        // layer that says so is composited correctly, where an 8-bit sRGB one
        // would crush the dark end (see App/Stage/StageSnapshot.swift).
        layer.pixelFormat = .rgba16Float
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        layer.framebufferOnly = false
        layer.isOpaque = true
        return layer
    }

    /// The pointer and the wheel belong to the SwiftUI gestures laid over the
    /// stage, not to the layer.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            link?.invalidate()
            link = nil
            lastFrame = nil
            return
        }
        if link == nil {
            let link = displayLink(target: self, selector: #selector(frame(_:)))
            // Common modes, so a drag, a live resize or an open menu does not
            // stall a camera arc half way.
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        resize()
        installIfNeeded()
        setNeedsFrames()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        resize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resize()
    }

    /// Starts the loop, or keeps it running: the next display refresh draws a
    /// frame, and so does every one after it until the scene settles.
    func setNeedsFrames() {
        link?.isPaused = false
    }

    /// Builds what the stage view asked for into this surface's renderer,
    /// once the surface is in a window. The scene has one camera and one
    /// graph, and entities belong to one renderer: the surface on screen
    /// holds them, and one SwiftUI made without showing it builds nothing.
    func installIfNeeded() {
        guard window != nil, let renderer, let wanted else { return }
        let holds = scene.surface === self
        guard !holds || installedKey != wanted.key else { return }
        scene.surface = self
        wanted.install(renderer)
        installedKey = wanted.key
        setNeedsFrames()
    }

    func tearDown() {
        observing?.cancel()
        observing = nil
        link?.invalidate()
        link = nil
        if scene.surface === self { scene.surface = nil }
        // The graph is released with the renderer rather than left holding
        // the scene's camera, which a surface made again will take over.
        renderer?.entities.removeAll()
    }

    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    private func resize() {
        guard let metalLayer, let window else { return }
        let scale = window.backingScaleFactor
        metalLayer.contentsScale = scale
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard size.width >= 1, size.height >= 1, metalLayer.drawableSize != size else { return }
        metalLayer.drawableSize = size
        setNeedsFrames()
    }

    @objc private func frame(_ link: CADisplayLink) {
        // The first frame after a pause steps one refresh, not the length of
        // the pause: the scene's clock only runs while something moves.
        let deltaTime = lastFrame.map { min(max(link.timestamp - $0, 0), 0.1) }
            ?? (link.targetTimestamp - link.timestamp)
        lastFrame = link.timestamp
        let moving = scene.update(deltaTime: deltaTime, model: model)
        render(deltaTime: deltaTime)
        guard !moving else { return }
        // This frame drew the settled state; nothing more is owed until
        // something asks.
        link.isPaused = true
        lastFrame = nil
    }

    private func render(deltaTime: TimeInterval) {
        guard
            let renderer, let metalLayer,
            metalLayer.drawableSize.width >= 1, metalLayer.drawableSize.height >= 1,
            let drawable = metalLayer.nextDrawable(),
            let output = try? RealityRenderer.CameraOutput(
                .singleProjection(colorTexture: drawable.texture)
            )
        else { return }
        let presentable = Presentable(drawable: drawable)
        try? renderer.updateAndRender(
            deltaTime: deltaTime, cameraOutput: output,
            whenScheduled: { _ in presentable.drawable.present() }
        )
    }
}

/// A drawable handed to the renderer's scheduling callback, which runs off
/// the main actor. It is presented there and touched nowhere else.
private struct Presentable: @unchecked Sendable {
    let drawable: any CAMetalDrawable
}
