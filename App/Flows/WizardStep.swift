//
//  WizardStep.swift
//
//  The five screens of the set-up assistant — S3 preflight, S4 choose, S5
//  review, S6 apply, S7 ready — and the one progress label the app is allowed
//  to show (UX_SPEC §2.3 band 1).
//
//  The milestone labels ML0…ML3 never appear here or anywhere else in the
//  interface. "Step 3 of 5" is the only progress indicator in the app, and it
//  is a text label, never a progress bar.
//

import Foundation

/// S3 → S7, in the spec's order. Nothing reorders these and nothing skips one:
/// S4b is a modal *state* within `choose`, not a step of its own (§S4b).
enum WizardStep: Int, Sendable, Equatable, CaseIterable, Identifiable, Comparable {
    case preflight = 1
    case choose
    case review
    case apply
    case ready

    var id: Int { rawValue }

    static func < (lhs: WizardStep, rhs: WizardStep) -> Bool { lhs.rawValue < rhs.rawValue }

    /// §2.3 band 1: "Step 3 of 5" in `.caption` secondary, trailing. One
    /// localizable resource with two placeholders — nothing is concatenated.
    var caption: LocalizedStringResource {
        "Step \(rawValue) of \(WizardStep.allCases.count)"
    }

    var next: WizardStep? {
        WizardStep(rawValue: rawValue + 1)
    }

    var previous: WizardStep? {
        WizardStep(rawValue: rawValue - 1)
    }
}
