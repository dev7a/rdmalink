//
//  IdentifySession.swift
//
//  S4b — Identify a port (UX_SPEC §S4b). The one thing nothing on screen can
//  resolve — which physical socket holds the cable in your hand — answered by
//  the hardware.
//
//  Read-only. It needs no password, it is always available, and it answers
//  about **this** Mac only, using this Mac's own events, so it cannot be
//  confused by the identical twin on the shelf.
//
//  Detection is two-beat and belt-and-braces. Beat one is any receptacle
//  transitioning away from device-present; beat two is any receptacle
//  transitioning back. **Beat one alone is already a usable answer and is
//  reported immediately.** The observations arrive from the window's live
//  read — Core's `LinkWatcher` with the one-second state diff running
//  underneath it — so a dock that never raises an event is caught by the diff
//  and the success state is identical whichever detector saw it.
//

import Foundation
import Observation
import RDMALinkCore

/// The receptacle Identify is talking about.
struct IdentifiedPort: Sendable, Equatable, Identifiable {
    var id: String
    var positionName: String
    var isThunderbolt: Bool
}

/// One observation of one receptacle. The session never sees a `PortSnapshot`,
/// so it can be driven from a test with three lines of values.
struct IdentifyObservation: Sendable, Equatable {
    var id: String
    var positionName: String
    var isThunderbolt: Bool
    /// `true` while something is in the receptacle, whatever it is.
    var isOccupied: Bool

    init(id: String, positionName: String, isThunderbolt: Bool, isOccupied: Bool) {
        self.id = id
        self.positionName = positionName
        self.isThunderbolt = isThunderbolt
        self.isOccupied = isOccupied
    }

    init(_ snapshot: PortSnapshot) {
        self.init(
            id: snapshot.id,
            positionName: snapshot.port.positionName,
            isThunderbolt: snapshot.port.isThunderbolt,
            isOccupied: snapshot.port.link != .empty)
    }
}

@MainActor
@Observable
final class IdentifySession {
    /// Where the watch has got to.
    enum Outcome: Sendable, Equatable {
        case watching
        /// Beat one. Already usable: the user can walk away with this.
        case unplugged(IdentifiedPort)
        /// Beat two.
        case replugged(IdentifiedPort)
        /// Two receptacles changed within the same ~400 ms.
        case ambiguous
        /// The receptacle that moved carries USB, not Thunderbolt.
        case usbOnly(IdentifiedPort)
        /// Sixty seconds, nothing seen.
        case timedOut
    }

    /// Two receptacles changing inside this window is not an answer.
    static let ambiguityWindow: Duration = .milliseconds(400)
    /// "Still waiting for it to come back. Take your time."
    static let nudgeAfter = IdentifyClock.nudgeAfter
    /// "I didn't see anything change."
    static let timeoutAfter = IdentifyClock.timeoutAfter

    private(set) var outcome: Outcome = .watching
    /// True once an unplug has been waiting thirty seconds for its replug.
    private(set) var showsNudge = false
    /// How many receptacles are being watched, for the status line.
    private(set) var watchedCount = 0
    /// VoiceOver hears every detection: "Cable removed from Back, far right",
    /// "Found Back, far right" (§8.2). The view posts and clears it.
    private(set) var announcement: String?

    /// The selection S4 had when Identify started, restored on cancel.
    let previousSelection: Set<String>
    /// The position name that selection had, for the USB-only copy.
    private let previousPositionName: String?

    private var occupancy: [String: Bool] = [:]
    private var names: [String: IdentifiedPort] = [:]
    private var startedAt: ContinuousClock.Instant
    private var unpluggedAt: ContinuousClock.Instant?
    private var lastChangeAt: ContinuousClock.Instant?
    private let clock = ContinuousClock()

    init(previousSelection: Set<String> = [], previousPositionName: String? = nil) {
        self.previousSelection = previousSelection
        self.previousPositionName = previousPositionName
        self.startedAt = ContinuousClock().now
    }

    // MARK: - Copy

    static let headline: LocalizedStringResource = "Unplug it and plug it back in"
    static let body: LocalizedStringResource =
        "Take the cable out of the port you want to use, wait a moment, then put it back. I'll watch every port and light up the one that moved."
    static let replugHeadline: LocalizedStringResource = "That's the one"
    static let nudge: LocalizedStringResource =
        "Still waiting for it to come back. Take your time."
    static let ambiguousHeadline: LocalizedStringResource =
        "Two ports changed at the same moment"
    static let ambiguousBody: LocalizedStringResource =
        "I'd only be guessing which one you meant, and I'd rather not. Let's try again — one cable at a time."
    static let usbHeadline: LocalizedStringResource = "That's a USB port"
    static let timeoutHeadline: LocalizedStringResource = "I didn't see anything change"
    static let timeoutBody: LocalizedStringResource =
        "Some devices don't announce themselves, and an empty port has nothing to announce. Pick a port from the list instead — or try again with a Mac on the other end."

    /// §S4b writes the count in words for six, four and three. Any other
    /// machine takes the digit in the same sentence. **Owed from the spec
    /// owner:** the remaining counts.
    var statusLine: LocalizedStringResource? {
        switch outcome {
        case .watching:
            switch watchedCount {
            case 6: return "Watching all six ports…"
            case 4: return "Watching all four ports…"
            case 3: return "Watching all three ports…"
            default: return "Watching all \(watchedCount) ports…"
            }
        case let .unplugged(port):
            return "Got it — that's \(port.positionName). Plug it back in whenever you're ready."
        case .replugged, .ambiguous, .usbOnly, .timedOut:
            return nil
        }
    }

