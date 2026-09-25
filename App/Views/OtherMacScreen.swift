//
//  OtherMacScreen.swift
//
//  S8 — Now the other Mac (UX_SPEC §S8). "Close the loop the app cannot
//  cross." Reached from S7's footer and from the Help menu. **A screen, not a
//  sheet**, because the stage does the talking: while this is up, the camera
//  pulls back, a featureless ghost of a second Mac slides in beside this one
//  with a single thin line between them, and when the far end answers a pulse
//  travels back along that line and blooms at the near receptacle, once.
//
//  It takes the working area's place the way §S11's change log does, so the
//  port list — compact, per §2.3 — and the model stay beside it, and its
//  buttons take band 4 while the hub's footer steps aside (`OtherMacFooter`,
//  §2.3 band 4).
//

import AppKit
import SwiftUI

struct OtherMacScreen: View {
    let model: InventoryModel
    /// §S8's 3D behaviour is the stage's; this screen only tells it when the
    /// handoff begins and ends, and which port it is about.
    let stage: StageModel

    var body: some View {
        let report = OtherMacReport(ports: model.ports)
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Now the other Mac")
                    .font(.title2.weight(.semibold))
                Text("RDMALink only ever changes the Mac it's running on. There's no connection between the two — you do the same thing over there, by hand, and that's the whole trick.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                NumberedStep(number: 1, text: "Copy RDMALink across, or download it again on the other Mac.")
                NumberedStep(number: 2, text: "Open it and walk the same short path.")
                NumberedStep(number: 3, text: "Pick the port with the other end of this cable in it. Identify makes that painless.")
                if let address = report.address {
                    NumberedStep(
                        number: 4,
                        text: "When both sides are done, each Mac has its own address on this link. This one is \(address)."
                    )
                } else {
                    NumberedStep(number: 4, text: "When both sides are done, each Mac has its own address on this link. This one's address appears as soon as a Mac is connected.")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Leave this one cable connected while you're over there — and keep it to one cable between the pair.")
                Text("RDMALink can only see this Mac. Nothing it did crossed that cable — that's deliberate.")
                if report.answered {
                    // §S8's live line, in the same beat as the stage's
                    // returning pulse: one event, two places.
                    Text("Something answered on this link. That's a good sign — the other end is awake.")
                        .transition(.opacity)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.25), value: report)
        // §S8: the stage performs the handoff for as long as the screen is up,
        // about the port step 4 names — and re-aims if a later reading
        // changes which port that is.
        .onChange(of: report.subjectID, initial: true) { _, id in
            stage.beginHandoff(for: id)
        }
        .onDisappear { stage.endHandoff() }
    }

    /// The same four sentences, as plain text, for the other Mac's notes app.
    static func plainTextSteps(address: String?) -> String {
        var lines = [
            String(localized: "Now the other Mac"),
            "",
            String(localized: "1. Copy RDMALink across, or download it again on the other Mac."),
            String(localized: "2. Open it and walk the same short path."),
            String(localized: "3. Pick the port with the other end of this cable in it. Identify makes that painless."),
        ]
        if let address {
            let step: String.LocalizationValue = "4. When both sides are done, each Mac has its own address on this link. This one is \(address)."
            lines.append(String(localized: step))
        } else {
            lines.append(String(localized: "4. When both sides are done, each Mac has its own address on this link. This one's address appears as soon as a Mac is connected."))
        }
        lines.append("")
        lines.append(String(localized: "Leave this one cable connected while you're over there — and keep it to one cable between the pair."))
        return lines.joined(separator: "\n") + "\n"
    }
}

/// §S8's buttons, in band 4 while the screen holds the working area:
/// "**Copy These Steps** → **Copied** · **Done**", `Done` the default. The
/// hub's footer and link row step aside meanwhile (§2.3 band 4), so the window
/// has one button row and one default.
struct OtherMacFooter: View {
    let model: InventoryModel
    let done: () -> Void

    var body: some View {
        ScreenFooter {
            // A state the button passes through, not an end state (§9.14).
            CopyButton(title: "Copy These Steps") {
                OtherMacScreen.plainTextSteps(address: OtherMacReport(ports: model.ports).address)
            }
            Button("Done", action: done)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// One numbered step. The number is a separate, non-localized label so the
/// sentence itself stays one string (§1.3 rule: no sentence is concatenated).
private struct NumberedStep: View {
    let number: Int
    let text: LocalizedStringResource

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number.formatted())
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
