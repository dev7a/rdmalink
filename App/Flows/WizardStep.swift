//
//  WizardStep.swift
//
//  The screens of the set-up assistant — S4 choose, S5 review, S6 setting up,
//  S7 ready — and the one progress label the app is allowed to show (UX_SPEC
//  §2.3 band 1).
//
//  The milestone labels ML0…ML3 never appear here or anywhere else in the
//  interface. "Step 2 of 3" is the only progress indicator in the app, and it
//  is a text label, never a progress bar.
//

import Foundation

/// S4 → S7, in the spec's order. Nothing reorders these: S4b is a modal
/// *state* within `choose`, not a step of its own (§S4b), and S3's four
/// checks are a group at the top of `review`, not a screen (§S3).
enum WizardStep: Sendable, Equatable, Hashable, CaseIterable, Comparable {
    case choose
    case review
    /// S6. Not a numbered screen: "Setting up (S6) keeps Review's label while
    /// it runs" (§2.3 band 1), so it shares `review`'s number below.
    case apply
    case ready

    static func < (lhs: WizardStep, rhs: WizardStep) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    /// Which numbered screen this is, counting from the start of the flow.
    private var screen: Int {
        switch self {
        case .choose: 1
        case .review, .apply: 2
        case .ready: 3
        }
    }

    /// §2.3 band 1: "Step 2 of 3" in `.caption` secondary, trailing. One
    /// localizable resource with two placeholders — nothing is concatenated.
    ///
    /// The label "counts the screens of the current run": a run that opened on
    /// the picker has three (Choose, Review, Ready); one whose port was chosen
    /// on the hub, or picked for the user, opened on Review and has two.
    /// `first` is the screen the run opened on, and it shifts both numbers.
    func caption(openedOn first: WizardStep) -> LocalizedStringResource {
        let offset = first.screen - 1
        return "Step \(screen - offset) of \(WizardStep.ready.screen - offset)"
    }
}
