//
//  StageView.swift
//
//  The left 58 % of the window: the RealityKit stage (UX_SPEC §2.3).
//
//  Self-contained on purpose. It takes one `StageModel`, draws it, and posts
//  intents back into it; the window decides what a selection means. The port
//  list in the assistant column is the complete path to everything here
//  (§8.1), so nothing in this file may be the only way to do anything.
//

import AppKit
import RealityKit
import RDMALinkCore
import SwiftUI

struct StageView: View {
    let model: StageModel
    /// §4.5: clicking a USB-only receptacle produces the USB copy inline (R3),
    /// which is the working area's to draw. The stage only reports the click.
    var onUSBOnlyClick: ((StagePort) -> Void)?
    /// §S4's ⌘-click and ⇧-click, on the one screen that has a selection to
    /// extend. Absent elsewhere, so a modified click is an ordinary one.
    var onExtendClick: ((StagePort) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var scene = StageScene()
    @State private var focusedID: StagePort.ID?
    @State private var lastTranslation: CGSize?
    @State private var dragDistance: CGFloat = 0
    /// Review hook only: `RDMALINK_SNAPSHOT_STAGE` is posed once per launch.
    @State private var hasPosedForSnapshot = false
    @FocusState private var isStageFocused: Bool

    private var appearance: StageAppearance {
        StageAppearance(
            colorScheme: colorScheme,
            reduceMotion: reduceMotion,
            increaseContrast: contrast == .increased,
            reduceTransparency: reduceTransparency
        )
    }

    private var buildKey: StageBuildKey {
        StageBuildKey(
            geometry: StageBuildKey.Geometry(
                archetype: model.archetype,
                shape: model.ports.map { "\($0.id)|\($0.face.rawValue)|\($0.kind.rawValue)" }
            ),
            colorScheme: colorScheme,
            increaseContrast: contrast == .increased
        )
    }

    var body: some View {
        // §8.2's container is the render surface alone. Wrapping the overlays
        // in it too would put `Back`, `Front`, `Fit` and `Reset View` under an
        // `.accessibilityChildren`, which *replaces* what it covers — and §8.7
        // needs "click Back" to find a real element.
        surface
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(containerSummary))
            .accessibilityChildren { accessibilityElements }
            .overlay(alignment: .top) {
                StageNarration(line: model.narration, appearance: appearance)
                    .padding(.top, 14)
            }
            .overlay(alignment: .bottom) { faceSelector }
            .overlay(alignment: .bottomTrailing) {
                StageViewControls(fit: model.fit, reset: model.reset, appearance: appearance)
                    .padding(12)
            }
            // §S5's hover-to-preview for **Save how to undo this**.
            .overlay(alignment: .trailing) {
                StageBookmarkGlyph(
                    isShowing: model.preview?.kind == .note, appearance: appearance
                )
                .padding(.trailing, 18)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                let previous = scene.viewport
                guard size != previous else { return }
                scene.viewport = size
                scene.reframe(previousViewport: previous)
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                scene.frameInWindow = $0
            }
            .onChange(of: model.cameraRequest) { _, request in
                guard let request else { return }
                scene.perform(request)
                model.cameraRequestHandled()
            }
            .onChange(of: model.announcement) { _, announcement in
                guard let announcement else { return }
                AccessibilityNotification.Announcement(announcement).post()
                model.announcementDelivered()
            }
            .onChange(of: isStageFocused) { _, focused in
                focusedID = focused ? (model.selectedID ?? firstThunderboltID) : nil
                scene.setFocus(focusedID)
            }
            .onAppear {
                scene.startScrollMonitor()
                armSnapshotCapture()
            }
            // Review hook only; see App/Stage/StageSnapshot.swift. The state is
            // posed the moment the first inventory lands, which is also what
            // the hook waits for before it starts its own settle.
            .onChange(of: model.ports.count, initial: true) { _, count in
                guard SnapshotHook.destination != nil, count > 0, !hasPosedForSnapshot,
                      let state = StageSnapshotState.requested
                else { return }
                hasPosedForSnapshot = true
                state.apply(to: model)
            }
            .onDisappear {
                // `EventSubscription` keeps the scene alive on its own, and
                // `RealityViewCameraContent` keeps the whole entity graph
                // alive. §8.5's reflow gives this view a new identity every
                // time the window crosses 900 pt, so an abandoned stage that
                // is never torn down is a full graph leaked per crossing.
                scene.stopScrollMonitor()
                scene.subscription?.cancel()
                scene.subscription = nil
                scene.content = nil
                scene.onFaceChanged = nil
                StageSnapshot.capture = nil
            }
    }

