//
//  HubActionsCommands.swift
//
//  §2.7's Port menu, and the View menu's `Change Log ⌘L`. The menu bar is
//  outside the window's view tree, so these reach the hub through the focused
//  scene value exactly as the View menu reaches the stage — which is also what
//  keeps every item unavailable, rather than wrong, when no window is front.
//
//  Every item is present on every Mac and disabled when it has nothing to act
//  on. A missing menu item is a thing the user hunts for; an unavailable one
//  is an answer.
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

/// §2.7: `Set Up a Port… ⌘N · Identify a Port… ⌘I · Adopt… · Restore… ·
/// Restore All Ports… · Return to Bridge… · Stop Managing…`.
///
/// `Return to Bridge…` is §7.5's, which arrived after §2.7's table was
/// written; it sits beside the two actions it belongs with. **Owed from the
/// spec owner:** the row in §2.7's table.
struct PortCommands: View {
    @FocusedValue(\.hubActions) private var hub: HubActionsModel?

    var body: some View {
        item(.setUpAPort(portID: nil), key: "n")
        item(.identifyAPort(portID: nil), key: "i")
        Divider()
        item(.adopt(portID: selectedID))
        restoreItem
        item(.restoreAll)
        Divider()
        item(.returnToBridge(portID: selectedID))
        item(.stopManaging(portID: selectedID))
    }

    /// §2.8: "the Port menu's `Restore…` … [is] enabled" whenever any note
    /// exists, and the model decides which port that means.
    private var restoreItem: some View {
        Button("Restore…") {
            guard let hub else { return }
            hub.perform(hub.restoreAction)
        }
        .disabled(hub?.hasAnyNote != true)
    }

    private var selectedID: String { hub?.selectedPort?.id ?? "" }

    private func item(_ action: HubAction, key: KeyEquivalent? = nil) -> some View {
        Button(action.title) { hub?.perform(action) }
            .modifier(OptionalShortcut(key: key))
            .disabled(hub?.canPerform(action) != true)
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