    /// The body for the state the session is in, when it has one of its own.
    var currentBody: LocalizedStringResource {
        switch outcome {
        case .watching, .unplugged:
            return Self.body
        case let .replugged(port):
            return "\(port.positionName). If that's not what you expected, try again — no harm done."
        case .ambiguous:
            return Self.ambiguousBody
        case let .usbOnly(port):
            // The spec's sentence contrasts the port the user had in mind with
            // the one that actually moved. Without a previous selection there
            // is nothing to contrast, so R3's own body stands in.
            guard let previousPositionName else {
                return "The front ports on this Mac carry USB, not Thunderbolt. Move the cable to one of the four Thunderbolt ports on the back and I'll follow along."
            }
            return "\(previousPositionName) isn't it — that's \(port.positionName), and the front ports on this Mac carry USB, not Thunderbolt. Try one of the ports on the back."
        case .timedOut:
            return Self.timeoutBody
        }
    }

    var currentHeadline: LocalizedStringResource {
        switch outcome {
        case .watching, .unplugged: Self.headline
        case .replugged: Self.replugHeadline
        case .ambiguous: Self.ambiguousHeadline
        case .usbOnly: Self.usbHeadline
        case .timedOut: Self.timeoutHeadline
        }
    }

    /// The contextual default button, which appears only once there is an
    /// answer. `Cancel` is always there and is the view's to draw.
    var defaultAction: WizardAction? {
        switch outcome {
        case .watching: nil
        case .unplugged, .replugged: .useThisPort
        case .ambiguous, .usbOnly: .identifyAgain
        case .timedOut: .pickFromTheList
        }
    }

    /// The receptacle the answer names, when there is one.
    var identified: IdentifiedPort? {
        switch outcome {
        case let .unplugged(port), let .replugged(port), let .usbOnly(port): port
        case .watching, .ambiguous, .timedOut: nil
        }
    }

    // MARK: - Watching

    /// One observation of every receptacle. Call it on every live read.
    ///
    /// The first call seeds the baseline and decides nothing: a session that
    /// answered on its own first sample would answer about the world before
    /// the user touched it.
    func observe(_ ports: [IdentifyObservation], now: ContinuousClock.Instant? = nil) {
        let instant = now ?? clock.now
        watchedCount = ports.count
        for port in ports {
            names[port.id] = IdentifiedPort(
                id: port.id, positionName: port.positionName, isThunderbolt: port.isThunderbolt)
        }
        guard !occupancy.isEmpty else {
            occupancy = Dictionary(ports.map { ($0.id, $0.isOccupied) }, uniquingKeysWith: { a, _ in a })
            return
        }
        let changed = ports.filter { occupancy[$0.id] != nil && occupancy[$0.id] != $0.isOccupied }
        occupancy = Dictionary(ports.map { ($0.id, $0.isOccupied) }, uniquingKeysWith: { a, _ in a })
        guard !changed.isEmpty else {
            tick(instant)
            return
        }
        // Two receptacles inside the same beat is not an answer.
        if changed.count > 1 {
            becomeAmbiguous()
            return
        }
        if let last = lastChangeAt, instant - last < Self.ambiguityWindow,
            case .watching = outcome {
            becomeAmbiguous()
            return
        }
        lastChangeAt = instant
        resolve(changed[0], at: instant)
    }

    /// Advances the two clocks when nothing changed.
    ///
    /// Called from the view that owns the session, once a second, because the
    /// observations only arrive when a cable moves — and the whole point of
    /// both deadlines is what happens when none does.
    func tick(_ now: ContinuousClock.Instant? = nil) {
        let instant = now ?? clock.now
        let waiting: Duration? = {
            guard let unpluggedAt, case .unplugged = outcome else { return nil }
            return instant - unpluggedAt
        }()
        switch IdentifyClock.tick(watchingFor: instant - startedAt, unpluggedFor: waiting) {
        case .keepWatching:
            if waiting != nil { showsNudge = false }
        case .nudge:
            showsNudge = true
        case .timedOut:
            if case .watching = outcome { outcome = .timedOut }
        }
    }

    /// `Identify Again`, and the way out of every dead end this screen has.
    func restart() {
        outcome = .watching
        showsNudge = false
        occupancy = [:]
        unpluggedAt = nil
        lastChangeAt = nil
        startedAt = clock.now
    }

    func announcementDelivered() { announcement = nil }

    // MARK: - Private

    private func resolve(_ observation: IdentifyObservation, at instant: ContinuousClock.Instant) {
        guard let port = names[observation.id] else { return }
        // A USB-only receptacle answers the question and then says it is the
        // wrong answer, which is more useful than refusing to look.
        guard port.isThunderbolt else {
            outcome = .usbOnly(port)
            showsNudge = false
            announcement = String(localized: "Found \(port.positionName)")
            return
        }
        if observation.isOccupied {
            // Beat two, or a first sample that was already a replug.
            outcome = .replugged(port)
            showsNudge = false
            announcement = String(localized: "Found \(port.positionName)")
        } else {
            outcome = .unplugged(port)
            unpluggedAt = instant
            showsNudge = false
            announcement = String(localized: "Cable removed from \(port.positionName)")
        }
    }

    private func becomeAmbiguous() {
        outcome = .ambiguous
        showsNudge = false
        unpluggedAt = nil
    }
}
