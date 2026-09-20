import Foundation

/// A volume mounted over one of this Mac's Thunderbolt links — what R4 is
/// about, and what S3's second check row names.
public struct MountedVolume: Sendable, Equatable {
    /// The name the copy uses, e.g. `Vault`: the mount point's last component,
    /// which is what Finder shows.
    public var name: String
    /// Where it is mounted, e.g. `/Volumes/Vault`.
    public var mountPoint: String
    /// The source exactly as `mount` printed it. Technical: it belongs in
    /// `Copy Details`, never in a headline.
    public var source: String
    /// The port it came in on.
    public var portBSDName: String

    public init(name: String, mountPoint: String, source: String, portBSDName: String) {
        self.name = name
        self.mountPoint = mountPoint
        self.source = source
        self.portBSDName = portBSDName
    }
}

/// Which volumes are mounted over a Thunderbolt link right now.
///
/// Read-only: it runs `/sbin/mount` and parses what it prints. A file server
/// reached down the link RDMALink is about to change is the one thing that
/// would notice the interruption, so this is a gate at preflight and again
/// before Restore.
public enum MountedVolumes {

    /// Every volume mounted over any of these ports.
    public static func over(
        _ ports: [OperationPort],
        runner: CommandRunner = CommandRunner()
    ) throws -> [MountedVolume] {
        let output = try runner.run("/sbin/mount")
        guard output.succeeded else {
            throw CommandRunner.Failure.io(
                "/sbin/mount failed (\(output.exitStatus)): \(output.text)")
        }
        return parse(output.text, ports: ports)
    }

    /// Every volume mounted over one port.
    public static func over(
        _ port: OperationPort,
        runner: CommandRunner = CommandRunner()
    ) throws -> [MountedVolume] {
        try over([port], runner: runner)
    }

    /// Pure. `mount` prints one line per volume: `SOURCE on MOUNTPOINT (type, options)`.
    ///
    /// A line belongs to a port when its **source** names one of that port's
    /// link-local addresses or its interface scope — `%en6`, or `%25en6` where
    /// the source is a URL and the scope has been percent-encoded. The mount
    /// point is deliberately not matched: a volume called `en6` would not make
    /// it a Thunderbolt mount.
    static func parse(_ text: String, ports: [OperationPort]) -> [MountedVolume] {
        var found: [MountedVolume] = []
        for line in text.split(whereSeparator: \.isNewline) {
            // From the right: the trailing `(type, options)` first, then the
            // mount point, which is always an absolute path. A share whose own
            // name contains " on " would defeat a left-to-right split.
            guard let options = line.range(of: " (", options: .backwards) else { continue }
            let head = line[..<options.lowerBound]
            guard let split = head.range(of: " on /", options: .backwards) else { continue }
            let source = String(head[..<split.lowerBound])
            let mountPoint = String(head[split.lowerBound...].dropFirst(4))
            guard let port = ports.first(where: { matches(source: source, port: $0) }) else {
                continue
            }
            let name = URL(fileURLWithPath: mountPoint).lastPathComponent
            found.append(MountedVolume(
                name: name.isEmpty ? mountPoint : name,
                mountPoint: mountPoint,
                source: source,
                portBSDName: port.bsdName))
        }
        return found
    }

    /// The needles one port is recognised by in a mount source.
    static func needles(for port: OperationPort) -> [String] {
        ["%\(port.bsdName)", "%25\(port.bsdName)"] + port.linkLocalAddresses
    }

    static func matches(source: String, port: OperationPort) -> Bool {
        needles(for: port).contains { source.localizedCaseInsensitiveContains($0) }
    }
}
