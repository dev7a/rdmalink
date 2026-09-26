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
    /// Every kernel bridge this receptacle belongs to, switched on or not.
    /// §4.4's ribbon is drawn between the members of the same bridge, and an
    /// inactive one is drawn at 40 % — so both facts have to reach the stage.
    var bridges: [StageBridge] = []
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
    /// §4.8's callout: the row's detail line, verbatim, from the same
    /// `PortRowPresentation` as the label above. Empty where there is no
    /// snapshot to build one from, and the callout is not shown.
    var calloutDetail = ""
    /// The row's technical line — `en6 · bridge0 · Thunderbolt Bridge` — for
    /// the callout while Show Technical Names is on. Never drawn on the model
    /// itself (§4.7).
    var technicalSuffix: String?

    var isThunderbolt: Bool { kind == .thunderbolt }

    /// §4.8's callout text for this receptacle, or nil while the stage has no
    /// row to quote.
    func callout(showsTechnicalNames: Bool) -> StageCalloutText? {
        guard !calloutDetail.isEmpty else { return nil }
        return StageCalloutText(
            title: positionName, detail: calloutDetail,
            technical: showsTechnicalNames ? technicalSuffix : nil
        )
    }
}

/// One kernel bridge a receptacle belongs to, reduced to what §4.4's ribbon
/// needs: which bridge it is, so members can be tied together, and whether it
/// is in use, so an unused one draws at 40 %.
struct StageBridge: Identifiable, Equatable, Sendable {
    /// The kernel interface name, `bridge0`. Unique within one port's list.
    let id: String
    /// The kernel says this bridge is up and carrying something.
    var isActive: Bool
}

extension StagePort {
    /// The seam with Core. The integrator calls this; nothing in App/Stage does.
    ///
    /// A port whose `face` is nil is one macOS gave no position (§4.7's
    /// "positions unavailable" on a recognized Mac): it is filed under the
    /// back, where the binder finds it a hole only if the chassis has one
    /// there, and drops it otherwise rather than drawing it somewhere invented.
    /// On an unrecognized Mac no chassis is built at all (R31), so the face
    /// is never read.
    init(port: ThunderboltPort, physicalIndex: Int, configuration: Configuration) {
        self.init(
            id: port.id,
            face: port.face ?? .back,
            physicalIndex: physicalIndex,
            kind: port.isThunderbolt ? .thunderbolt : .usbOnly,
            link: port.link,
            cfg: configuration,
            positionName: port.positionName,
            bridges: port.bridges.map { StageBridge(id: $0.name, isActive: $0.isUp) }
        )
    }
}

/// UX_SPEC §6.2 R2: the two receptacles one cable's ends are both in.
///
/// "Both receptacles ring and a single light thread is drawn between them,
/// arcing across the chassis — the one time a thread connects two ports of
/// the same machine." The rings are the ports' own `attention`; this is the
/// thread's pair, in the order the refusal names them.
struct StageLoopedPair: Equatable, Sendable {
    let a: StagePort.ID
    let b: StagePort.ID

    func contains(_ id: StagePort.ID) -> Bool { a == id || b == id }
}

/// UX_SPEC §4.4: which bridge ribbons are drawn, beyond the ones hover and
/// selection raise on their own.
///
/// "The ribbon appears on hover, on selection, throughout review, apply, and
/// restore, and whenever the port list's bridge row is hovered" — the first two
/// the stage knows by itself, and the rest are the screen's business, which is
/// what this value carries.
enum StageRibbons: Equatable, Sendable {
    /// S1 and S4: hover and selection only.
    case automatic
    /// The port list's bridge row is hovered: every member of that one bridge,
    /// by its kernel name.
    case bridge(String)
    /// S5, S6 and S10: the ribbon stays up for the whole screen.
    case all
}

/// UX_SPEC §S4b. The stage's whole part in Identify: which receptacles are
/// listening, and which one answered.
enum StageIdentify: Equatable, Sendable {
    case off
    /// Every eligible receptacle shimmers in phase — *listening*, not
    /// *loading* — and the camera has pulled back to see both faces.
    case watching
    /// An unplug landed: every other shimmer stops dead and this one takes a
    /// steady `.secondary` ring. "The silence around the answer is the
    /// feedback."
    case answered(StagePort.ID)
    /// The cable went back in: the ring blooms to full accent with a single
    /// 8 % scale pulse, and the camera arcs square on.
    case confirmed(StagePort.ID)

