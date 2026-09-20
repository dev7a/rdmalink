//
//  SnapshotHook.swift
//
//  A review hook, not a feature. It exists so a reviewer — or an orchestrating
//  agent with no screen — can get a true picture of the window in each of its
//  states without driving the app by hand.
//
//  Usage:
//
//      RDMALINK_SNAPSHOT=/tmp/hub.png ./RDMALink.app/Contents/MacOS/RDMALink
//      RDMALINK_SNAPSHOT=/tmp/front.png RDMALINK_SNAPSHOT_FACE=front ./…/RDMALink
//      RDMALINK_SNAPSHOT=/tmp/s13.png RDMALINK_SNAPSHOT_SHEET=whatThisAllMeans ./…
//      RDMALINK_SNAPSHOT=/tmp/s5.png RDMALINK_SNAPSHOT_ROUTE=review ./…/RDMALink
//      RDMALINK_SNAPSHOT=/tmp/s8.png RDMALINK_SNAPSHOT_ROUTE=other-mac ./…/RDMALink
//      RDMALINK_SNAPSHOT=/tmp/light.png RDMALINK_SNAPSHOT_APPEARANCE=light ./…
//
//  With `RDMALINK_SNAPSHOT` set, the app waits for the first inventory to land,
//  draws the key window into a bitmap with `cacheDisplay(in:to:)`, writes it as
//  a PNG and terminates. `RDMALINK_SNAPSHOT_FACE` is `back`, `front`, `left` or
//  `right` and turns the stage to that face before the capture.
//  `RDMALINK_SNAPSHOT_SHEET` is `whatThisAllMeans` or `settings` and puts
//  that surface in front first. `RDMALINK_SNAPSHOT_APPEARANCE` is `light` or
//  `dark` and forces this process's appearance.
//
//  `RDMALINK_SNAPSHOT_ROUTE` opens one of the app's own routes on the live
//  inventory first: `hub`, `preflight`, `choose`, `review`, `restore-sheet`,
//  `adopt-sheet`, `changelog` or `other-mac` (§S8, a screen in the working
//  area, with the ghost second Mac on the stage). The three assistant routes
//  arrive with the first Thunderbolt port already chosen. **Every one of
//  them is a read.**
//  `review` runs `SetUpPorts.preview` and stops; no route reaches
//  `perform`, opens an `AuthorizedSession` or raises the administrator
//  prompt — S6's burst is behind its own button, which nothing here presses.
//
//  Nothing here runs unless the environment variable is present, and nothing
//  here writes anywhere but the path it was handed.
//

import AppKit
import Foundation
import RDMALinkCore

