//
//  HubActionsCommands.swift
//
//  §2.7's Port menu, and the View menu's `Check Again ⌘R` and `Change Log
//  ⌘L`. The menu bar is outside the window's view tree, so these reach the
//  hub through the focused scene value exactly as the View menu reaches the
//  stage — which is also what keeps every item unavailable, rather than wrong,
//  when no window is front.
//
//  Every item is present on every Mac and disabled when it has nothing to act
//  on. A missing menu item is a thing the user hunts for; an unavailable one
//  is an answer. That holds on a Mac RDMALink does not recognize too (§6.2
//  R31, §2.7): the window offers nothing that writes — absent, not disabled —
//  but the menu keeps its shape, with every item unavailable, `Identify
//  Port…` included, "because there is no model for it to point at" (§S1).
//  `canPerform` answers no for all of them there, and `perform` refuses
//  them as well, so a disabled item is not the only guard.
//

import SwiftUI

struct HubActionsFocusedValueKey: FocusedValueKey {
    typealias Value = HubActionsModel
}

extension FocusedValues {
    var hubActions: HubActionsModel? {
        get { self[HubActionsFocusedValueKey.self] }
        set { self[HubActionsFocusedValueKey.self] = newValue }
    }
}

/// §2.7: `Set Up Port… ⌘N · Identify Port… ⌘I · Adopt… · Restore… ·
/// Restore All Ports… · Return to Bridge… · Stop Managing…`.
///
/// `Return to Bridge…` is §7.5's; it sits beside the two actions it belongs
/// with.
struct PortCommands: View {
    @FocusedValue(\.hubActions) private var hub: HubActionsModel?

    var body: some View {
        item(.setUpPort(portID: nil), key: "n")
        item(.identifyPort(portID: nil), key: "i")
        Divider()
        item(.adopt(portID: selectedID))
        restoreItem
        item(.restoreAll)
        Divider()
        item(.returnToBridge(portID: selectedID))
        item(.stopManaging(portID: selectedID))
    }

    /// §2.8: whenever a restorable note exists the Port menu's `Restore…` is
    /// enabled — "the one exception is an unrecognized Mac", where it is
    /// present and unavailable. The model decides which port it means, and
    /// `canPerform` answers for both, as it does for every other item.
    private var restoreItem: some View {
        Button("Restore…") {
            guard let hub else { return }
            hub.perform(hub.restoreAction)
        }
        .disabled(hub.map { !$0.canPerform($0.restoreAction) } ?? true)
    }

    private var selectedID: String { hub?.selectedPort?.id ?? "" }

    private func item(_ action: HubAction, key: KeyEquivalent? = nil) -> some View {
        Button(action.title) { hub?.perform(action) }
            .modifier(OptionalShortcut(key: key))
            .disabled(hub?.canPerform(action) != true)
    }
}

/// The window's re-check — the probe and the checks' own reads — handed to
/// the menu bar the way the stage and the hub are.
struct RecheckFocusedValueKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}

extension FocusedValues {
    var recheck: (@MainActor () -> Void)? {
        get { self[RecheckFocusedValueKey.self] }
        set { self[RecheckFocusedValueKey.self] = newValue }
    }
}

/// The first of the app's View items (§2.7), after the system's toolbar
/// items, and the one home of ⌘R: the toolbar's `Check Again` runs the same
/// re-check and declares no shortcut of its own (§2.2). A read, so it is
/// available in every state, R31 included.
struct CheckAgainCommand: View {
    @FocusedValue(\.recheck) private var recheck

    var body: some View {
        Button("Check Again") { recheck?() }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(recheck == nil)
    }
}

/// The View menu's last item (§2.7), which shows §S11 in place of the working
/// area rather than opening a sheet.
struct ChangeLogCommand: View {
    @FocusedValue(\.hubActions) private var hub: HubActionsModel?

    var body: some View {
        Button("Change Log") { hub?.perform(.changeLog) }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(hub == nil)
    }
}

/// Two of the Port menu's items carry a shortcut and the rest do not, and a
/// `Button` cannot take an optional one.
private struct OptionalShortcut: ViewModifier {
    let key: KeyEquivalent?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: .command)
        } else {
            content
        }
    }
}