    /// Review hook only; see App/Stage/StageSnapshot.swift. A window bitmap
    /// cannot read a Metal layer, so the hook is handed a closure that renders
    /// this stage off screen at whatever pose it is holding.
    private func armSnapshotCapture() {
        guard SnapshotHook.destination != nil else { return }
        StageSnapshot.capture = { [model, scene] scale in
            let frame = scene.frameInWindow
            guard frame.width > 1, frame.height > 1 else { return nil }
            guard
                let image = await StageSnapshot.image(
                    moment: model.moment(focused: scene.focusedID),
                    archetype: model.archetype,
                    palette: StagePalette(appearance: scene.appearance),
                    appearance: scene.appearance,
                    pose: scene.pose,
                    size: frame.size,
                    scale: scale
                )
            else { return nil }
            return (image, frame)
        }
    }

    // MARK: - The scene

    private var surface: some View {
        ZStack {
            // §3.4: the stage background is `.windowBackground` in both
            // appearances. The generated environment paints the same colour
            // inside the renderer; this is what shows if it ever does not.
            //
            // Review hook only: while a snapshot is being taken this backdrop
            // is left out, so the window bitmap has a real hole where the
            // Metal layer is and the off-screen render can be composited
            // *under* the floating controls instead of over them.
            if SnapshotHook.destination == nil {
                Rectangle().fill(.windowBackground)
            }

            RealityView { content in
                content.camera = .virtual
                install(into: &content)
                scene.content = content
                // Weakly, and torn down in `onDisappear`: the subscription
                // lives on the scene, so a strong capture here is a cycle that
                // keeps the whole entity graph alive after the view is gone.
                let live = scene
                scene.subscription = content.subscribe(
                    to: SceneEvents.Update.self
                ) { [weak live, model] event in
                    MainActor.assumeIsolated {
                        live?.update(deltaTime: event.deltaTime, model: model)
                    }
                }
            } update: { content in
                scene.content = content
                // Reduce Motion and Reduce Transparency change no geometry and
                // no material, so they are read off the scene every frame
                // rather than rebuilt for.
                scene.appearance = appearance
                if scene.installedKey != buildKey { install(into: &content) }
            }
            .realityViewCameraControls(.none)
            .onContinuousHover(coordinateSpace: .local, perform: hover)
            .gesture(orbit)
            .simultaneousGesture(tap)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isStageFocused)
        .onKeyPress(.leftArrow) { moveFocus(by: -1) }
        .onKeyPress(.rightArrow) { moveFocus(by: 1) }
        .onKeyPress(.upArrow) { cycleFace(by: -1) }
        .onKeyPress(.downArrow) { cycleFace(by: 1) }
        .onKeyPress(.space) { activateFocused() }
    }

    private func install(into content: inout RealityViewCameraContent) {
        let palette = StagePalette(appearance: appearance)
        if let environment = try? StageMesh.environment(
            background: palette.background.cgColor, lift: palette.backgroundLift.cgColor
        ) {
            content.environment = .skybox(environment)
        }
        scene.appearance = appearance
        scene.onFaceChanged = { [model] face in model.currentFace = face }
        // Only a new machine earns the resting pose. An appearance change is
        // not a new launch, and a user who has orbited to inspect a port must
        // not lose the pose because the sun went down (§9.2's reasoning, for
        // the camera this time).
        let key = buildKey
        scene.install(
            StageSceneBuilder.build(
                ports: model.ports, archetype: model.archetype, palette: palette,
                appearance: appearance
            ),
            into: &content,
            keepingPose: scene.installedKey?.geometry == key.geometry
        )
        scene.installedKey = key
    }

    // MARK: - Overlays

