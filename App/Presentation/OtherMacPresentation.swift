//
//  OtherMacPresentation.swift
//
//  What §S8 is about on this reading: which port is "this link", the address
//  step 4 names, and whether the far end has answered. Pure over the hub's
//  snapshots and the way the screen was reached, so the screen, its footer's
//  copy and the stage's handoff agree about the port and the script can check
//  the rule. And which Mac the user says the other one is, for the stage's
//  picture of it (`OtherMacChoice`, §S8 "The other Mac's picture"), and
//  where the pop-up that says so stands (`OtherMacPickerPlace`).
//

import Foundation
import RDMALinkCore

/// §S8's `Other Mac:` pop-up: which Mac the stage draws the ghost second Mac
/// as. "It changes the stage's picture of the other Mac and nothing else",
/// and "the choice is remembered across launches" (`AppSettings.otherMac`).
/// The raw values are what is remembered, so they never change.
enum OtherMacChoice: String, CaseIterable, Identifiable, Sendable {
    case anyMac
    case macBookPro
    case macStudio
    case macMini

    /// "**Any Mac**, the default".
    static let standard = OtherMacChoice.anyMac

    var id: Self { self }

    /// The item, verbatim: Title Case, and no ellipsis, because choosing one
    /// finishes the command (§1.3 rule 11).
    var title: LocalizedStringResource {
        switch self {
        case .anyMac: "Any Mac"
        case .macBookPro: "MacBook Pro"
        case .macStudio: "Mac Studio"
        case .macMini: "Mac mini"
        }
    }

    /// The model a family is drawn as — "a current Thunderbolt 5 model of it:
    /// the Mac Studio (M5 Max), the Mac mini (M5 Pro) and the 14-inch MacBook
    /// Pro (M5 Pro or M5 Max)" — by the identifier Core's catalogue lists it
    /// under, so the chassis is the catalogue's and never a second table's.
    /// `nil` for **Any Mac**, which "draws the featureless box".
    var representative: String? {
        switch self {
        case .anyMac: nil
        case .macBookPro: "Mac17,7"
        case .macStudio: "Mac17,14"
        case .macMini: "Mac17,16"
        }
    }

    /// The chassis family the ghost is drawn as, or `nil` for the box.
    var archetype: Archetype? {
        representative.flatMap(HardwareModel.archetype(forIdentifier:))
    }
}

/// Where §S8's `Other Mac:` pop-up stands, if anywhere (UX_SPEC §S8 "The
/// other Mac's picture", §2.3). One answer for the stage and the working
/// area, so the pop-up is never in both places, and never in neither while
/// the screen is up on a Mac the stage can draw.
enum OtherMacPickerPlace: Equatable, Sendable {
    /// "On the stage, in its top-trailing corner — above where the ghost
    /// settles, across from the legend".
    case stage
    /// "Below 900 pt the stage is §8.5's 180 pt strip, which the pair fills
    /// from top to bottom, so there the pop-up leaves the stage for the
    /// working area … below the note and above the honesty line".
    case workingArea

    /// - Parameters:
    ///   - showsOtherMac: §S8 holds the working area — not merely asked for:
    ///     the set-up assistant's working area comes first.
    ///   - recognized: the stage draws a model. "On an unrecognized Mac
    ///     (R31) the stage draws no model and no ghost, so the pop-up is not
    ///     there, on the stage or in the working area."
    ///   - stageIsStrip: §8.5's single column, below 900 pt.
    static func place(showsOtherMac: Bool, recognized: Bool, stageIsStrip: Bool) -> Self? {
        guard showsOtherMac, recognized else { return nil }
        return stageIsStrip ? .workingArea : .stage
    }
}

/// How §S8 was reached, which decides whose link it is about (UX_SPEC §S8
/// "Whose link").
enum OtherMacOrigin: Equatable, Sendable {
    /// S7's `What to Do on the Other Mac`: the port that run just set up —
    /// the first in physical order when it set up several — for as long as
    /// this Mac reports it.
    case run(setUp: String)
    /// The Help menu, with no run: the port selected on the stage when the
    /// screen opened, if one was.
    case help(selected: String?)
}

/// §S8's subject.
struct OtherMacReport: Equatable, Sendable {
    /// The port the handoff is drawn from and step 4 names (§S8 "Whose
    /// link"). From S7, the port the run just set up, for as long as this Mac
    /// reports it, ready or not; once it is gone, the Help menu's rule. From
    /// the Help menu, the port selected when the screen opened if it is
    /// ready; otherwise the first ready port with an address, or the first
    /// ready port when none has one yet. §S8 step 4 names *this Mac's*
    /// address on the link, which is an address RDMALink put there; a port
    /// somebody else set up is not RDMALink's to hand out (§7.3), so `ready`
    /// is what the Help menu's rule looks at. `nil` only when no port
    /// qualifies: from the Help menu with no ready port, or from a run whose
    /// port this Mac no longer reports while no port is ready.
    var subjectID: String?
    /// Step 4's `fe80::…%en6` — the subject's own, when it has one.
    var address: String?
    /// §S8's live line, "when a Mac answers at the far end of this link": a
    /// Mac at the far end of the subject's cable — never another port's — is
    /// the one thing this Mac can see of the other.
    var answered: Bool

    init(ports: [PortSnapshot], origin: OtherMacOrigin) {
        let ready = ports.ready
        let usual = ready.first { $0.linkLocalAddress != nil } ?? ready.first
        let subject: PortSnapshot?
        switch origin {
        case .run(let id):
            // The port the user just set up, whatever the other ports are
            // doing: a ready neighbour with an address is not this link, and
            // this link with nothing plugged in yet still is.
            subject = ports.first { $0.id == id } ?? usual
        case .help(let selected):
            subject = ready.first { $0.id == selected } ?? usual
        }
        subjectID = subject?.id
        address = subject?.linkLocalAddress
        answered = subject?.port.link == .macLinked
    }
}
