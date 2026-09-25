//
//  WizardIdentify.swift
//
//  S4b — Identify a port (UX_SPEC §S4b). A modal *state* within S4, not a
//  sheet: the stage stays fully live and becomes the whole point, and the port
//  list stays where it is.
//
//  Read-only, no password, always available — including on a Thunderbolt 4 Mac
//  and in the middle of an unrecognized-model session.
//

import SwiftUI

struct WizardIdentify: View {
    let flow: SetUpFlow
    let perform: (WizardAction) -> Void

    var body: some View {
        if let session = flow.identify {
            content(session)
        }
    }

    private func content(_ session: IdentifySession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WizardHeadline(
                headline: session.currentHeadline, message: session.currentBody)
            if let status = session.statusLine {
                HStack(spacing: 8) {
                    if case .watching = session.outcome {
                        ProgressView().controlSize(.small)
                    }
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }
            if session.showsNudge {
                Text(IdentifySession.nudge)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            // The default button lives in the footer, where every default
            // button in the app lives. These are the rest of §S4b's row.
            HStack(spacing: 10) {
                ForEach(secondaryActions(for: session), id: \.self) { action in
                    Button(action.title) { perform(action) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.18), value: session.outcome)
        .animation(.smooth(duration: 0.18), value: session.showsNudge)
        // §8.2: every detected change is announced, which makes Identify
        // arguably better with VoiceOver than without.
        .onChange(of: session.announcement) { _, announcement in
            guard let announcement else { return }
            AccessibilityNotification.Announcement(announcement).post()
            session.announcementDelivered()
        }
    }

    /// §S4b's buttons, minus the one the footer is already showing.
    private func secondaryActions(for session: IdentifySession) -> [WizardAction] {
        switch session.outcome {
        case .watching: []
        case .unplugged, .replugged: [.identifyAgain, .chooseFromList]
        case .ambiguous, .usbOnly: [.chooseFromList]
        case .timedOut: [.identifyAgain]
        }
    }
}
