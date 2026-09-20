import Foundation
import SystemConfiguration
import Testing
@testable import RDMALinkCore

@Suite("The private bridge SPI, probed not assumed")
struct BridgeSPITests {
    @Test("Thirteen symbols, eleven plain and two only with a leading underscore")
    func probesTheWholeSPI() {
        #expect(BridgeSPI.symbolNames.count == 13)
        #expect(BridgeSPI.plainSymbolNames.count == 11)
        #expect(BridgeSPI.underscoreSymbolNames == [
            "_SCBridgeInterfaceCopyActive",
            "_SCBridgeInterfaceUpdateConfiguration",
        ])
        #expect(Set(BridgeSPI.symbolNames).count == 13)
        #expect(BridgeSPI.plainSymbolNames.allSatisfy { $0.hasPrefix("SCBridgeInterface") })
    }

    @Test("The probe answers the same way every time")
    func cachesTheProbe() {
        let first = BridgeSPI.availability
        #expect(first == BridgeSPI.availability)
        #expect(Set(first.resolved).isDisjoint(with: Set(first.missing)))
        #expect(first.resolved.count + first.missing.count == BridgeSPI.symbolNames.count)
    }

    @Test("What this Mac actually has", .tags(.liveRead))
    func reportsWhatResolvedHere() {
        let availability = BridgeSPI.availability
        print("BridgeSPI resolved (\(availability.resolved.count)/13): "
            + availability.resolved.joined(separator: ", "))
        print("BridgeSPI missing: "
            + (availability.missing.isEmpty ? "none" : availability.missing.joined(separator: ", ")))
        print("BridgeSPI canEditMembership: \(availability.canEditMembership), "
            + "canUpdateConfiguration: \(availability.canUpdateConfiguration)")
        // macOS 27.2 has all thirteen. If a future build drops one, the app
        // falls back to a supervised System Settings hand-off rather than guess.
        #expect(availability.canEditMembership)
    }

    @Test("A missing symbol is a refusal, never a crash")
    func reportsAMissingSymbol() {
        let error = BridgeSPIError.symbolMissing("SCBridgeInterfaceCopyAll")
        #expect(error.description
            == "SCBridgeInterfaceCopyAll is not available on this version of macOS")
    }

    @Test("Reading the bridges on this Mac changes nothing", .tags(.liveRead))
    func readsBridgesReadOnly() throws {
        guard BridgeSPI.availability.canEditMembership else {
            print("BridgeSPI: member editing is not available on this build")
            return
        }
        let preferences = try #require(SCPreferencesCreate(nil, "RDMALink tests" as CFString, nil))
        let bridges = try BridgeSPI.bridges(in: preferences)
        for bridge in bridges {
            print("bridge \(bridge.bsdName) (\(bridge.displayName ?? "no display name")): "
                + (bridge.members.isEmpty ? "no members" : bridge.members.joined(separator: ", ")))
            // Proves SCBridgeInterfaceRef really is an SCNetworkInterfaceRef.
            #expect(!bridge.bsdName.isEmpty)
        }
        print("BridgeSPI stored bridges: \(bridges.count)")
    }

    @Test("The kernel's live bridges, which the stored ones need not match", .tags(.liveRead))
    func readsActiveBridges() throws {
        // `_SCBridgeInterfaceCopyActive` is its own dlsym probe: gating this on
        // `canUpdateConfiguration` would fail on a macOS that kept one and
        // dropped the other, and skip silently on the mirror case.
        guard BridgeSPI.availability.canReadActiveBridges else { return }
        let active = try BridgeSPI.activeBridges()
        for bridge in active {
            print("active bridge \(bridge.bsdName): "
                + (bridge.members.isEmpty ? "no members" : bridge.members.joined(separator: ", ")))
            #expect(!bridge.bsdName.isEmpty)
        }
        print("BridgeSPI active bridges: \(active.count)")
        // Whatever the SPI says, the kernel is the truth: membership is read
        // back through ifconfig after every change.
        let snapshot = try InterfaceSnapshot.read()
        for bridge in active {
            #expect(snapshot[bridge.bsdName] != nil)
        }
    }

    @Test("The interfaces a bridge could take", .tags(.liveRead))
    func readsAvailableMembers() throws {
        guard BridgeSPI.availability.resolved
            .contains("SCBridgeInterfaceCopyAvailableMemberInterfaces") else { return }
        let preferences = try #require(SCPreferencesCreate(nil, "RDMALink tests" as CFString, nil))
        let available = try BridgeSPI.availableMemberInterfaces(in: preferences)
        print("BridgeSPI available members (\(available.count)): "
            + available.joined(separator: ", "))
    }

    @Test("Removing a member that isn't one writes nothing")
    func refusesToRemoveANonMember() throws {
        guard BridgeSPI.availability.canEditMembership else { return }
        let preferences = try #require(SCPreferencesCreate(nil, "RDMALink tests" as CFString, nil))
        let bridges = try BridgeSPI.bridges(in: preferences)
        guard let first = bridges.first else { return }
        let bridge = try BridgeSPI.bridge(serviceIdentifier: nil, bsdName: first.bsdName,
                                          in: preferences)
        // "en999" is never a member of anything, so this exercises the guard and
        // returns before SCBridgeInterfaceSetMemberInterfaces is reached. The
        // session is read-only and is never committed either way.
        #expect(throws: BridgeSPIError.memberNotFound(bsdName: "en999",
                                                      bridge: first.bsdName)) {
            try BridgeSPI.removeMember(bsdName: "en999", from: bridge)
        }
    }

    @Test("An unknown bridge is named, not guessed at")
    func refusesAnUnknownBridge() throws {
        guard BridgeSPI.availability.canEditMembership else { return }
        let preferences = try #require(SCPreferencesCreate(nil, "RDMALink tests" as CFString, nil))
        #expect(throws: BridgeSPIError.bridgeNotFound("bridge99")) {
            try BridgeSPI.bridge(serviceIdentifier: nil, bsdName: "bridge99", in: preferences)
        }
    }

    @Test("A bridge is found by the identifier the note recorded, not its name",
          .tags(.liveRead))
    func resolvesByServiceIdentifier() throws {
        guard BridgeSPI.availability.canEditMembership else { return }
        let preferences = try #require(SCPreferencesCreate(nil, "RDMALink tests" as CFString, nil))
        let bridges = try BridgeSPI.bridges(in: preferences)
        guard let first = bridges.first else { return }
        let services = NetworkServices.read(from: preferences)
        guard let service = services.first(where: { $0.interfaceBSDName == first.bsdName })
        else { return }
        // `bridgeN` names are kernel-allocated and not stable across a delete
        // and recreate, so the identifier has to win over a stale name.
        let resolved = try BridgeSPI.bridge(serviceIdentifier: service.serviceID,
                                            bsdName: "bridge99", in: preferences)
        #expect(try BridgeSPI.describe(resolved).bsdName == first.bsdName)
    }
}

extension Tag {
    /// Reads real system state. Never writes any of it.
    @Tag static var liveRead: Self
}