    /// The receptacle Identify is talking about, once there is one.
    var id: StagePort.ID? {
        switch self {
        case .off, .watching: nil
        case .answered(let id), .confirmed(let id): id
        }
    }
}

/// UX_SPEC §S5's hover-to-preview: "You can watch each sentence mean something
/// before you agree to it." One case per change row, and each is silent,
/// reversible and writes nothing anywhere.
enum StagePreview: String, Equatable, Sendable, CaseIterable {
    /// **Save how to undo this** — a bookmark glyph at the stage's trailing edge.
    case note
    /// **Leave Thunderbolt Bridge** — this receptacle's ribbon links fade
    /// away and the segmented ring's gaps widen a hair.
    case leaveBridge
    /// **Get its own network service** — a small accent node beside the
    /// receptacle.
    case service
    /// **Turn IPv4 off, IPv6 to link-local** — the node gains a hairline ring.
    case addresses
}

/// One hover-to-preview, and the receptacle whose change row it is.
struct StagePreviewIntent: Equatable, Sendable {
    var kind: StagePreview
    var id: StagePort.ID
}

/// UX_SPEC §S8's handoff: "the ghost second Mac". The camera pulls back and
/// pans so this Mac occupies the leading third of the stage, a featureless
/// rounded box at 40 % slides in from the trailing side with a single thin
/// line from the near port to it, and when the far end answers a pulse
/// travels back along the line and blooms at the near receptacle, once. The
/// ghost never gains detail, ever — it is explicitly *a Mac the app can't
/// see*; the legend names it (§4.8).
struct StageHandoff: Equatable, Sendable {
    /// The receptacle "this link" is on — the near port, which carries the
    /// line. The line is its cable, so no receptacle's thread is drawn and
    /// every other receptacle recedes but a selection
    /// (``StageMoment/dim(for:)``). `nil` when no port qualifies (§S8 "Whose
    /// link"): the ghost still arrives, there is no cable to draw, and
    /// nothing recedes.
    var portID: StagePort.ID?
    /// The face the handoff is staged on: the near port's, or the face in
    /// front when there is no near port.
    var face: PortFace
}

/// What the stage has to draw for this Mac (UX_SPEC §3.4, §6.2 R31).
///
/// The one place the decision lives: the view draws a scene only for
/// ``chassis(_:)``, and every camera intent, narration and selection on the
/// model is refused for the other two, so nothing downstream has to ask
/// whether there is a chassis to turn.
enum StagePicture: Equatable, Sendable {
    /// Nothing is known yet — S0 before this Mac's identity lands. Blank.
    case pending
    /// Neither rule in §4.7 recognizes this Mac. No chassis, no rings, no
    /// chrome: R31's unavailable-content block stands where the model would.
    case unrecognized
    /// A Mac the catalogue can draw.
    case chassis(Chassis)
}

/// A camera move the view has not performed yet.
///
/// The token makes a repeat of the same move a new request: pressing ⌘0 twice
/// must fit twice, and `Equatable` on the kind alone would swallow the second.
struct StageCameraRequest: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// §9.1's turn: the three-quarter pose on that face.
        case turn(PortFace)
        /// §S4b and §S5: square on to the face, with no three-quarter offset.
        case squareOn(PortFace)
        /// §S4b: pull back far enough that a change anywhere will be seen, from
        /// a pose that shows something of every face these receptacles are on.
        case survey([PortFace])
        /// §S8: pull back and pan so this Mac takes the leading third and the
        /// ghost beside it fits.
        case handoff(PortFace)
        /// §S8 is over: the camera comes back to this Mac alone, where it is.
        case endHandoff
        case fit
        case reset
    }

    var kind: Kind
    var token: Int
}

@MainActor
@Observable
final class StageModel {
    /// The chassis to draw, or the reason there is none.
    var picture: StagePicture = .pending
    /// The marketing name, for the accessibility container summary (§8.2).
    var machineName = ""

    /// The chassis, while there is one to draw.
    var chassis: Chassis? {
        if case .chassis(let chassis) = picture { return chassis }
        return nil
    }

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

    // MARK: - The ML2 beats
    //
    // Everything below is an *intent*: a screen says what moment it is in and
    // the stage draws it. None of it is a fact about the Mac — the facts
    // arrive through `ports` — and none of it writes anything anywhere.

    /// §4.4: which bridge ribbons are up, beyond hover and selection.
    var ribbons: StageRibbons = .automatic

