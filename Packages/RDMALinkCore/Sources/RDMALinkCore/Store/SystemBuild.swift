import Darwin
import Foundation

/// The macOS build this Mac is running, such as `26B5086k`.
///
/// Every undo note records it, so a note taken on one build is recognizable
/// when it is read back on another — and so the diagnostics file can say which
/// build a failing step happened on.
public enum SystemBuild {

    /// `kern.osversion`, or an empty string if sysctl will not answer.
    public static var current: String { value(for: "kern.osversion") ?? "" }

    /// Reads a string sysctl by name.
    static func value(for name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let text = CBuffer.string(buffer)
        return text.isEmpty ? nil : text
    }
}
