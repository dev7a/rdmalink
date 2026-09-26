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
//  Nothing re-enters a run (§2.7). While the set-up assistant is up the same
//  two answer no to everything but the picker's own: on S4 the route it
//  names for a dimmed row (`Restore…`, `Return to Bridge…` or `Adopt…`) and
//  `Identify Port…`, which starts its S4b; on S4b to S7, nothing. `Change
//  Log` and Help's `What to Do on the Other Mac` and `Save Diagnostics
//  File…` wait for it to close as well. And a sheet is never replaced from
//  outside it (§2.6): while one is up every item here answers no, and so do
//  Help's `RDMALink Help` and `Save Diagnostics File…`.
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

    /// §2.7, §2.8: the Port menu's `Restore…` means one port — the port in
    /// hand, or the only noted one — or it is unavailable, because `Restore
    /// All Ports…` sits right under it and one sheet has one name there. It
    /// is unavailable on an unrecognized Mac too, and on the picker it means
    /// the dimmed row last clicked and nothing else (§2.7). The model decides
    /// which port it means, and `canPerform` answers for it, as it does for
    /// every other item.
    private var restoreItem: some View {
        let action = hub?.restoreOnePort
        return Button("Restore…") {
            if let hub, let action { hub.perform(action) }
        }
        .disabled(action.map { hub?.canPerform($0) != true } ?? true)
    }

    /// The hub's selection — or, on the picker, the dimmed row last clicked,
    /// which is "that row" in §2.7 (`HubActionsModel.menuPortID`).
    private var selectedID: String { hub?.menuPortID ?? "" }

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

/// Whether the main window has one of its sheets up, handed to the menu bar
/// so the Help menu's items can wait for it (§2.6, §S12).
struct PresentsSheetFocusedValueKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var presentsSheet: Bool? {
        get { self[PresentsSheetFocusedValueKey.self] }
        set { self[PresentsSheetFocusedValueKey.self] = newValue }
    }
}

/// §2.7's `Save Diagnostics File…`, unavailable while the main window has a
/// sheet up: a sheet never stacks on a sheet, and an app-wide save panel over
/// one would be the same stacking by another name (§S12). Unavailable while
/// the set-up assistant is up too: the save panel is a sheet on the window,
/// and nothing but What This All Means opens a sheet over a run (§2.6, §2.7).
/// The router answers for the assistant, as it does for `OtherMacCommand`.
struct SaveDiagnosticsCommand: View {
    let router: HubRouter
    @FocusedValue(\.presentsSheet) private var presentsSheet

    var body: some View {
        Button("Save Diagnostics File…") { DiagnosticsFile.save() }
            .disabled(presentsSheet == true || router.isAssistantUp)
    }
}

/// §2.7's `RDMALink Help` ⌘?, which opens §S13's sheet. It is the one sheet
/// that opens over any step of a run, because it only reads (§2.6) — but
/// never over another sheet, which would stack on it.
struct HelpCommand: View {
    let show: () -> Void
    @FocusedValue(\.presentsSheet) private var presentsSheet

    var body: some View {
        Button("RDMALink Help", action: show)
            .keyboardShortcut("?", modifiers: .command)
            .disabled(presentsSheet == true)
    }
}

/// The View menu's last item (§2.7), which shows §S11 in place of the working
/// area rather than opening a sheet — and so is unavailable while the set-up
/// assistant holds the working area, rather than queued behind it
/// (`HubActionsModel.canPerform`).
struct ChangeLogCommand: View {
    @FocusedValue(\.hubActions) private var hub: HubActionsModel?

    var body: some View {
        Button("Change Log") { hub?.perform(.changeLog) }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(hub?.canPerform(.changeLog) != true)
    }
}

/// Help › `What to Do on the Other Mac` (§2.7, §S8). A screen in the working
/// area, so it is unavailable while the set-up assistant holds it — never
/// queued to appear when the run ends. The router says so rather than the
/// focused window, so the answer holds with Settings in front too. With the
/// window closed there is no assistant either, and the item brings it back.
struct OtherMacCommand: View {
    let router: HubRouter
    let show: () -> Void

    var body: some View {
        Button("What to Do on the Other Mac", action: show)
            .disabled(router.isAssistantUp)
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
