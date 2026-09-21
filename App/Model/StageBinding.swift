//
//  StageBinding.swift
//
//  The seam between the window's inventory and the 3D stage (UX_SPEC §2.4).
//
//  `InventoryModel` is the one source of truth about this Mac; `StageModel` is
//  the one source of truth about what is selected. This file is the only place
//  the first is turned into the second; the one answer to "what ring is this
//  receptacle wearing" is `StagePort.Configuration.init(_:)` in
//  App/Stage/StageLegend.swift, where the legend reads it too.
//

import Foundation
import RDMALinkCore
import SwiftUI

/// Everything the stage is drawn from, in one comparable value.
///
/// The stage is re-derived when — and only when — this changes, which keeps a
/// one-second state diff that observed nothing from touching the scene.
struct StageInput: Equatable {
    var hardware: HardwareModel?
    var ports: [PortSnapshot]
    /// Which screen the port list is drawing (§S4). It belongs in here because
    /// the callout and the accessibility strings below are the row's own words
    /// and change with it — so the stage is re-derived when the step changes,
    /// exactly as it is when a cable moves.
    var mode: PortRowMode = .status
}

extension StageModel {
    /// Mirrors the window's inventory onto the stage without disturbing what
    /// the user is pointing at: selection and hover survive a re-read, because
    /// a link event two seconds into reading a row must not move the row.
    ///
    /// The physical index is the port's rank in the list Core reported, which
    /// is physical order across the whole machine — the same number the wake
    /// beat staggers on and the same order VoiceOver walks (§2.3, §9.2).
    func apply(_ input: StageInput) {
        // §3.4 and §6.2 R31: a Mac the catalogue cannot draw gets no stand-in.
        // `chassis(for:)` is nil exactly when neither rule in §4.7 recognized
        // it, and that is the whole of the stage's read-only mode.
        picture = switch input.hardware {
        case nil: .pending
        case let hardware?:
            ReceptacleCatalogue.chassis(for: hardware.archetype).map(StagePicture.chassis)
                ?? .unrecognized
        }
        machineName = input.hardware?.marketingName ?? ""

        let selected = selectedID
        let hovered = hoveredID
        let attention = Set(ports.filter(\.attention).map(\.id))
        // §7.4: what each receptacle was doing before this read, so a change on
        // a face nobody is looking at can be noticed rather than redrawn in
        // silence. Empty on the first read, when everything is "new".
        let before = Dictionary(
            ports.map { ($0.id, ($0.link, $0.cfg)) }, uniquingKeysWith: { first, _ in first }
        )

        ports = input.ports.enumerated().map { index, snapshot in
            var port = StagePort(
                port: snapshot.port,
                physicalIndex: index + 1,
                configuration: StagePort.Configuration(snapshot)
            )
            // §4.5 again, from the other side: a USB-only receptacle cannot be
            // selected, so it cannot stay selected across a re-read either.
            port.selected = port.isThunderbolt && port.id == selected
            port.hovered = port.id == hovered
            // §S3 and §6.2 R3's recovery: an attention ring is a beat the app
            // is in the middle of, not a fact about the port, so a one-second
            // state diff must not wipe it half way through.
            port.attention = attention.contains(port.id)
            // §8.2: the stage speaks with the port list's voice, not its own —
            // and §4.8's callout quotes the same row, verbatim. Including on
            // §S4, where the row says why a receptacle cannot be chosen rather
            // than what it is: two answers about one port on the one screen
            // where the difference is the point would be the worst place to
            // have them (§2.4).
            let presentation = PortRowPresentation(snapshot: snapshot, mode: input.mode)
            port.accessibilityLabel = presentation.accessibilityLabel
            port.accessibilityValue = presentation.accessibilityValue
            port.calloutDetail = presentation.detail.line
            port.technicalSuffix = presentation.technicalSuffix
            return port
        }

        guard !before.isEmpty else { return }
        for port in ports {
            guard let was = before[port.id] else { continue }
            guard was.0 != port.link || was.1 != port.cfg else { continue }
            noteUnseenChange(on: port.face)
        }
    }
}

// MARK: - Reaching the stage from the menu bar

/// §2.7's View menu drives the stage, and the menu bar is outside the window's
/// view tree. The focused scene value is how AppKit's menu finds the stage of
/// whichever window is front — which is also what keeps ⌘1 doing nothing at all
/// when no window is.
struct StageModelFocusedValueKey: FocusedValueKey {
    typealias Value = StageModel
}

extension FocusedValues {
    var stageModel: StageModel? {
        get { self[StageModelFocusedValueKey.self] }
        set { self[StageModelFocusedValueKey.self] = newValue }
    }
}
