import Foundation

/// Lists the RDMA devices macOS has published, one per Thunderbolt controller.
/// They only appear after the restart that the NVRAM switch asks for, which is
/// what separates `onAfterRestart` from `on`.
enum RDMADevices {

    /// The listing tool that ships with macOS.
    static let toolPath = "/usr/bin/ibv_devices"

    /// Reads the device list. A missing tool, a nonzero exit or a refused run
    /// all mean the same thing here: no devices are present.
    static func read(runner: CommandRunner) -> [String] {
        guard let output = try? runner.run(toolPath), output.succeeded else { return [] }
        return parse(output.text)
    }

    /// Parses the two-column `ibv_devices` listing:
    ///
    /// ```
    ///     device          	   node GUID
    ///     ------          	----------------
    ///     rdma_en2        	c03b3b8fe481ac05
    /// ```
    ///
    /// A row is a device name and a hexadecimal node GUID, which is precise
    /// enough to drop the header and the rule under it without matching on
    /// the word `device`.
    static func parse(_ text: String) -> [String] {
        var devices: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let columns = line.split(whereSeparator: \.isWhitespace)
            guard columns.count == 2 else { continue }
            let name = String(columns[0])
            let guid = columns[1]
            guard isDeviceName(name), isNodeGUID(guid) else { continue }
            devices.append(name)
        }
        return devices
    }

    /// A device name such as `rdma_en2`: a letter, then letters, digits and
    /// underscores.
    static func isDeviceName(_ value: String) -> Bool {
        guard let first = value.first, first.isLetter else { return false }
        return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// A node GUID: eight to thirty-two hexadecimal digits.
    static func isNodeGUID(_ value: Substring) -> Bool {
        (8...32).contains(value.count) && value.allSatisfy(\.isHexDigit)
    }
}