enum SnapshotHook {
    /// Where to write the PNG, or nil when the app was launched normally.
    static var destination: URL? {
        guard let path = ProcessInfo.processInfo.environment["RDMALINK_SNAPSHOT"],
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// The face to turn the stage to before capturing, when one was asked for.
    static var face: PortFace? {
        ProcessInfo.processInfo.environment["RDMALINK_SNAPSHOT_FACE"]
            .flatMap(PortFace.init(rawValue:))
    }

    /// A surface to put in front of the window before capturing, so the sheet
    /// and the settings pane are reviewable too. `RDMALINK_SNAPSHOT_SHEET`.
    enum Surface: String, Sendable {
        case whatThisAllMeans
        case settings
    }

    static var surface: Surface? {
        ProcessInfo.processInfo.environment["RDMALINK_SNAPSHOT_SHEET"]
            .flatMap(Surface.init(rawValue:))
    }

    /// One of the app's own routes, opened on the live inventory before the
    /// capture. `RDMALINK_SNAPSHOT_ROUTE`.
    enum Route: String, Sendable {
        case hub
        case preflight
        case choose
        case review
        case restoreSheet = "restore-sheet"
        case adoptSheet = "adopt-sheet"
        case changelog
        case otherMac = "other-mac"
    }

    static var route: Route? {
        ProcessInfo.processInfo.environment["RDMALINK_SNAPSHOT_ROUTE"]
            .flatMap(Route.init(rawValue:))
    }

    /// How long a route is given to land: a sheet reads this Mac when it
    /// opens, the review screen runs its plan off the main actor, and §S8's
    /// ghost takes a 0.7 s camera arc to slide in beside the machine.
    private static let routeDelay = Duration.milliseconds(1400)

    /// `light` or `dark`, so both appearances are reviewable from one machine
    /// without touching the reviewer's own System Settings. It sets this
    /// process's appearance and nothing outside it.
    static var appearance: NSAppearance? {
        switch ProcessInfo.processInfo.environment["RDMALINK_SNAPSHOT_APPEARANCE"] {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }

    /// How long to let SwiftUI settle after the inventory lands. The window is
    /// already in its final shape by then — S0 guarantees that — so this only
    /// covers the frame the new content is drawn in.
    private static let settleDelay = Duration.milliseconds(400)

    /// Waits for `isReady`, turns the stage to the requested face, puts the
    /// requested surface in front, captures, and terminates. Returns only if
    /// the capture failed, so a broken hook never leaves a headless run
    /// hanging.
    @MainActor
    static func run(
        isReady: @MainActor () -> Bool,
        turnTo: @MainActor (PortFace) -> Void,
        present: @MainActor (Surface) -> Void,
        open: @MainActor (Route) -> Void = { _ in }
    ) async {
        guard let destination else { return }
        if let appearance { NSApplication.shared.appearance = appearance }
        while !isReady() {
            try? await Task.sleep(for: .milliseconds(50))
        }
        // A sheet or the settings window only becomes key once the app is
        // front, and a headless launch is not.
        NSApplication.shared.activate()
        // A forced appearance only reaches SwiftUI once the app is front, and
        // an appearance change rebuilds the stage — which puts the camera back
        // at its resting pose. Posing before that lands turns the machine and
        // then silently turns it back.
        if appearance != nil { try? await Task.sleep(for: .milliseconds(500)) }
        if let route {
            open(route)
            try? await Task.sleep(for: routeDelay)
        }
        if let face {
            turnTo(face)
            // The camera arc is 0.7 s (§3.5) and is stepped by the render
            // loop, so the capture waits for it rather than for a frame.
            try? await Task.sleep(for: .milliseconds(1100))
        }
        if let surface {
            try? await Task.sleep(for: .milliseconds(200))
            present(surface)
        }
        try? await Task.sleep(for: settleDelay)
        do {
            try await capture(to: destination)
        } catch {
            FileHandle.standardError.write(Data("RDMALINK_SNAPSHOT failed: \(error)\n".utf8))
        }
        // A sheet is modal, and `terminate` asks the run loop politely. The
        // picture is already on disk by here, so a hook that cannot get its
        // answer must not leave a headless run hanging (its own header says so).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            exit(0)
        }
        NSApplication.shared.terminate(nil)
    }

    /// Draws the key window into a PNG.
    ///
    /// The frame view rather than the content view, because the unified
    /// toolbar is drawn above the content view and a review picture without
    /// `Check Again` and `Help` would be missing what §2.2 specifies. It
    /// falls back to the content view if AppKit ever stops giving the
    /// content view a superview.
    ///
    /// `cacheDisplay(in:to:)` draws the AppKit view tree, which leaves a hole
    /// where the `RealityView` is — a Metal layer is not an AppKit drawing.
    /// The stage is therefore rendered off screen and composited into that
    /// hole; see App/Stage/StageSnapshot.swift for why that is the only way
    /// left on macOS 27.
    @MainActor
    static func capture(to destination: URL) async throws {
        let application = NSApplication.shared
        // A sheet is what the user is looking at when one is up, so it wins.
        // The windows are asked rather than `NSApplication.keyWindow`, which
        // answers nil while the app is not the active application — which a
        // headless launch is not, however hard it activates.
        let window = application.windows.first { $0.isSheet && $0.isVisible }
            ?? application.windows.first(where: \.isKeyWindow)
            ?? application.windows.first(where: \.isMainWindow)
            ?? application.windows.first { $0.isVisible }
        guard let content = window?.contentView else { throw SnapshotFailure.noWindow }
        let view = content.superview ?? content
        let bounds = view.bounds
        guard let representation = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw SnapshotFailure.noBitmap
        }
        // The stage has to come out of the AppKit pass as a transparent hole,
        // or there is nothing for the off-screen render to be composited
        // *under* and the floating controls are painted over. The window's own
        // opaque fill is what would otherwise close the hole, so it is lifted
        // for the one draw and put straight back.
        let wasOpaque = window?.isOpaque ?? true
        let previousBackground = window?.backgroundColor
        window?.isOpaque = false
        window?.backgroundColor = .clear
        view.cacheDisplay(in: bounds, to: representation)
        window?.isOpaque = wasOpaque
        if let previousBackground { window?.backgroundColor = previousBackground }

        if let window { await compositeStage(into: representation, window: window, frameView: view) }
        // Whatever is still transparent — the toolbar strip above the stage,
        // and the stage itself if the render failed — is the window's own
        // background, which is what was lifted to make the hole.
        fill(representation, bounds: bounds, with: backgroundColor(of: window))
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw SnapshotFailure.noPNG
        }
        try data.write(to: destination)
    }

    /// `.windowBackgroundColor` resolved against the window's own appearance.
    /// A bitmap context carries no appearance of its own, so a dynamic colour
    /// filled into one resolves against whatever happens to be current — which
    /// is how a light-appearance capture ended up with a black toolbar strip.
    @MainActor
    private static func backgroundColor(of window: NSWindow?) -> NSColor {
        var resolved = NSColor.windowBackgroundColor
        let appearance = window?.effectiveAppearance ?? NSApplication.shared.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? resolved
        }
        return resolved
    }

    /// Puts `color` behind everything already drawn.
    @MainActor
    private static func fill(
        _ representation: NSBitmapImageRep, bounds: CGRect, with color: NSColor
    ) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: representation) else { return }
        NSGraphicsContext.current = context
        color.setFill()
        bounds.fill(using: .destinationOver)
        context.flushGraphics()
    }

    /// Draws the off-screen stage render over the hole `cacheDisplay` left.
    ///
    /// The stage reports its rectangle in SwiftUI's global space, which is the
    /// content view's, top-left origin. The bitmap is the frame view's, in
    /// AppKit's bottom-left origin, so the rectangle is moved into the content
    /// view's place in the frame view and then turned the right way up.
    @MainActor
    private static func compositeStage(
        into representation: NSBitmapImageRep, window: NSWindow, frameView: NSView
    ) async {
        guard let capture = StageSnapshot.capture,
              let rendered = await capture(window.backingScaleFactor),
              let content = window.contentView
        else { return }

        let contentFrame = content.convert(content.bounds, to: frameView)
        let stage = rendered.frameInWindow
        let target = CGRect(
            x: contentFrame.minX + stage.minX,
            y: contentFrame.maxY - stage.maxY,
            width: stage.width,
            height: stage.height
        )

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: representation) else { return }
        NSGraphicsContext.current = context
        // Underneath, not over: the narration capsule, the face selector and
        // the Fit / Reset View buttons are drawn by AppKit and must survive.
        NSImage(cgImage: rendered.image, size: target.size).draw(
            in: target, from: .zero, operation: .destinationOver, fraction: 1
        )
        context.flushGraphics()
    }

    enum SnapshotFailure: Error, CustomStringConvertible {
        case noWindow, noBitmap, noPNG

        var description: String {
            switch self {
            case .noWindow: "no visible window to capture"
            case .noBitmap: "the window would not make a bitmap"
            case .noPNG: "the bitmap would not encode as PNG"
            }
        }
    }
}
