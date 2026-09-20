//
//  WizardActions.swift
//
//  What the assistant's buttons do when what they do is open something.
//
//  Every refusal's primary is a real action (UX_SPEC §6.1 rule 5), and most of
//  those actions are "open the right settings pane". The deep links live here,
//  in one place, with one fallback: if a pane's link is not honoured, System
//  Settings is opened anyway, because landing the user in the app they were
//  sent to is better than a button that appears to do nothing.
//

import AppKit
import Foundation
import RDMALinkCore

enum WizardSettingsPane {
    /// Verified on macOS 27.2 and load-bearing: it is the one the RDMA switch
    /// already uses (`docs/ARCHITECTURE.md`).
    static let developerTools = RDMAStatus.developerToolsSettingsURL

    /// **Unverified on macOS 27.** These three follow the documented
    /// `x-apple.systempreferences:` extension-bundle form, but nothing in this
    /// repository has confirmed the identifiers on this release, so every open
    /// falls back to System Settings itself rather than failing silently.
    static let network = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")
    static let usersAndGroups = URL(
        string: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension")
    static let profiles = URL(
        string: "x-apple.systempreferences:com.apple.Profiles-Settings.extension")

    private static let systemSettings = URL(string: "x-apple.systempreferences:")!

    @MainActor
    static func open(_ url: URL?) {
        guard let url, NSWorkspace.shared.open(url) else {
            NSWorkspace.shared.open(systemSettings)
            return
        }
    }
}

enum WizardFinder {
    /// R4's `Show in Finder`: Finder comes forward with the volume selected.
    @MainActor
    static func showVolume(named name: String) {
        let url = URL(fileURLWithPath: "/Volumes").appending(path: name)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// R14's `Show the Notes Folder`.
    @MainActor
    static func showNotesFolder(_ directory: URL = BaselineStore.defaultDirectory) {
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }
}

enum WizardSystemSettingsApp {
    /// R12's `Quit System Settings`, shown only when System Settings is the
    /// holder of the lock. A polite terminate, never a kill.
    @MainActor
    static func quit() {
        for app in NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.systempreferences")
        {
            app.terminate()
        }
    }
}
