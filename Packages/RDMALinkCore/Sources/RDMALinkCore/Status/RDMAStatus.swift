import Foundation

/// Whether this Mac has RDMA over Thunderbolt switched on, and whether the
/// RDMA devices have actually turned up.
///
/// The switch itself is not the app's to flip: it lives in System Settings and
/// needs a restart. RDMALink only reports what it finds, and re-checks.
public enum RDMAStatus: Sendable, Equatable {
    /// Neither NVRAM route could be read, so nothing is claimed.
    case unknown
    /// The switch is off.
    case off
    /// The switch is on in NVRAM, but no RDMA devices are present yet —
    /// normally because the Mac has not been restarted since it was turned on.
    /// After a restart this same reading is what R22 describes: on, but this
    /// Mac does not offer RDMA over Thunderbolt. Deciding between the two needs
    /// the boot time, which belongs to the screen, not to the reading.
    case onAfterRestart
    /// The switch is on and these RDMA devices are present, one per
    /// Thunderbolt controller.
    case on(devices: [String])

    /// The deep link to System Settings › Privacy & Security › Developer Tools,
    /// where the switch lives.
    public static let developerToolsSettingsLink =
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_DevTools"

    /// The same deep link, ready to open.
    public static let developerToolsSettingsURL = URL(string: developerToolsSettingsLink)!

    /// Reads the switch and the device list.
    ///
    /// Read-only: it reads `rdma-enable` from the IORegistry `options` node,
    /// falls back to `nvram -p`, and lists devices with `ibv_devices`. It never
    /// throws — a Mac that cannot answer is `unknown`, which the hub says out
    /// loud rather than papering over.
    public static func read(runner: CommandRunner = CommandRunner()) -> RDMAStatus {
        switch RDMASwitch.read(runner: runner) {
        case .unknown:
            return .unknown
        case .off:
            return .off
        case .on:
            let devices = RDMADevices.read(runner: runner)
            return devices.isEmpty ? .onAfterRestart : .on(devices: devices)
        }
    }

    /// The devices this reading found, which is empty unless the status is `on`.
    public var devices: [String] {
        if case .on(let devices) = self { return devices }
        return []
    }
}