    /// §S6 and §S10: how much of a receptacle's segmented ring has closed,
    /// 0…4 gaps. Absent means the ring is whatever ``StagePort/cfg`` says;
    /// present means a real operation is running on that port and the ring is
    /// reporting it.
    private(set) var progress: [StagePort.ID: Int] = [:]

    /// §S4b.
    private(set) var identify: StageIdentify = .off

    /// §S5: the change row the pointer is on, and the receptacle it is about.
    private(set) var preview: StagePreviewIntent?

    /// §S8: the ghost second Mac, while "Now the other Mac" is up.
    private(set) var handoff: StageHandoff?

    /// §6.2 R2: the cable that comes back into this Mac, while S5's checks
    /// are naming it.
    private(set) var loopedPair: StageLoopedPair?

    /// §S4 "After this screen the choice is frozen": on S5, S6 and S7 "no row
    /// and no receptacle is a selection target: clicking one does nothing".
    /// While set, ``select(_:)`` and ``hover(_:)`` refuse every caller — the
    /// model, the list, the keyboard and the menu alike — and the chosen
    /// receptacle alone stays lit. The assistant sets it from its step, so
    /// there is one gate rather than one per surface.
    private(set) var isSelectionFrozen = false
    /// The receptacles the freeze holds: every one the user chose, because
    /// §S4's multi-selection is two chosen ports, not one chosen and one
    /// "other". The model lights one of them; the list dims by this set, so
    /// the second chosen row is never drawn as context under its own
    /// **About to change** badge (§S5).
    private(set) var frozenSelection: Set<StagePort.ID> = []

    private var requestToken = 0
    private var narrationClear: Task<Void, Never>?

    init() {}

    /// Everything the stage draws, as one value.
    ///
    /// The live scene reads the model directly; this is for the second,
    /// off-screen render the review hook takes (App/Stage/StageSnapshot.swift),
    /// which needs the whole moment in one piece because it builds its own
    /// entity graph from scratch.
    func moment(focused: StagePort.ID? = nil) -> StageMoment {
        StageMoment(
            ports: ports, ribbons: ribbons, progress: progress, identify: identify,
            preview: preview, handoff: handoff, loopedPair: loopedPair, focused: focused,
            // Nil while nothing is held, so the moment says "not frozen"
            // rather than "frozen on nothing" — which would fade the whole
            // machine (§S5's 25 %).
            frozenSelection: isSelectionFrozen ? frozenSelection : nil
        )
    }

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
    ///
    /// With no chassis there is nothing a selection could light, so on an
    /// unrecognized Mac the rows take no selection either (§S1, R31).
    func select(_ id: StagePort.ID?) {
        guard !isSelectionFrozen else { return }
        light(id)
    }

    func hover(_ id: StagePort.ID?) {
        guard !isSelectionFrozen else { return }
        guard hoveredID != id else { return }
        for index in ports.indices { ports[index].hovered = ports[index].id == id }
    }

    /// Holds the chosen receptacles and closes the selection to every click
    /// until ``thawSelection()``. The hover glow goes with it: a row that
    /// cannot be picked does not light up under the pointer either (§S4).
    /// One receptacle can be lit at a time, so the first in physical order
    /// — the order S5's sections and S6's writes run in — is the one shown.
    func freezeSelection(on ids: Set<StagePort.ID>) {
        for index in ports.indices { ports[index].hovered = false }
        frozenSelection = ids
        light(ports.first { ids.contains($0.id) }?.id)
        isSelectionFrozen = true
    }

    /// The user is choosing again (S4), or the assistant is gone.
    func thawSelection() {
        isSelectionFrozen = false
        frozenSelection = []
    }