    @ViewBuilder
    private var faceSelector: some View {
        // §2.3: hidden entirely when the model has one relevant face.
        let faces = model.relevantFaces
        if faces.count > 1 {
            StageFaceSelector(
                faces: faces, current: model.currentFace, appearance: appearance,
                unseenChange: model.unseenChange, turnTo: model.turnTo
            )
            .padding(.bottom, 14)
        }
    }

    // MARK: - Pointer

    private func hover(_ phase: HoverPhase) {
        switch phase {
        case .active(let point):
            scene.isPointerInside = true
            let id = scene.portID(at: point)
            model.hover(id)
            cursor(for: id).set()
        case .ended:
            scene.isPointerInside = false
            model.hover(nil)
            NSCursor.arrow.set()
        }
    }

    /// §4.5: the cursor becomes `.operationNotAllowed` over a USB-only
    /// receptacle — the model refuses before the panel has to explain.
    private func cursor(for id: StagePort.ID?) -> NSCursor {
        guard let port = model.ports.first(where: { $0.id == id }) else { return .arrow }
        return port.isThunderbolt ? .pointingHand : .operationNotAllowed
    }

    /// §3.4's orbit.
    ///
    /// `minimumDistance: 0` on purpose: the gesture has to see the press
    /// itself, because that is the only thing that makes `dragDistance` the
    /// distance travelled during the press the tap is about to end rather than
    /// whatever the previous orbit left behind. Zeroing it in `onEnded`
    /// instead cannot work — the tap's `onEnded` and this one both fire on
    /// mouse-up and their order is not defined — and zeroing it only at the
    /// start of the *next* drag means every click after an orbit is swallowed.
    /// The camera still does not move until the pointer has travelled the 2 pt
    /// the gesture used to require.
    private var orbit: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let previous = lastTranslation else {
                    lastTranslation = value.translation
                    dragDistance = 0
                    return
                }
                let dx = value.translation.width - previous.width
                let dy = value.translation.height - previous.height
                lastTranslation = value.translation
                dragDistance += abs(dx) + abs(dy)
                guard dragDistance >= 2 else { return }
                scene.orbit(deltaX: Double(dx), deltaY: Double(dy))
            }
            .onEnded { _ in lastTranslation = nil }
    }

    private var tap: some Gesture {
        SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            // The pointer's own position resolves overlapping proxies the way
            // hovering does; the hit entity is the fallback.
            let hit = scene.portID(at: value.location) ?? scene.portID(of: value.entity)
            guard dragDistance < 4, let id = hit,
                  let port = model.ports.first(where: { $0.id == id })
            else { return }
            guard port.isThunderbolt else {
                onUSBOnlyClick?(port)
                return
            }
            focusedID = id
            scene.setFocus(id)
            let flags = NSEvent.modifierFlags
            if let onExtendClick, flags.contains(.command) || flags.contains(.shift) {
                onExtendClick(port)
                return
            }
            model.select(id)
        }
    }

    // MARK: - Keyboard (§8.3)

    private var thunderboltPorts: [StagePort] { model.ports.filter(\.isThunderbolt) }

    private var firstThunderboltID: StagePort.ID? { thunderboltPorts.first?.id }

    /// ← → move between receptacles in physical order, camera leaning to follow.
    private func moveFocus(by step: Int) -> KeyPress.Result {
        let ports = thunderboltPorts
        guard !ports.isEmpty else { return .ignored }
        let current = ports.firstIndex { $0.id == focusedID } ?? -1
        let next = ports[((current + step) % ports.count + ports.count) % ports.count]
        focusedID = next.id
        scene.setFocus(next.id)
        model.hover(next.id)
        if next.face != model.currentFace { model.turnTo(next.face) }
        return .handled
    }

    /// ↑ ↓ switch faces.
    private func cycleFace(by step: Int) -> KeyPress.Result {
        let faces = model.relevantFaces
        guard faces.count > 1 else { return .ignored }
        let current = faces.firstIndex(of: model.currentFace) ?? 0
        model.turnTo(faces[((current + step) % faces.count + faces.count) % faces.count])
        return .handled
    }

    private func activateFocused() -> KeyPress.Result {
        guard let focusedID else { return .ignored }
        model.select(focusedID)
        return .handled
    }

    // MARK: - Accessibility (§8.2)

    /// §8.2: "Mac Studio, back face. Four Thunderbolt ports."
    private var containerSummary: String {
        let count = model.ports.count { $0.isThunderbolt && $0.face == model.currentFace }
        let name = model.machineName
        let face = Self.faceWord(model.currentFace)
        guard count != 1 else {
            let one: String.LocalizationValue = "\(name), \(face) face. One Thunderbolt port."
            return String(localized: one)
        }
        let spelled = ThisMacPresentation.spelledOut(count)
        let many: String.LocalizationValue =
            "\(name), \(face) face. \(spelled) Thunderbolt ports."
        return String(localized: many)
    }

    /// One element per receptacle, in physical order — the container's order is
    /// the list's order and the machine's order, on every screen.
    private var accessibilityElements: some View {
        VStack(spacing: 0) {
            ForEach(model.ports) { port in
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityLabel(Text(Self.label(for: port)))
                    // §8.2: "Its *value* carries the address when configured."
                    .accessibilityValue(Text(verbatim: port.accessibilityValue ?? ""))
                    .accessibilityAddTraits(port.selected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction {
                        if port.isThunderbolt {
                            model.select(port.id)
                        } else {
                            onUSBOnlyClick?(port)
                        }
                    }
            }
        }
    }

    /// §8.2's element label — position, kind, state and bridge membership.
    ///
    /// Built by `StageModel.apply` from the very `PortRowPresentation` the port
    /// list reads, so the stage and the list can never describe one receptacle
    /// two different ways, and the membership sentence §4.3's whole outer track
    /// depends on is spoken rather than silently dropped.
    private static func label(for port: StagePort) -> String {
        port.accessibilityLabel.isEmpty ? port.positionName : port.accessibilityLabel
    }

    private static func faceWord(_ face: PortFace) -> String {
        let word: String.LocalizationValue = switch face {
        case .back: "back"
        case .front: "front"
        case .left: "left"
        case .right: "right"
        }
        return String(localized: word)
    }
}

