//
//  SettingsWindow.swift
//
//  S12 — the one preferences surface. A single pane, so per HIG (and UX_SPEC
//  §2.7, §S12) there is no toolbar and no tab bar.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RDMALinkCore

struct SettingsWindow: View {
    @AppStorage(AppSettings.showTechnicalNames) private var showsTechnicalNames = false
    /// Off until the check exists. §S12's help text says "RDMALink checks the
    /// release page now and then", and shipping it on would be the app saying
    /// so in its own voice about something it does not do (§1.3 rule 10).
    @AppStorage(AppSettings.checksForUpdates) private var checksForUpdates = false

    /// Whether any undo note exists, which decides `Reveal Notes in Finder`.
    /// Read when the window appears rather than watched: notes are written by
    /// the set-up path, which cannot run while this window is in front.
    @State private var hasNotes = false
    @State private var saveFailure: String?

    // §S12's `Check for Updates Now` is not built here. ML3 owns the
    // release-page check, §S12's States list names exactly one disabled
    // control (`Reveal Notes in Finder`), and §1.3 rule 5 is why a permanently
    // unavailable button with a sentence the spec never wrote is worse than an
    // absent one. **Owed:** the button, with the ML3 check behind it.

    var body: some View {
        Form {
            Section {
                SettingsToggle(
                    title: "Show technical names",
                    help: "Adds names like en6 and the exact service names next to each port. The link address always shows in full, because tools need every character of it. Nothing is ever written on the picture of your Mac.",
                    isOn: $showsTechnicalNames
                )
                SettingsToggle(
                    title: "Check for updates automatically",
                    help: "RDMALink checks the release page now and then. It never sends anything about your Mac.",
                    isOn: $checksForUpdates
                )
            }
            Section {
                SettingsButton(
                    title: "Reveal Notes in Finder",
                    help: "RDMALink keeps one small note per port it set up. That note is what makes putting things back possible — it's safe to back up and safe to leave alone.",
                    isEnabled: hasNotes,
                    disabledHelp: "RDMALink hasn't set up a port on this Mac yet, so there are no notes to show.",
                    action: revealNotes
                )
                SettingsButton(
                    title: "Save a Diagnostics File…",
                    help: "A plain text file with what RDMALink can see on this Mac and what it has changed: the model, the chip, the macOS build, the ports, and any step that failed. No personal information, and nothing is sent anywhere — it's yours to keep or share.",
                    action: saveDiagnostics
                )
                if let saveFailure {
                    Text(verbatim: saveFailure)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .task { hasNotes = Self.notesExist() }
    }

    /// Exactly the folder `BaselineStore` writes to, so the button never opens
    /// a directory the app does not actually use.
    private func revealNotes() {
        WizardFinder.showNotesFolder()
    }

    private func saveDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Diagnostics.suggestedFileName()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            let text = await Task.detached(priority: .userInitiated) { Diagnostics.live() }.value
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                saveFailure = nil
            } catch {
                saveFailure = String(
                    localized: "The file couldn't be written: \(error.localizedDescription)"
                )
            }
        }
    }

    private static func notesExist() -> Bool {
        !((try? NotesLocation.store.list()) ?? []).isEmpty
    }
}

/// A toggle with §S12's `.callout` help text beneath it.
private struct SettingsToggle: View {
    let title: LocalizedStringResource
    let help: LocalizedStringResource
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: $isOn)
            Text(help)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

/// A button with §S12's `.callout` help text beneath it. When the button is
/// unavailable the reason is the tooltip, so nothing is disabled in silence.
private struct SettingsButton: View {
    let title: LocalizedStringResource
    var help: LocalizedStringResource?
    var isEnabled = true
    var disabledHelp: LocalizedStringResource?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(title, action: action)
                .disabled(!isEnabled)
                .help(tooltip)
            if let help {
                Text(help)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private var tooltip: Text {
        if !isEnabled, let disabledHelp { return Text(disabledHelp) }
        return Text(help ?? title)
    }
}
