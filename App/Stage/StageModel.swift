//
//  StageModel.swift
//
//  What the stage draws and what it is allowed to say. The window owns one of
//  these; `StageView` renders it and posts intents back into it, and the port
//  list in the assistant column reads and writes the same selection, which is
//  what makes the mapping live in both directions (UX_SPEC §2.4).
//
//  No RealityKit type appears here. Camera moves are requests the view picks
//  up, so the model stays a plain value graph that anything can drive.
//

import Foundation
import Observation
import RDMALinkCore

/// One receptacle on the stage.
///
/// `link` is the inner, hardware track (§4.2) and `cfg` the outer,
/// configuration track (§4.3). They are never conflated, here or on the model.
struct StagePort: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable, Equatable { case thunderbolt, usbOnly }

    /// UX_SPEC §4.3's five outer-track states.
    enum Configuration: Sendable, Equatable {
        /// A member of at least one kernel bridge — the segmented ring.
        case bridge
        /// Out of every bridge, with no service of its own — no outer ring.
        case none
        /// Ready for RDMA — the solid accent ring.
        case ready
        /// Set up outside RDMALink — the double hairline.
        case outside
        /// The service went away, or the port is back in a bridge — dashed.
        case drift
    }

    /// The `ThunderboltPort` id: the BSD name, stable across replugs.
    let id: String
    var face: PortFace
    /// 1-based, in physical order across the whole machine (§2.3, §8.2).
    var physicalIndex: Int
    var kind: Kind
    var link: LinkState
    var cfg: Configuration
    /// The physical position name from §4.7, for the accessibility element.
    /// Never drawn on the model — no text ever is (§4.7).
    var positionName: String
    var selected = false
    var hovered = false
    /// §S3: a check that names a port gives it an attention ring and one breath.
    var attention = false
    /// §8.2's element label, built from the same `PortRowPresentation` the port
    /// list reads so the stage and the list never describe a receptacle two
    /// ways. Empty only where there is no snapshot to build one from.
    var accessibilityLabel = ""
    /// §8.2: "Its *value* carries the address when configured."
    var accessibilityValue: String?

    var isThunderbolt: Bool { kind == .thunderbolt }
}

extension StagePort {
    /// The seam with Core. The integrator calls this; nothing in App/Stage does.
    ///
    /// A port whose `face` is nil is on an unrecognized Mac, where the generic
    /// box has one face and the physical order is whatever macOS reported.
    init(port: ThunderboltPort, physicalIndex: Int, configuration: Configuration) {
        self.init(
            id: port.id,
            face: port.face ?? .back,
            physicalIndex: physicalIndex,
            kind: port.isThunderbolt ? .thunderbolt : .usbOnly,
            link: port.link,
            cfg: configuration,
            positionName: port.positionName
        )
    }
}

/// A camera move the view has not performed yet.
///
/// The token makes a repeat of the same move a new request: pressing ⌘0 twice
/// must fit twice, and `Equatable` on the kind alone would swallow the second.
struct StageCameraRequest: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case turn(PortFace)
        case fit
        case reset
    }

    var kind: Kind
    var token: Int
}

@MainActor
@Observable
final class StageModel {
    var archetype: Archetype = .unknown
    /// The marketing name, for the accessibility container summary (§8.2).
    var machineName = ""

    /// Every receptacle, in physical order. The order is the list's order and
    /// the VoiceOver container's order; it never changes for a redraw (§2.3).
    var ports: [StagePort] = []

    /// Which face the camera is showing. The face selector reads it; the
    /// camera writes it as it turns past the quarter (§2.3).
    var currentFace: PortFace = .back {
        didSet { if currentFace == unseenChange { unseenChange = nil } }
    }

    /// §S1 and §7.4: a port changed state on a face nobody is looking at. The
    /// face selector's other segment takes an accent dot and the working area
    /// offers one inline line with `Show Me` — the only camera move the app
    /// ever makes unasked, and it is asked. Cleared the moment that face comes
    /// to the front.
    private(set) var unseenChange: PortFace?

    /// The narration capsule. Every value is verbatim from UX_SPEC; the stage
    /// never writes a sentence of its own (§1.3).
    private(set) var narration: LocalizedStringResource?

    /// What VoiceOver should be told about the last camera move (§8.2). The
    /// view posts it and clears it.
    private(set) var announcement: String?

    private(set) var cameraRequest: StageCameraRequest?

    /// Bumped once when the probe finishes, to run the waking-ports beat (§9.2).
    private(set) var wakeToken = 0

    private var requestToken = 0
    private var narrationClear: Task<Void, Never>?

