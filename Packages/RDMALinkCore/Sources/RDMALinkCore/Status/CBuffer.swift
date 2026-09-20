import Foundation

/// A NUL-terminated C buffer, read back as a Swift string.
///
/// `String(cString:)` on an array is deprecated in Swift 6.4, and the arrays
/// here — `mkstemp` templates and `sysctl` buffers — always carry their NUL.
enum CBuffer {
    static func string(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
