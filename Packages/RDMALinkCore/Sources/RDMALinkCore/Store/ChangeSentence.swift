import Foundation

/// The change log's sentences, exactly as the spec writes them (S11).
///
/// Each sentence is one whole string: nothing here is assembled out of
/// fragments, and the two that name a moment take the whole moment as a single
/// placeholder so a translator can move it.
public enum ChangeSentence {

    /// The entry for a port RDMALink set up.
    public static let setUp =
        "Took it out of Thunderbolt Bridge and gave it its own service, with IPv4 off and IPv6 link-local only."

    /// The entry for a port RDMALink adopted.
    public static let adopted =
        "Adopted. RDMALink noted how it was already set up and changed nothing."

    /// The entry for a port RDMALink returned to the bridge (§7.5), with one
    /// placeholder for the bridge as System Settings names it — when a
    /// standalone service went with it.
    public static let returnedAndRemovedServiceFormat =
        "Put it back in %@ and removed its standalone service."

    /// The same entry when there was no standalone service to remove.
    public static let returnedFormat = "Put it back in %@."

    /// The note a restored entry carries, with one placeholder for the moment,
    /// such as `3 September at 15:10`.
    public static let alreadyPutBackFormat = "Already put back on %@."

    /// The note a returned entry carries once the port has been set up again,
    /// with one placeholder for the moment.
    public static let setUpAgainFormat = "Set up again on %@."

    /// The note an adopted entry carries once the port has been returned to
    /// the bridge, with one placeholder for the moment.
    public static let putBackInBridgeFormat = "Put back in the bridge on %@."

    /// The note an entry carries once RDMALink stopped looking after the port.
    public static let stoppedLookingAfterFormat =
        "RDMALink stopped looking after this port on %@."

    /// The line for an entry whose port is not on this Mac any more.
    public static let portIsGone =
        "This port isn't on this Mac any more, so there's nothing left to put back. The note stays until you clear it."

    /// "Put it back in Thunderbolt Bridge and removed its standalone service."
    /// or, with nothing removed, "Put it back in Thunderbolt Bridge."
    public static func returned(bridgeName: String, removedService: Bool) -> String {
        String(format: removedService ? returnedAndRemovedServiceFormat : returnedFormat,
               bridgeName)
    }

    /// "Already put back on 3 September at 15:10."
    public static func alreadyPutBack(moment: String) -> String {
        String(format: alreadyPutBackFormat, moment)
    }

    /// "Set up again on 20 September at 11:52."
    public static func setUpAgain(moment: String) -> String {
        String(format: setUpAgainFormat, moment)
    }

    public static func putBackInBridge(moment: String) -> String {
        String(format: putBackInBridgeFormat, moment)
    }

    /// "RDMALink stopped looking after this port on 3 September at 15:12."
    public static func stoppedLookingAfter(moment: String) -> String {
        String(format: stoppedLookingAfterFormat, moment)
    }
}
