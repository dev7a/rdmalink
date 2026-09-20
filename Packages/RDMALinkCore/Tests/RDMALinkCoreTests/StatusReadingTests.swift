import Foundation
import Testing
@testable import RDMALinkCore

// The `ibv_devices` listing, copied from a Mac Studio M3 Ultra on macOS 27.2.
private let deviceListing = """
    device          \t   node GUID
    ------          \t----------------
    rdma_en2        \tc03b3b8fe481ac05
    rdma_en3        \tc13b3b8fe481ac05
    rdma_en4        \tc23b3b8fe481ac05
    rdma_en5        \tc33b3b8fe481ac05
    rdma_en6        \tc43b3b8fe481ac05
    rdma_en7        \tc53b3b8fe481ac05
"""

@Suite("RDMA device listing")
struct RDMADeviceParsingTests {

    @Test("Every device on a Mac with RDMA on")
    func readsRealListing() {
        #expect(RDMADevices.parse(deviceListing) ==
                ["rdma_en2", "rdma_en3", "rdma_en4", "rdma_en5", "rdma_en6", "rdma_en7"])
    }

    @Test("The header and the rule under it are not devices")
    func dropsHeader() {
        #expect(RDMADevices.parse("    device          \t   node GUID\n    ------ \t----------------") == [])
    }

    @Test("No devices reads as no devices")
    func handlesEmptyListing() {
        #expect(RDMADevices.parse("") == [])
        #expect(RDMADevices.parse("No IB devices found\n") == [])
    }

    @Test("A row needs a name and a GUID")
    func needsBothColumns() {
        #expect(RDMADevices.parse("    rdma_en2\n") == [])
        #expect(RDMADevices.parse("    rdma_en2 \tnot-a-guid\n") == [])
        #expect(RDMADevices.parse("    rdma_en2 \tc03b3b8fe481ac05 extra\n") == [])
        #expect(RDMADevices.parse("    2rdma \tc03b3b8fe481ac05\n") == [])
    }
}

@Suite("The rdma-enable switch")
struct RDMASwitchParsingTests {

    @Test("On, in every spelling NVRAM uses")
    func readsOn() {
        for value in ["1", "%01", "true", "yes", "on", "  1  ", "1\0", "ON"] {
            #expect(RDMASwitch.parse(value) == .on, "\(value) should read as on")
        }
    }

    @Test("Off, and never written counts as off")
    func readsOff() {
        for value in ["0", "%00", "false", "no", "off", "", "   "] {
            #expect(RDMASwitch.parse(value) == .off, "\(value) should read as off")
        }
    }

    @Test("Anything else is not guessed at")
    func refusesToGuess() {
        for value in ["2", "maybe", "%02", "enabled"] {
            #expect(RDMASwitch.parse(value) == .unknown, "\(value) should read as unknown")
        }
    }

    @Test("One variable out of the nvram -p listing")
    func readsListing() {
        let listing = """
        SystemAudioVolume\t_
        rdma-enable\t1
        boot-args\t-v
        """
        #expect(RDMASwitch.parseNVRAMListing(listing) == "1")
        #expect(RDMASwitch.parseNVRAMListing(listing, variable: "boot-args") == "-v")
        #expect(RDMASwitch.parseNVRAMListing(listing, variable: "rdma") == nil)
        #expect(RDMASwitch.parseNVRAMListing("") == nil)
    }

    @Test("NVRAM hands back data far more often than a string")
    func readsEveryPropertyType() {
        #expect(RDMASwitch.describe(Data([0x31]) as CFTypeRef) == "1")
        #expect(RDMASwitch.describe("1" as CFTypeRef) == "1")
        #expect(RDMASwitch.describe(NSNumber(value: 1)) == "1")
    }
}

@Suite("RDMA status")
struct RDMAStatusTests {

    @Test("The deep link is the one System Settings answers to")
    func carriesTheDeepLink() {
        #expect(RDMAStatus.developerToolsSettingsLink ==
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_DevTools")
        #expect(RDMAStatus.developerToolsSettingsURL.absoluteString ==
                RDMAStatus.developerToolsSettingsLink)
    }

    @Test("Only an on status has devices")
    func exposesDevices() {
        #expect(RDMAStatus.on(devices: ["rdma_en2"]).devices == ["rdma_en2"])
        #expect(RDMAStatus.onAfterRestart.devices.isEmpty)
        #expect(RDMAStatus.off.devices.isEmpty)
        #expect(RDMAStatus.unknown.devices.isEmpty)
    }
}
