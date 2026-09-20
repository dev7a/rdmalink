//
//  RestartWatch.swift
//
//  Separates the two meanings of one reading.
//
//  `RDMAStatus.onAfterRestart` says the switch is on in NVRAM and no RDMA
//  devices are present. That is "turned on, restart still owed" before the
//  restart and R22's "this Mac doesn't actually offer RDMA over Thunderbolt"
//  after it — and the switch carries no timestamp to tell them apart.
//
//  So one thing is written down: the `kern.boottime` this Mac was in when
//  RDMALink first saw the switch on. If the Mac has booted since, the restart
//  has happened. The note is cleared the moment the switch reads off again,
//  and nothing else is remembered.
//
//  Conservative by construction: a first launch that already finds the switch
//  on says "On after you restart" once, and only calls it R22 after a further
//  restart. Being a restart late is honest; claiming R22 early is not.
//

import Darwin
import Foundation
import RDMALinkCore

enum RestartWatch {
    private static let switchSeenOnAtBootKey = "RDMASwitchSeenOnAtBoot"

    /// Records what this reading implies and answers whether this Mac has been
    /// restarted since RDMALink first saw the switch on.
    static func hasRestartedSinceSwitchOn(
        _ status: RDMAStatus,
        defaults: UserDefaults = .standard
    ) -> Bool {
        switch status {
        case .off:
            defaults.removeObject(forKey: switchSeenOnAtBootKey)
            return false
        case .on, .unknown:
            return false
        case .onAfterRestart:
            let boot = bootTime()
            guard let seen = defaults.object(forKey: switchSeenOnAtBootKey) as? Double else {
                defaults.set(boot, forKey: switchSeenOnAtBootKey)
                return false
            }
            // A second of slack: `kern.boottime` is adjusted when the clock is
            // corrected, and a one-second wobble is not a restart.
            return boot > seen + 1
        }
    }

    /// Seconds since the epoch at which this Mac booted.
    private static func bootTime() -> Double {
        var value = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &value, &size, nil, 0) == 0 else { return 0 }
        return Double(value.tv_sec)
    }
}
