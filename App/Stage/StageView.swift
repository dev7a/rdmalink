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
    /// §S1: "double-clicking a configurable one … opens Review for it" — a
    /// named run, step 1 of 2. Set by the hub only; `nil` inside a run, where
    /// the picker owns the choice.
    var onDoubleClick: ((StagePort) -> Void)?

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

    // §4.8's callout. Two ways in, one way out: the pointer resting on a
    // receptacle for 300 ms, or keyboard focus landing on one.
    /// The receptacle the pointer is over right now, before the rest.
    @State private var pointerID: StagePort.ID?
    /// The receptacle the pointer has rested on.
    @State private var restedID: StagePort.ID?
    /// The receptacle keyboard focus was moved to (§8.3's ← → and Tab), which
    /// a click clears again: a click is a selection, not a question.
    @State private var keyboardCalloutID: StagePort.ID?
    @State private var rest: Task<Void, Never>?
    /// §4.8: "hidden with View › Hide Legend ⌘K … and the choice is
    /// remembered."
    @AppStorage(AppSettings.showsLegend) private var showsLegend = true
    @AppStorage(AppSettings.showTechnicalNames) private var showsTechnicalNames = false
    /// §S8's `Other Mac:` pop-up, which the window puts on the stage while
    /// that screen is up and the stage is wider than §8.5's strip.
    @Environment(\.otherMacPickerPlace) private var otherMacPickerPlace
    /// What the pop-up measured last, so the callout can stand clear of it.
    @State private var otherMacPickerSize: CGSize?

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
                archetype: model.chassis?.archetype,
                shape: model.ports.map { "\($0.id)|\($0.face.rawValue)|\($0.kind.rawValue)" }
            ),
            colorScheme: colorScheme,
            increaseContrast: contrast == .increased
        )
    }

    var body: some View {
        switch model.picture {
        case .chassis:
            chassisStage
        case .unrecognized:
            // §6.2 R31: no model, and none of the chrome that goes with one —
            // no selector, legend, callout or view buttons. The block stands
            // where the chassis would, in the system's own style.
            StageUnrecognizedView()
        case .pending:
            // S0, before this Mac's identity has landed: nothing to draw yet,
            // and nothing to say about it either.
            Rectangle().fill(.windowBackground)
        }
    }

    /// The stage proper, for a Mac the catalogue can draw.
    private var chassisStage: some View {
        // §8.2's container is the render surface alone. Wrapping the overlays
        // in it too would put `Back`, `Front`, `Fit` and `Reset View` under an
        // `.accessibilityChildren`, which *replaces* what it covers — and §8.7
        // needs "click Back" to find a real element.
        surface
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(containerSummary))
            .accessibilityChildren { accessibilityElements }
            // §2.3's top band: the narration capsule, and §S8's pop-up in the
            // top-trailing corner, which the capsule makes way for.
            .overlay { topBand }
            // §4.8's legend, "shown whenever the rings are live" — with the
            // line that names §S8's ghost while the handoff is up. It stays
            // out of the corner §S8's pop-up holds.
            .overlay {
                if showsLegend {
                    StageLegendOverlay(
                        rows: StageLegend.rows(for: model.ports, handoff: model.handoff),
                        projection: scene.projection,
                        viewport: scene.viewport, appearance: appearance,
                        trailingCornerTaken: showsOtherMacPicker
                    )
                }
            }
            // §4.8's callout, beside the receptacle it is about — and never
            // over §S8's pop-up.
            .overlay(alignment: .topLeading) {
                let port = calloutPort
                StageCalloutOverlay(
                    port: port, showsTechnicalNames: showsTechnicalNames,
                    projection: scene.projection,
                    rowIDs: model.ports.filter { $0.face == port?.face }.map(\.id),
                    receptaclePointSize: scene.receptaclePointSize,
                    viewport: scene.viewport, appearance: appearance,
                    pickerSize: showsOtherMacPicker ? otherMacPickerSize : nil
                )
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
                // §S4: while the choice is frozen there is no receptacle for
                // focus to land on, because none is a selection target.
                focusedID = focused && !model.isSelectionFrozen
                    ? (model.selectedID ?? firstThunderboltID) : nil
                scene.setFocus(focusedID)
                // §4.8: "moving keyboard focus to it shows a small callout".
                // Tab lands on the selected receptacle or the first one, and
                // that is a move too; focus leaving takes the callout with it.
                keyboardCalloutID = focused ? focusedID : nil
            }
            // §S4 "After this screen the choice is frozen": the keyboard is
            // gated like the pointer, so a focus ring that arrived on S4 is
            // taken away rather than left over a port Space can no longer
            // choose, and ← → ↑ ↓ cannot turn the Mac away from the port S5
            // is describing or S6 is working on (§S5, §S6).
            .onChange(of: model.isSelectionFrozen) { _, frozen in
                guard frozen else { return }
                focusedID = nil
                scene.setFocus(nil)
                keyboardCalloutID = nil
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
            // Review hook only: `RDMALINK_SNAPSHOT_CALLOUT` names a receptacle
            // by BSD name and the callout is raised on it as a rested hover
            // would raise it, without the 300 ms nobody is waiting through.
            .onChange(of: model.ports.count, initial: true) { _, count in
                guard count > 0, restedID == nil, let id = SnapshotHook.callout,
                      model.ports.contains(where: { $0.id == id })
                else { return }
                model.hover(id)
                restedID = id
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
                let chassis = model.chassis,
                let image = await StageSnapshot.image(
                    moment: model.moment(focused: scene.focusedID),
                    chassis: chassis,
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
        // Only ever reached from `chassisStage`, which exists for a chassis alone;
        // read fresh rather than captured, so a rebuild draws the Mac the
        // model holds now.
        guard let chassis = model.chassis else { return }
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
                ports: model.ports, chassis: chassis, palette: palette,
                appearance: appearance
            ),
            into: &content,
            keepingPose: scene.installedKey?.geometry == key.geometry
        )
        scene.installedKey = key
    }

    // MARK: - Overlays

    /// §S8's pop-up is on the stage while the window puts it here and the
    /// ghost is up: "it comes and goes with the ghost".
    private var showsOtherMacPicker: Bool {
        otherMacPickerPlace == .stage && model.handoff != nil
    }

    private var topBand: some View {
        StageTopBand {
            StageNarration(line: model.narration, appearance: appearance)
            if showsOtherMacPicker {
                StageOtherMacPicker(appearance: appearance)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: {
                        otherMacPickerSize = $0
                    }
                    .layoutValue(key: StageTopBand.SlotKey.self, value: .picker)
                    // §S8: "it fades in as the ghost arrives and out as the
                    // ghost leaves, over 150 ms, and under Reduce Motion it
                    // simply appears and goes."
                    .transition(.opacity)
            }
        }
        .animation(
            appearance.reduceMotion ? nil : .smooth(duration: 0.15), value: showsOtherMacPicker
        )
    }

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
            if id != pointerID { pointerMoved(to: id) }
        case .ended:
            scene.isPointerInside = false
            model.hover(nil)
            NSCursor.arrow.set()
            pointerMoved(to: nil)
        }
    }

    /// §4.8: "Resting on a receptacle (300 ms, as a tooltip)". The rest is
    /// counted from the pointer arriving over a receptacle, and leaving it —
    /// for another or for nothing — takes the callout away in the same beat
    /// the hover ring goes: "the callout fades with the hover."
    private func pointerMoved(to id: StagePort.ID?) {
        pointerID = id
        rest?.cancel()
        rest = nil
        guard let id else {
            if SnapshotHook.callout == nil { restedID = nil }
            return
        }
        // Already up for the keyboard: the pointer arriving on the same
        // receptacle has nothing to wait for.
        if id == keyboardCalloutID {
            restedID = id
            return
        }
        restedID = nil
        rest = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, pointerID == id else { return }
            restedID = id
        }
    }

    /// The receptacle the callout is about: the rested pointer first, then
    /// keyboard focus — and only while its face is the one in front. §4.8
    /// puts the callout "beside" the receptacle; once the machine has turned
    /// (↑ ↓, ⌘1–⌘4, the face selector, an orbit past the corner) the
    /// receptacle's projected centre is a point on the far side of the
    /// chassis and there is nothing there to be beside. `turnTo` sets
    /// `currentFace` before the arc starts, so a ← → that crosses faces
    /// raises the callout on the new face at once. USB-only receptacles have
    /// a callout too — §4.8 gives them their subtitle — so the kind is not
    /// filtered.
    private var calloutPort: StagePort? {
        guard let id = restedID ?? keyboardCalloutID,
              let port = model.ports.first(where: { $0.id == id }),
              port.face == model.currentFace
        else { return nil }
        return port
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
            // §S4: from S5 on no receptacle is a selection target, and a
            // click does nothing — not R3, not a focus ring, nothing.
            guard !model.isSelectionFrozen else { return }
            guard port.isThunderbolt else {
                onUSBOnlyClick?(port)
                return
            }
            focusedID = id
            scene.setFocus(id)
            keyboardCalloutID = nil
            let flags = NSEvent.modifierFlags
            if let onExtendClick, flags.contains(.command) || flags.contains(.shift) {
                onExtendClick(port)
                return
            }
            model.select(id)
            // The second click of a double-click arrives as its own tap; the
            // event's count is what tells the two apart (§S1 3D behavior).
            if NSApp.currentEvent?.clickCount == 2 { onDoubleClick?(port) }
        }
    }

    // MARK: - Keyboard (§8.3)

    private var thunderboltPorts: [StagePort] { model.ports.filter(\.isThunderbolt) }

    private var firstThunderboltID: StagePort.ID? { thunderboltPorts.first?.id }

    /// ← → move between receptacles in physical order, camera leaning to follow.
    /// Ignored while the choice is frozen (§S4): no receptacle is a target,
    /// and the camera stays square on the face the review is about (§S5).
    private func moveFocus(by step: Int) -> KeyPress.Result {
        guard !model.isSelectionFrozen else { return .ignored }
        let ports = thunderboltPorts
        guard !ports.isEmpty else { return .ignored }
        let current = ports.firstIndex { $0.id == focusedID } ?? -1
        let next = ports[((current + step) % ports.count + ports.count) % ports.count]
        focusedID = next.id
        scene.setFocus(next.id)
        model.hover(next.id)
        keyboardCalloutID = next.id
        if next.face != model.currentFace { model.turnTo(next.face) }
        return .handled
    }

    /// ↑ ↓ switch faces. The callout goes with the face it was on: the
    /// keyboard one is cleared outright, and a rest timer still counting
    /// toward a pointer callout is cancelled rather than left to raise one
    /// on a receptacle that has just turned away.
    private func cycleFace(by step: Int) -> KeyPress.Result {
        // §S6: "the camera is locked for the duration so the eye has one
        // place to be" — and the same key is gated the same way on S5 and
        // S7, where the freeze is on for the same reason.
        guard !model.isSelectionFrozen else { return .ignored }
        let faces = model.relevantFaces
        guard faces.count > 1 else { return .ignored }
        let current = faces.firstIndex(of: model.currentFace) ?? 0
        keyboardCalloutID = nil
        restedID = nil
        rest?.cancel()
        rest = nil
        model.turnTo(faces[((current + step) % faces.count + faces.count) % faces.count])
        return .handled
    }

    private func activateFocused() -> KeyPress.Result {
        // Ignored rather than silently dead: `select` would refuse anyway,
        // but a key that reports itself handled swallows the press (§S4).
        guard !model.isSelectionFrozen, let focusedID else { return .ignored }
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
    ///
    /// **Owed:** §8.2's custom actions. Each element has only its default
    /// action, which selects. §8.2 gives it **Select**, **Show Me**, and the
    /// row's own buttons by their titles without the ellipsis — built from
    /// `PortRowPresentation.actions`, filtered by `HubFooterModel.offers` and
    /// unavailable by `allows`, so the stage and the list cannot offer one
    /// port two different ways.
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
                        // §S4: the freeze covers every input, VoiceOver
                        // included — no R3 for a USB-only receptacle either.
                        guard !model.isSelectionFrozen else { return }
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

// MARK: - §4.8's overlays

/// The legend in the top-leading corner — or the top-trailing one while the
/// chassis reaches under the leading one: "It never overlaps a receptacle: it
/// yields to the model by moving to the top-trailing corner when the chassis
/// reaches under it and that corner is clear." The two positions cross-fade
/// (§3.5's state change).
///
/// A view of its own so that only this re-lays out when the projection moves
/// under a camera arc, not the whole stage.
private struct StageLegendOverlay: View {
    let rows: [StageLegendRow]
    let projection: StageProjection
    let viewport: CGSize
    let appearance: StageAppearance
    /// §4.8: "while §S8's `Other Mac:` pop-up holds that corner the legend
    /// stays where it is, and the handoff has pulled this Mac back into the
    /// leading third, clear of it."
    let trailingCornerTaken: Bool

    @State private var size = CGSize.zero

    private static let inset: CGFloat = 12
    /// A little daylight before the legend gives way, so it moves for a
    /// chassis coming under it and not for one merely passing close.
    private static let clearance: CGFloat = 6

    var body: some View {
        ZStack {
            if !rows.isEmpty {
                if yields {
                    legend
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .transition(.opacity)
                } else {
                    legend
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.opacity)
                }
            }
        }
        .animation(appearance.reduceMotion ? nil : .smooth(duration: 0.15), value: yields)
        // §S8's line comes and goes with the ghost, on §3.5's cross-fade.
        .animation(appearance.reduceMotion ? nil : .smooth(duration: 0.15), value: rows)
        .allowsHitTesting(false)
    }

    private var legend: some View {
        StageLegendView(rows: rows)
            .padding(Self.inset)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
    }

    /// True when the chassis's projected bounds reach the legend's resting
    /// place and leave the top-trailing corner clear. The chassis's projected
    /// bounds are the box's whole axis-aligned extent, nearly the stage's
    /// width at the resting pose, so a box high enough to reach one top
    /// corner can reach both; moving then would swap one overlap for
    /// another, and the legend stays where §4.8 puts it. The legend's own
    /// size is what it measured last, so the first frame decides from an
    /// empty rectangle and the next one corrects it.
    private var yields: Bool {
        guard !trailingCornerTaken, let chassis = projection.chassisBounds, size != .zero
        else { return false }
        let leading = CGRect(origin: .zero, size: size)
            .insetBy(dx: -Self.clearance, dy: -Self.clearance)
        let trailing = CGRect(origin: CGPoint(x: viewport.width - size.width, y: 0), size: size)
            .insetBy(dx: -Self.clearance, dy: -Self.clearance)
        return chassis.intersects(leading) && !chassis.intersects(trailing)
    }
}

