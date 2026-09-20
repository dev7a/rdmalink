/// RDMALinkCore holds everything the app and the command-line tool share:
/// the hardware inventory, the network configuration reads and writes,
/// the RDMA status, and the baseline (undo note) store.
public enum RDMALinkCore {
    /// The core's version. The app shows it in About.
    public static let version = "0.1.0"
}
