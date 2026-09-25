//
//  DiagnosticsFile.swift
//
//  `Save Diagnostics File…` — the one implementation behind all three places
//  that offer it: Settings (§S12), the change log (§S11) and the Help menu
//  (§2.7). The payload is `Diagnostics.live()`, the same text every `Copy
//  Details` puts on the pasteboard (§6.1 rule 8).
//
//  A save that fails in silence looks exactly like one that worked, so a
//  failure is said, in an alert on the window the save was asked from (§S12).
//

import AppKit
import UniformTypeIdentifiers

@MainActor
enum DiagnosticsFile {
    /// The save panel, as a sheet on the window it was asked from. It stands
    /// alone only when there is no window at all — the Help menu can be used
    /// with none open.
    static func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Diagnostics.suggestedFileName()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        let window = sheetHost(NSApplication.shared.keyWindow)
        if let window {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                write(to: url, reportingOn: window)
            }
        } else {
            guard panel.runModal() == .OK, let url = panel.url else { return }
            write(to: url, reportingOn: nil)
        }
    }

    /// The text is built off the main actor: it reads IOKit, the network and
    /// the notes folder.
    private static func write(to url: URL, reportingOn window: NSWindow?) {
        Task {
            let text = await Task.detached(priority: .userInitiated) { Diagnostics.live() }.value
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                report(error, on: window)
            }
        }
    }

    /// §S12: purely informational, so one `OK` is the whole answer.
    ///
    /// The window is asked again here, because the text took a moment to
    /// build: an alert sent to a window that has closed since is never seen,
    /// which is the silent failure this exists to prevent. One that has taken
    /// a sheet since gets the alert queued behind it.
    private static func report(_ error: any Error, on window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = String(localized: "The diagnostics file couldn't be saved.")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "OK"))
        if let window = sheetHost(window) {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    /// The window a sheet goes on: the one asked from, or the window it
    /// hangs from when that is itself a sheet. If it already has a sheet up —
    /// Restore, say, opened while the text was being built — AppKit queues
    /// this one until that sheet closes (`NSWindow.beginSheet`), so a sheet
    /// never stacks on a sheet and never falls back to an app-wide modal
    /// over one (§S12). `nil` only when there is no window left to hang from.
    private static func sheetHost(_ window: NSWindow?) -> NSWindow? {
        guard let window else { return nil }
        let host = window.sheetParent ?? window
        return host.isVisible ? host : nil
    }
}