/// The callout beside the receptacle the pointer rested on or the keyboard
/// focused: to its trailing side, or its leading side when there is no room,
/// and never over it. It fades in and out over 150 ms (§3.5) and a change
/// of receptacle cross-fades.
private struct StageCalloutOverlay: View {
    let port: StagePort?
    let showsTechnicalNames: Bool
    let projection: StageProjection
    /// The receptacles on the same face as `port` — its row, which the
    /// callout stands clear of as a whole.
    let rowIDs: [StagePort.ID]
    /// How wide the receptacle's collider reads right now, in points — what
    /// the callout stands clear of.
    let receptaclePointSize: Double
    let viewport: CGSize
    let appearance: StageAppearance
    /// §S8's `Other Mac:` pop-up, while it is on the stage: its size, in the
    /// top-trailing corner `StageMath.topBand` puts it in. "It never covers
    /// §S8's `Other Mac:` pop-up" (§4.8).
    let pickerSize: CGSize?

    @State private var size = CGSize.zero

    private static let gap: CGFloat = 8
    private static let margin: CGFloat = 8

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let port, let text = port.callout(showsTechnicalNames: showsTechnicalNames),
               let centre = projection.receptacles[port.id] {
                StageCalloutView(text: text, appearance: appearance)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                    .offset(origin(beside: centre))
                    .id(port.id)
                    .transition(.opacity)
            }
        }
        .animation(appearance.reduceMotion ? nil : .smooth(duration: 0.15), value: port?.id)
        .allowsHitTesting(false)
    }

    /// Beside the receptacle: to its trailing side when that fits and its
    /// leading side otherwise, and above it — the callout's bottom edge at
    /// the top of the receptacle's *row* — so a row of receptacles stays in
    /// view under it, falling below the row when there is no room above — or
    /// when the place above would reach §S8's pop-up (§4.8).
    ///
    /// The row, not the one receptacle: a Mac Studio's back row recedes in
    /// perspective, so the receptacles beside the hovered one sit higher on
    /// screen than its own centre, and a callout stood off from that centre
    /// alone lands on their rings. The stand-off is the collider's half
    /// width plus a gap, which the hover ring — the widest, 1.85 cm on a
    /// 1.6 cm collider — stays inside. The horizontal stand-off alone keeps
    /// it off the receptacle itself, whichever way the vertical placement
    /// goes.
    private func origin(beside centre: CGPoint) -> CGSize {
        let standoff = CGFloat(receptaclePointSize) / 2 + Self.gap
        var x = centre.x + standoff
        if x + size.width > viewport.width - Self.margin {
            x = max(centre.x - standoff - size.width, Self.margin)
        }
        // The same face's receptacles near this one's height. No chassis in
        // the catalogue stacks two rows on one face, so the band only keeps a
        // receptacle the camera has carried far above or below from
        // deciding for one it is nowhere near.
        let row = rowIDs.compactMap { projection.receptacles[$0] }
            .filter { abs($0.y - centre.y) < standoff * 2 }
        let top = row.map(\.y).min() ?? centre.y
        let bottom = row.map(\.y).max() ?? centre.y
        var y = top - standoff - size.height
        if y < Self.margin || reachesPicker(CGRect(x: x, y: y, width: size.width, height: size.height)) {
            y = min(bottom + standoff, max(viewport.height - size.height - Self.margin, Self.margin))
        }
        return CGSize(width: x, height: y)
    }

    /// True when `frame` comes within the callout's own margin of §S8's
    /// pop-up.
    private func reachesPicker(_ frame: CGRect) -> Bool {
        guard let pickerSize,
              let origin = StageMath.topBand(
                  width: viewport.width, narration: .zero, picker: pickerSize
              ).picker
        else { return false }
        return frame.intersects(
            CGRect(origin: origin, size: pickerSize).insetBy(dx: -Self.margin, dy: -Self.margin)
        )
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
        /// The chassis being drawn. `nil` never reaches the builder: the stage
        /// draws no scene without one (R31).
        var archetype: Archetype?
        var shape: [String]
    }

    var geometry: Geometry
    var colorScheme: ColorScheme
    /// §3.6 doubles every ring track, which is a mesh.
    var increaseContrast: Bool
}

/// UX_SPEC §6.2 R31's stage: "In its place, centred, an unavailable-content
/// block in the system's own style." Verbatim, symbol included, and nothing
/// floating over it.
struct StageUnrecognizedView: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.windowBackground)
            ContentUnavailableView(
                "No picture for this Mac",
                systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                description: Text("RDMALink doesn't recognize it, so it won't draw one.")
            )
        }
    }
}

#Preview("Stage") {
    let model = StageModel()
    model.picture = ReceptacleCatalogue.chassis(for: .studioSix).map(StagePicture.chassis) ?? .pending
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