    init() {}

    // MARK: - Selection

    /// The single source of truth is the port array, so a row and a receptacle
    /// can never disagree about what is selected.
    var selectedID: StagePort.ID? {
        get { ports.first(where: \.selected)?.id }
        set { select(newValue) }
    }

    var hoveredID: StagePort.ID? {
        get { ports.first(where: \.hovered)?.id }
        set { hover(newValue) }
    }

    var selectedPort: StagePort? { ports.first(where: \.selected) }
    var hoveredPort: StagePort? { ports.first(where: \.hovered) }

    /// USB-only receptacles are never selectable (§4.5): the model refuses
    /// before the panel has to explain. Clicking one is the panel's business.
    func select(_ id: StagePort.ID?) {
        guard id == nil || ports.first(where: { $0.id == id })?.isThunderbolt == true else {
            return
        }
        // The face check comes first. Selecting the row that is *already*
        // selected is how a user brings a receptacle back after ⌘1 turned the
        // machine away from it, and an early return on "nothing changed" makes
        // that a dead click at the one moment §2.4 exists to cover.
        if let face = ports.first(where: { $0.id == id })?.face, face != currentFace {
            turnTo(face)
        }
        guard selectedID != id else { return }
        for index in ports.indices { ports[index].selected = ports[index].id == id }
    }

    func hover(_ id: StagePort.ID?) {
        guard hoveredID != id else { return }
        for index in ports.indices { ports[index].hovered = ports[index].id == id }
    }

    /// §S3: ring the receptacles a check names, and stop when it is answered.
    func setAttention(_ ids: Set<StagePort.ID>) {
        for index in ports.indices { ports[index].attention = ids.contains(ports[index].id) }
    }

    // MARK: - Camera intents

    /// UX_SPEC §9.1. The line lands first, then the camera moves.
    func turnTo(_ face: PortFace) {
        guard face != currentFace else { return }
        currentFace = face
        say("Let me turn it around", showing: face)
        request(.turn(face))
    }

    func fit() { request(.fit) }

    /// ⇧⌘0. Back to the resting pose, silently: the spec gives the stage no
    /// sentence for this move, and the stage does not write its own.
    func reset() { request(.reset) }

    /// Called by the view once it has applied a request.
    func cameraRequestHandled() { cameraRequest = nil }

    /// Called by the view once it has posted the announcement.
    func announcementDelivered() { announcement = nil }

    /// Called when the first probe finishes (§9.2). Once per launch.
    func wake() { wakeToken += 1 }

    /// §7.4's `Show Me`: turn to the face that changed and clear the notice.
    func showUnseenChange() {
        guard let face = unseenChange else { return }
        unseenChange = nil
        turnTo(face)
    }

    /// Called by `apply(_:)` when a re-read moved a port on a face that is not
    /// in front. Never set for the face the user is already looking at.
    func noteUnseenChange(on face: PortFace) {
        guard face != currentFace else { return }
        unseenChange = face
    }

    // MARK: - Faces

    /// The faces the selector offers. Hidden entirely when one face is
    /// relevant (§2.3), which the view decides from this being a single value.
    var relevantFaces: [PortFace] {
        let present = ports.reduce(into: [PortFace]()) { faces, port in
            if !faces.contains(port.face) { faces.append(port.face) }
        }
        guard !present.isEmpty else {
            return ReceptacleCatalogue.chassis(for: archetype).faces
        }
        return present
    }

    // MARK: - Private

    private func request(_ kind: StageCameraRequest.Kind) {
        requestToken += 1
        cameraRequest = StageCameraRequest(kind: kind, token: requestToken)
    }

    /// The panel line and the VoiceOver announcement are posted together so a
    /// VoiceOver user is told exactly what a sighted user is shown (§8.2).
    private func say(_ line: LocalizedStringResource, showing face: PortFace) {
        narration = line
        announcement = Self.announcement(for: face)
        narrationClear?.cancel()
        narrationClear = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            self?.narration = nil
        }
    }

    /// UX_SPEC §8.2 gives "Turning the Mac around. Now showing the back." The
    /// other three faces reuse the sentence with the face names §2.3 uses for
    /// the port-list headers, lowercased mid-sentence.
    private static func announcement(for face: PortFace) -> String {
        let showing: String.LocalizationValue = switch face {
        case .back: "Turning the Mac around. Now showing the back."
        case .front: "Turning the Mac around. Now showing the front."
        case .left: "Turning the Mac around. Now showing the left side."
        case .right: "Turning the Mac around. Now showing the right side."
        }
        return String(localized: showing)
    }
}
