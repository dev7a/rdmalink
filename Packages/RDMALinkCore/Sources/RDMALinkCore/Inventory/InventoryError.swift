import Darwin

/// A hardware read that did not happen.
///
/// The app turns this into R24 ("RDMALink can't see this Mac's Thunderbolt
/// hardware"), and ``description`` is what `Copy Details` carries.
public struct InventoryError: Error, Sendable, Equatable, CustomStringConvertible {
    /// What was being attempted, in technical words.
    public var step: String
    /// The `kern_return_t` the call returned.
    public var code: Int32

    public init(step: String, code: Int32) {
        self.step = step
        self.code = code
    }

    public var description: String {
        "Could not \(step) (IOKit error 0x\(String(UInt32(bitPattern: code), radix: 16)))"
    }
}
