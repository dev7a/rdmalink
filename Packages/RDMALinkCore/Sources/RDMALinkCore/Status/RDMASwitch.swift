import Foundation
import IOKit

/// Reads the `rdma-enable` NVRAM variable — the system switch behind
/// System Settings › Privacy & Security › Developer Tools › RDMA over
/// Thunderbolt. The app never writes it; it only reports what it says.
enum RDMASwitch {

    /// What NVRAM says about the switch.
    enum State: Sendable, Equatable {
        /// The variable says the switch is on.
        case on
        /// The variable says off, or was never written.
        case off
        /// Neither NVRAM route could be read, or the value made no sense.
        case unknown
    }

    /// The IORegistry path of the node that carries the NVRAM variables.
    static let optionsPath = "IODeviceTree:/options"
    /// The variable name. Public key, load-bearing.
    static let variableName = "rdma-enable"
    /// The fallback reader, used only when the IORegistry node is unreadable.
    static let nvramToolPath = "/usr/sbin/nvram"

    /// What one attempt at reading the variable found.
    enum Reading: Sendable, Equatable {
        /// The variable is there and this is what it says.
        case value(String)
        /// The store is readable and holds no such variable.
        case absent
        /// The store, or this variable, could not be read.
        case unreadable
    }

    /// Reads the switch: the IORegistry `options` node first, `nvram -p` after.
    static func read(runner: CommandRunner) -> State {
        switch readFromIORegistry() {
        case .value(let text):
            return parse(text)
        case .absent:
            // The node is there and the variable is not: it was never turned on.
            return .off
        case .unreadable:
            break
        }
        switch readFromNVRAMTool(runner: runner) {
        case .value(let text): return parse(text)
        case .absent: return .off
        case .unreadable: return .unknown
        }
    }

    /// Reads the variable out of `IODeviceTree:/options`.
    static func readFromIORegistry() -> Reading {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, optionsPath)
        guard entry != IO_OBJECT_NULL else { return .unreadable }
        defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(
            entry, variableName as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else {
            return .absent
        }
        guard let text = describe(value) else { return .unreadable }
        return .value(text)
    }

    /// Reads the variable out of the `nvram -p` listing.
    static func readFromNVRAMTool(runner: CommandRunner) -> Reading {
        guard let output = try? runner.run(nvramToolPath, ["-p"]), output.succeeded else { return .unreadable }
        guard let text = parseNVRAMListing(output.text) else { return .absent }
        return .value(text)
    }

    /// Turns the property value into text. NVRAM hands back data far more
    /// often than a string — on this Mac `rdma-enable` is the single byte
    /// `0x31`, which is the character `1`.
    static func describe(_ value: CFTypeRef) -> String? {
        if let data = value as? Data { return String(decoding: data, as: UTF8.self) }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }  // also CFBoolean
        return nil
    }

    /// Reads one variable out of the `nvram -p` listing, whose lines are
    /// `name<tab>value`.
    static func parseNVRAMListing(_ text: String, variable: String = variableName) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            guard line[..<tab] == variable else { continue }
            return String(line[line.index(after: tab)...])
        }
        return nil
    }

    /// Reads a stored NVRAM value as a switch position. Unset and empty count
    /// as off; anything unrecognized is `unknown`, because guessing at a system
    /// switch is exactly what this app does not do.
    static func parse(_ text: String) -> State {
        let value = text
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch value {
        case "1", "%01", "true", "yes", "on": return .on
        case "", "0", "%00", "false", "no", "off": return .off
        default: return .unknown
        }
    }
}
