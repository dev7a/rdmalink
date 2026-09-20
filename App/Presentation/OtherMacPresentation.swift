//
//  OtherMacPresentation.swift
//
//  What §S8 is about on this reading: which port is "this link", the address
//  step 4 names, and whether the far end has answered. Pure over the hub's
//  snapshots, so the screen and the stage's handoff agree about the port and
//  the script can check the rule.
//

import Foundation

/// §S8's subject.
struct OtherMacReport: Equatable, Sendable {
    /// The port the handoff is drawn from: the first port RDMALink set up or
    /// adopted that has an address, or the first it set up when none has one
    /// yet. §S8 step 4 names *this Mac's* address on the link, which is an
    /// address RDMALink put there; a port somebody else set up is not
    /// RDMALink's to hand out (§7.3), so `ready` is what is looked at.
    var subjectID: String?
    /// Step 4's `fe80::…%en6`, when there is one.
    var address: String?
    /// §S8's live line: "when the far end answers". A Mac at the far end of
    /// the subject's cable is the one thing this Mac can see of the other.
    var answered: Bool

    init(ports: [PortSnapshot]) {
        let ready = ports.ready
        let subject = ready.first { $0.linkLocalAddress != nil } ?? ready.first
        subjectID = subject?.id
        address = subject?.linkLocalAddress
        answered = subject?.port.link == .macLinked
    }
}