/// What forces the scene to be rebuilt rather than merely re-posed.
///
/// Split, because the two halves are owed different things. A change to the
/// machine is a new scene *and* a new camera pose; a change to the appearance
/// rebuilds the same machine in different materials and must leave the camera
/// exactly where the user put it. Reduce Motion and Reduce Transparency are in
/// neither half: they change no geometry and no material at all.
struct StageBuildKey: Equatable {
    struct Geometry: Equatable {
        var archetype: Archetype
        var shape: [String]
    }

    var geometry: Geometry
    var colorScheme: ColorScheme
    /// §3.6 doubles every ring track, which is a mesh.
    var increaseContrast: Bool
}

#Preview("Stage") {
    let model = StageModel()
    model.archetype = .studioSix
    model.machineName = "Mac Studio"
    model.currentFace = .back
    model.ports = [
        StagePort(
            id: "en2", face: .back, physicalIndex: 1, kind: .thunderbolt, link: .empty,
            cfg: .bridge, positionName: "Back, far left"
        ),
        StagePort(
            id: "en3", face: .back, physicalIndex: 2, kind: .thunderbolt, link: .macLinked,
            cfg: .ready, positionName: "Back, middle left"
        ),
        StagePort(
            id: "en4", face: .back, physicalIndex: 3, kind: .thunderbolt, link: .device,
            cfg: .bridge, positionName: "Back, middle right"
        ),
        StagePort(
            id: "en5", face: .back, physicalIndex: 4, kind: .thunderbolt,
            link: .macLinkComingUp, cfg: .drift, positionName: "Back, far right"
        ),
        StagePort(
            id: "en6", face: .front, physicalIndex: 5, kind: .thunderbolt, link: .empty,
            cfg: .outside, positionName: "Front, left"
        ),
        StagePort(
            id: "en7", face: .front, physicalIndex: 6, kind: .thunderbolt, link: .empty,
            cfg: .none, positionName: "Front, right"
        ),
    ]
    model.wake()
    return StageView(model: model).frame(width: 580, height: 600)
}
