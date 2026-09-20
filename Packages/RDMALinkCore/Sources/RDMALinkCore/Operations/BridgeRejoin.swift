import Foundation

/// Putting a port into a bridge's stored member list so that configd attempts
/// the kernel add on the next apply — and the one retry that works when it
/// does not.
///
/// Two things were measured on 2026-09-20 and shape everything here:
///
/// 1. configd attempts the add a few milliseconds after an apply. If the same
///    apply is tearing down the port's IP configuration, the add lands while
///    IPv6 is still attached and the kernel refuses it. So a service deletion
///    goes in a commit of its own, and the port is given time to go quiet
///    (``KernelVerification/waitUntilQuiet(_:writer:policy:)``) before the
///    membership is written.
/// 2. A commit that changes nothing makes configd attempt nothing: applying
///    again is not a retry. The retry is to take the membership out, commit,
///    let the port settle, put it back, and commit again.
enum BridgeRejoin {
    /// Adds the member to the stored list, uncommitted.
    ///
    /// When the stored list already has it — an earlier attempt got this far
    /// and the kernel did not follow (R20) — it is toggled instead, because
    /// committing the same list again would change nothing.
    ///
    /// - Returns: whether the membership was rewritten rather than simply
    ///   added. That rewrite is the one retry there is, so the caller folds it
    ///   into the ``KernelAgreement`` it reports
    ///   (``KernelAgreement/foldingRewrite(atAddTime:)``): a kernel that then
    ///   agreed on the first read did not settle on its own.
    @discardableResult
    static func add(
        _ bsdName: String,
        to bridge: BridgeMembership,
        at position: Int?,
        writer: NetworkWriter,
        policy: KernelWaitPolicy
    ) throws -> Bool {
        do {
            try writer.addMember(bsdName, to: bridge, at: position)
            return false
        } catch BridgeSPIError.alreadyMember {
            try toggle(bsdName, in: bridge, at: position, writer: writer, policy: policy)
            return true
        }
    }

    /// The retry: out and committed, quiet, then in again — left uncommitted
    /// for the caller, so it commits exactly as the first attempt did.
    static func toggle(
        _ bsdName: String,
        in bridge: BridgeMembership,
        at position: Int?,
        writer: NetworkWriter,
        policy: KernelWaitPolicy
    ) throws {
        try writer.removeMember(bsdName, from: bridge)
        try writer.commitAndApply()
        _ = try KernelVerification.waitUntilQuiet(bsdName, writer: writer, policy: policy)
        try writer.addMember(bsdName, to: bridge, at: position)
    }

    /// A service deletion committed on its own, then the port given time to go
    /// quiet, so the membership that follows is not written into the teardown.
    static func commitDeletionAndSettle(
        _ bsdName: String,
        writer: NetworkWriter,
        policy: KernelWaitPolicy
    ) throws {
        try writer.commitAndApply()
        _ = try KernelVerification.waitUntilQuiet(bsdName, writer: writer, policy: policy)
    }
}