    private func light(_ id: StagePort.ID?) {
        guard chassis != nil else { return }
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

    // MARK: - §S3's attention rings

    /// Ring the receptacles a check names, and stop when it is answered.
    ///
    /// UX_SPEC §S3: "that receptacle takes a 1.5 pt attention ring in
    /// `.secondary` and a single 1.6 s breath". The breath is one dip and back,
    /// not a loop — it starts when a receptacle joins the set and it ends by
    /// itself. Passing the empty set takes every ring away.
    ///
    /// With two Macs connected, both receptacles are named at once and both
    /// ring simultaneously; a faint light thread leaves each of them for as
    /// long as they are ringed, **making the loop visible rather than
    /// described**.
    func attention(ids: Set<StagePort.ID>) {
        for index in ports.indices { ports[index].attention = ids.contains(ports[index].id) }
    }

    /// UX_SPEC §6.2 R2: "both receptacles ring and a single light thread is
    /// drawn between them, arcing across the chassis". The thread is drawn
    /// for exactly two receptacles, in the order R2 names them, and taken
    /// away with anything else — including the empty list.
    func loopedBack(_ ids: [StagePort.ID]) {
        guard ids.count == 2, ids[0] != ids[1],
            ids.allSatisfy({ id in ports.contains { $0.id == id && $0.isThunderbolt } })
        else {
            loopedPair = nil
            return
        }
        loopedPair = StageLoopedPair(a: ids[0], b: ids[1])
    }

    // MARK: - §S6 and §S10: the ring that closes as the work gets done

    /// UX_SPEC §S6: "The selected receptacle's segmented ring **closes its gaps
    /// one by one** as each real step completes, ending as a solid accent
    /// ring."
    ///
    /// Call it as each write lands, never on a timer — §3.5 is explicit that a
    /// stall has to look like a stall. `step` is how many of `total` steps are
    /// done, so `progress(step: 0, of: 5, …)` is the ring the apply screen
    /// opens on and `step == total` is the solid ring.
    ///
    /// In the same beat as the first gap closes, this receptacle's bridge
    /// ribbon detaches and retracts into the other members (§4.4, §9.3).
    func progress(step: Int, of total: Int, for id: StagePort.ID) {
        self.progress[id] = StageMath.closedGaps(step: step, of: total)
    }

    /// §S6 and §9.5: "the same ring re-opens its gaps at the same pace and the
    /// ribbon springs back while the checklist reverses." One call per step the
    /// rollback undoes, which is what keeps the two in step.
    func rollback(for id: StagePort.ID) {
        guard let closed = progress[id] else { return }
        self.progress[id] = max(closed - 1, 0)
    }

    /// §S10: restore is the inverse — "the solid ring **re-opens into the
    /// four-arc segmented ring** and the bridge ribbon springs back out and
    /// reattaches."
    ///
    /// The ring starts solid and opens a gap per completed step, reaching the
    /// ordinary bridge-member shape on the last one. If verification fails,
    /// stop calling: the ring stops half-open and stays that way, which is
    /// exactly what R20's copy says.
    func restoreProgress(step: Int, of total: Int, for id: StagePort.ID) {
        self.progress[id] = 4 - StageMath.closedGaps(step: step, of: total)
    }

    /// Hands the receptacle's outer ring back to ``StagePort/cfg``.
    ///
    /// Called once the operation is over and the re-read has landed — §S7's
    /// solid accent ring and §S10's "settles to the ordinary bridge-member
    /// state" are both states of the port, not of an animation, and the stage
    /// must not keep asserting a progress it is no longer being told about.
    func clearProgress(for id: StagePort.ID) { self.progress[id] = nil }

    func clearAllProgress() { self.progress.removeAll() }

    // MARK: - §S4b: Identify

    /// Every eligible receptacle starts shimmering, in phase, and the camera
    /// pulls back to a pose that shows something of every face they are on.
    ///
    /// The camera move carries no line of its own: §S4b's own headline and
    /// status line are on screen the whole time, and the stage never writes a
    /// sentence (§1.3).
    func startIdentify() {
        identify = .watching
        request(.survey(relevantFaces))
    }

    /// An unplug landed. Every other shimmer stops dead; this receptacle takes
    /// a steady `.secondary` ring.
    func identify(answer id: StagePort.ID) {
        identify = .answered(id)
    }

    /// The cable went back in: the ring blooms to full accent with a single
    /// 8 % scale pulse **on the ring only**, the camera arcs square on, and the
    /// list row selects itself.
    ///
    /// A USB-only receptacle can answer Identify — §S4b has copy for exactly
    /// that. The camera still turns to it, because that is the answer; the ring
    /// and the bloom do not appear, because §4.5 gives a USB-only receptacle no
    /// ring of any kind, and ``select(_:)`` refuses it for the same reason. The
    /// words are the panel's, and it has them.
    func identify(replug id: StagePort.ID) {
        identify = .confirmed(id)
        if let port = ports.first(where: { $0.id == id }) {
            turnSquareOn(to: port.face)
        }
        select(id)
    }

    /// Identify is over — cancelled, timed out, or finished with.
    func stopIdentify() { identify = .off }

    // MARK: - §S5: hover-to-preview

    /// Preview one change row on the model, silently and reversibly. Passing
    /// `nil` takes the preview away; the pointer leaving a row is the whole of
    /// the undo.
    func preview(_ kind: StagePreview?, for id: StagePort.ID) {
        guard let kind else {
            if self.preview?.id == id { self.preview = nil }
            return
        }
        self.preview = StagePreviewIntent(kind: kind, id: id)
    }

    /// Takes any preview off the model, whichever receptacle it was about.
    ///
    /// The pointer leaving a row is the ordinary undo, but the pointer does
    /// not move when the screen is replaced by the keyboard — Return on S5's
    /// footer, with the pointer still on a change row — so the screen going
    /// away has to clear it too. Routing a sentinel id through
    /// ``preview(_:for:)`` cannot: port ids are BSD names and match nothing,
    /// which leaves the bookmark glyph or the widened ring asserting a change
    /// that was already made or abandoned.
    func clearPreview() { preview = nil }

    // MARK: - §S8: the ghost second Mac

    /// "Now the other Mac" is up. The near port is the one §S8 is about and
    /// step 4 names (`OtherMacReport`), or none when no port qualifies (§S8
    /// "Whose link"); the stage turns to its face if it is not in front, then
    /// pulls back and lets the ghost in.
    /// Calling it again with a different port re-aims the line without
    /// starting the handoff over.
    ///
    /// The near port becomes the selection, so the handoff opens with one
    /// lit port and the list agrees with the stage about it (§2.4); a port
    /// the user selects afterwards comes forward as a selection does. It is
    /// set here rather than through ``select(_:)``, whose turn would be a
    /// second camera move on top of the handoff's own.
    func beginHandoff(for id: StagePort.ID?) {
        let face = ports.first { $0.id == id }?.face ?? handoff?.face ?? currentFace
        let intent = StageHandoff(portID: id, face: face)
        guard handoff != intent else { return }
        let wasStaged = handoff?.face
        handoff = intent
        if face != currentFace {
            currentFace = face
            say("Turning the Mac around", showing: face)
        }
        if let id, chassis != nil, !isSelectionFrozen,
           ports.contains(where: { $0.id == id && $0.isThunderbolt }) {
            for index in ports.indices { ports[index].selected = ports[index].id == id }
        }
        if wasStaged != face { request(.handoff(face)) }
    }

    /// The screen is gone; so is the ghost, and the camera comes back to this
    /// Mac without turning it.
    func endHandoff() {
        guard handoff != nil else { return }
        handoff = nil
        request(.endHandoff)
    }

    // MARK: - Camera intents

    /// UX_SPEC §9.1. The line lands first, then the camera moves.
    func turnTo(_ face: PortFace) {
        guard face != currentFace else { return }
        currentFace = face
        say("Turning the Mac around", showing: face)
        request(.turn(face))
    }

    /// §S4b's replug and §S5's review pose: square on to the face, with none of
    /// ``turnTo(_:)``'s three-quarter offset.
    ///
    /// The line is spoken only when the machine really turns round. Squaring up
    /// on the face already in front is a few degrees, and §3.5's rule exists so
    /// that a 180° turn is never a surprise, not so that every nudge is
    /// narrated.
    func turnSquareOn(to face: PortFace) {
        if face != currentFace {
            currentFace = face
            say("Turning the Mac around", showing: face)
        }
        request(.squareOn(face))
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
    /// in front. Never set for the face the user is already looking at — and
    /// never on a Mac with no chassis, where there is no face to show (R31).
    func noteUnseenChange(on face: PortFace) {
        guard chassis != nil, face != currentFace else { return }
        unseenChange = face
    }

    // MARK: - Faces

    /// The faces the selector offers. Hidden entirely when one face is
    /// relevant (§2.3), which the view decides from this being a single value
    /// — and empty with no chassis, where there is no selector at all (R31).
    var relevantFaces: [PortFace] {
        guard let chassis else { return [] }
        let present = ports.reduce(into: [PortFace]()) { faces, port in
            if !faces.contains(port.face) { faces.append(port.face) }
        }
        guard !present.isEmpty else { return chassis.faces }
        return present
    }

    // MARK: - Private

    /// Every camera intent passes through here, and none is raised without a
    /// chassis to move around (§6.2 R31: "no selector, legend, callout or
    /// view buttons", and no "Turning the Mac around" either).
    private func request(_ kind: StageCameraRequest.Kind) {
        guard chassis != nil else { return }
        requestToken += 1
        cameraRequest = StageCameraRequest(kind: kind, token: requestToken)
    }

    /// The panel line and the VoiceOver announcement are posted together so a
    /// VoiceOver user is told exactly what a sighted user is shown (§8.2).
    private func say(_ line: LocalizedStringResource, showing face: PortFace) {
        guard chassis != nil else { return }
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

/// Everything the stage draws at one instant, as a value.
///
/// The live scene reads ``StageModel`` directly and never builds one of these.
/// It exists for the review hook's off-screen render, which builds its own
/// entity graph and so needs the whole moment — the ports, the ribbons, the
/// rings mid-close, Identify and the hover-to-preview — handed to it in one
/// piece (App/Stage/StageSnapshot.swift).
struct StageMoment: Equatable, Sendable {
    var ports: [StagePort] = []
    var ribbons: StageRibbons = .automatic
    var progress: [StagePort.ID: Int] = [:]
    var identify: StageIdentify = .off
    var preview: StagePreviewIntent?
    var handoff: StageHandoff?
    var loopedPair: StageLoopedPair?
    var focused: StagePort.ID?
    /// §S4's frozen choice, as the scene sees it: the receptacles S5, S6 and
    /// S7 hold, or nil while the user is still choosing. See ``dim(for:)``.
    var frozenSelection: Set<StagePort.ID>?
}

extension StageMoment {
    /// §S5's 25 %: "unselected receptacles fade to 25 %, so the scene shows
    /// the subject and its context and nothing else". §S6 keeps it — the
    /// camera is locked and nothing else in the scene moves — and §S7 keeps
    /// it while the configured receptacle holds its solid accent ring. §S8's
    /// handoff recedes every receptacle but the near port and the selection
    /// "to 25 %, its rings and plug with it, as unselected receptacles do on
    /// S5".
    static let frozenDim: Float = 0.25
    /// §4.5: a hovered USB-only receptacle "dims 15 % and that is the whole
    /// answer the model gives".
    static let usbHoverDim: Float = 0.85

    /// How strongly this receptacle is drawn, 0…1, applied to the whole node
    /// so its rings go with it.
    ///
    /// §S3's attention ring outranks §S5's fade. A check that is not satisfied
    /// names a port — "Two Macs are connected, on Back, far left and Back,
    /// middle left" — and §S3 answers by ringing that receptacle and, for two
    /// Macs, running a light thread from each, "making the loop visible rather
    /// than described". Fading the receptacle the user has just been told to
    /// unplug would put out the one light the sentence is pointing at, so a
    /// ringed port is drawn in full however the freeze falls: §S5's 25 % is
    /// about "the subject and its context", and a blocking check's port is
    /// context.
    ///
    /// The freeze comes next because it is the screen's rule rather than one
    /// receptacle's: while it is on, nothing is hovered anyway (``StageModel``
    /// clears and refuses hover for the duration), so the two never argue —
    /// but stating the order here keeps §4.5's hub behaviour and §S5's review
    /// behaviour in one readable place instead of two branches in the scene.
    ///
    /// §S8's handoff is the screen's rule too, and never up during a run: with
    /// a near port, every other receptacle recedes so that "exactly one link
    /// reads — this port to the other Mac". The selection does not: the
    /// handoff opens with the near port selected, and a receptacle the user
    /// selects while it is up — a row, the model, a Port menu item that turns
    /// to it — "comes forward, as a selection does", so the list and the
    /// stage never disagree about the port in hand (§2.4). With no near port,
    /// nothing is singled out and nothing recedes.
    func dim(for port: StagePort) -> Float {
        if port.attention { return 1 }
        if let frozenSelection, !frozenSelection.contains(port.id) { return Self.frozenDim }
        if let near = handoff?.portID, near != port.id, !port.selected { return Self.frozenDim }
        if !port.isThunderbolt, port.hovered { return Self.usbHoverDim }
        return 1
    }

    /// §S8: "The line is that port's cable, so exactly one link reads" —
    /// while the handoff draws its line no receptacle draws its own light
    /// thread (§4.2): not the near port beside the line, and not a linked
    /// neighbour, whose thread at 25 % still reads as a second cable against
    /// the dark appearance's background — nor one the user selects, which
    /// comes forward while its thread stays down. With no near port there is
    /// no line, and every thread stays.
    var handoffHoldsTheOnlyLink: Bool { handoff?.portID != nil }
}
