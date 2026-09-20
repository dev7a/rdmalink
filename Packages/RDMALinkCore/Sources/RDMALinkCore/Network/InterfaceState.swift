import Foundation

/// One kernel network interface as `ifconfig -a` reports it.
///
/// This is the only place kernel bridge membership can be read: a port must be
/// out of *every* bridge, including a bridge that is down, before it can carry
/// RDMA. A "Disabled" service label in System Settings is not enough.
public struct InterfaceState: Sendable, Equatable, Codable {
    /// The BSD name, e.g. `en6` or `bridge0`.
    public var name: String
    /// The `UP` flag.
    public var isUp: Bool
    /// `status: active`.
    public var isActive: Bool
    /// BSD names listed as `member:` under this interface. Non-empty only for bridges.
    public var members: [String]
    /// Usable `fe80::` addresses, with the `%scope` suffix removed.
    /// Tentative, duplicated and detached addresses are left out.
    public var linkLocalAddresses: [String]
    /// Every `inet` and `inet6` address exactly as printed, scope suffix included.
    public var addresses: [String]

    public init(
        name: String,
        isUp: Bool = false,
        isActive: Bool = false,
        members: [String] = [],
        linkLocalAddresses: [String] = [],
        addresses: [String] = []
    ) {
        self.name = name
        self.isUp = isUp
        self.isActive = isActive
        self.members = members
        self.linkLocalAddresses = linkLocalAddresses
        self.addresses = addresses
    }

    /// True when this interface has bridge members of its own.
    public var isBridge: Bool { !members.isEmpty }
}

/// `ifconfig` would not say what the kernel has.
public enum InterfaceReadFailure: Error, Sendable, Equatable, CustomStringConvertible {
    case ifconfigFailed(exitStatus: Int32, output: String)

    public var description: String {
        switch self {
        case let .ifconfigFailed(exitStatus, output):
            return "/sbin/ifconfig -a failed (\(exitStatus)): \(output)"
        }
    }
}

/// Every interface the kernel reports, at one moment.
public struct InterfaceSnapshot: Sendable, Equatable, Codable {
    public var interfaces: [InterfaceState]
    /// When the snapshot was taken, so a stale read can be spotted.
    public var readAt: Date

    public init(interfaces: [InterfaceState], readAt: Date = Date()) {
        self.interfaces = interfaces
        self.readAt = readAt
    }

    public subscript(name: String) -> InterfaceState? {
        interfaces.first { $0.name == name }
    }

    /// The BSD names of every bridge listing `bsdName` as a member, down ones included.
    public func bridges(containing bsdName: String) -> [String] {
        interfaces.filter { $0.members.contains(bsdName) }.map(\.name)
    }

    /// Every interface that has members of its own.
    public var bridgeNames: [String] { interfaces.filter(\.isBridge).map(\.name) }

    /// Reads the live kernel state. Read-only: it runs `/sbin/ifconfig -a`.
    public static func read(using runner: CommandRunner = CommandRunner()) throws -> InterfaceSnapshot {
        let output = try runner.run("/sbin/ifconfig", ["-a"])
        guard output.succeeded else {
            throw InterfaceReadFailure.ifconfigFailed(exitStatus: output.exitStatus,
                                                      output: output.text)
        }
        return InterfaceSnapshot(interfaces: parse(output.text))
    }

    /// Parses `ifconfig -a` output.
    ///
    /// A line that starts in column zero and carries `flags=` opens an
    /// interface; indented lines belong to the one above.
    public static func parse(_ text: String) -> [InterfaceState] {
        var result: [InterfaceState] = []
        for line in text.split(whereSeparator: \.isNewline) {
            if line.first?.isWhitespace == false, let colon = line.firstIndex(of: ":"),
               line.contains("flags=") {
                let name = String(line[..<colon])
                let flags = line.split(separator: "<").dropFirst().first?
                    .split(separator: ">").first ?? ""
                result.append(InterfaceState(name: name,
                                             isUp: flags.split(separator: ",").contains("UP")))
            } else if !result.isEmpty {
                let index = result.count - 1
                let words = line.split(whereSeparator: \.isWhitespace)
                if words.count >= 2, words[0] == "member:" {
                    result[index].members.append(String(words[1]))
                }
                if words == ["status:", "active"] { result[index].isActive = true }
                if words.count >= 2, words[0] == "inet" || words[0] == "inet6" {
                    result[index].addresses.append(String(words[1]))
                }
                if words.count >= 2, words[0] == "inet6", words[1].hasPrefix("fe80:"),
                   !words.contains("tentative"), !words.contains("duplicated"),
                   !words.contains("detached") {
                    result[index].linkLocalAddresses.append(String(words[1].split(separator: "%")[0]))
                }
            }
        }
        return result
    }
}
