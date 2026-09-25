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
    /// The save panel, as a sheet on the key window when it can take one —
    /// the Help menu can be used with no window open, and then it stands
    /// alone.
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
    /// which is the silent failure this exists to prevent.
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

    /// The window a sheet can go on: one that is on screen, is not a sheet
    /// itself and has none up. Help › Save Diagnostics File… can be chosen
    /// with Restore or What This All Means open, and the key window is then
    /// that sheet — a sheet never stacks on a sheet (§S12).
    private static func sheetHost(_ window: NSWindow?) -> NSWindow? {
        guard let window, window.isVisible, window.sheetParent == nil,
            window.attachedSheet == nil
        else { return nil }
        return window
    }
}
