//
//  OtherMacSheet.swift
//
//  S8's four steps, reached from the Help menu's "What to Do on the Other Mac".
//
//  UX_SPEC §S8 makes this a *screen* rather than a sheet, because there the
//  stage performs the handoff with the ghost second Mac. That screen, and the
//  ghost, belong to ML3 and to the stage. Until then the copy is offered where
//  the spec also says it is reachable from — the Help menu — as a sheet with no
//  3D content, which is the honest subset: every word is §S8's, and nothing
//  claims a picture it isn't drawing.
//

import AppKit
import SwiftUI

struct OtherMacSheet: View {
    /// The `fe80::` address of the first ready port, when there is one.
    let address: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
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
                if let address {
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
                Text("I can only see this Mac. Nothing I did crossed that cable — that's deliberate.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                // §S8's button row is "**Copy These Steps** → **Copied** ·
                // **Done**": a state the button passes through, not an end
                // state (§9.14).
                CopyButton(title: "Copy These Steps") { plainTextSteps }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500, alignment: .leading)
    }

    /// The same four sentences, as plain text, for the other Mac's notes app.
    private var plainTextSteps: String {
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
