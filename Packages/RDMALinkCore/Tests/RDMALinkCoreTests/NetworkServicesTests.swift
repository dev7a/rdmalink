import Testing
@testable import RDMALinkCore

private let ipv4Off = ProtocolConfiguration(isEnabled: false, configMethod: "DHCP",
                                            hasManualAddresses: false)
private let ipv6LinkLocal = ProtocolConfiguration(isEnabled: true, configMethod: "LinkLocal",
                                                  hasManualAddresses: false)

private func service(
    id: String = "ABC-123",
    name: String = "Thunderbolt Bridge Free",
    interface: String? = "en6",
    enabled: Bool = true,
    ipv4: ProtocolConfiguration? = ipv4Off,
    ipv6: ProtocolConfiguration? = ipv6LinkLocal
) -> NetworkServiceInfo {
    NetworkServiceInfo(serviceID: id, name: name, interfaceBSDName: interface,
                       isEnabled: enabled, ipv4: ipv4, ipv6: ipv6)
}

@Suite("Reading what a port is set up as")
struct PortConfigurationTests {
    @Test("Standalone, IPv4 off, IPv6 link-local only is a full match")
    func recognisesWhatRDMALinkWouldHaveMade() {
        #expect(NetworkServices.classify(services: [service()], bridges: [])
            == .readyForRDMA(serviceID: "ABC-123"))
    }

    @Test("A port with no service of its own is unconfigured, bridges and all")
    func reportsAnUnconfiguredPort() {
        #expect(NetworkServices.classify(services: [], bridges: ["bridge0"])
            == .unconfigured(bridges: ["bridge0"]))
        #expect(NetworkServices.classify(services: [], bridges: [])
            == .unconfigured(bridges: []))
    }

    @Test("IPv6 set to Automatic is a near match, and is never adjusted")
    func reportsTheDifference() {
        let automatic = service(ipv6: ProtocolConfiguration(isEnabled: true,
                                                           configMethod: "Automatic",
                                                           hasManualAddresses: false))
        #expect(NetworkServices.classify(services: [automatic], bridges: [])
            == .nearMatch(serviceID: "ABC-123",
                          differences: [.ipv6NotLinkLocal(method: "Automatic")]))
    }

    @Test("Still in a bridge can never be a full match")
    func countsBridgeMembershipAsADifference() {
        #expect(NetworkServices.classify(services: [service()], bridges: ["bridge0", "bridge1"])
            == .nearMatch(serviceID: "ABC-123",
                          differences: [.stillInBridge("bridge0"), .stillInBridge("bridge1")]))
    }

    @Test("A disabled service, or one with IPv6 off, is not ready")
    func countsTheOtherDifferences() {
        #expect(NetworkServices.classify(services: [service(enabled: false)], bridges: [])
            == .nearMatch(serviceID: "ABC-123", differences: [.serviceDisabled]))
        #expect(NetworkServices.classify(services: [service(ipv6: nil)], bridges: [])
            == .nearMatch(serviceID: "ABC-123", differences: [.ipv6Disabled]))
        let ipv4On = ProtocolConfiguration(isEnabled: true, configMethod: "DHCP",
                                           hasManualAddresses: false)
        #expect(NetworkServices.classify(services: [service(ipv4: ipv4On)], bridges: [])
            == .nearMatch(serviceID: "ABC-123", differences: [.ipv4NotOff(method: "DHCP")]))
    }

    @Test("A fixed IPv4 address is someone's deliberate setup — R16, not a near match")
    func refusesToTouchAStaticAddress() {
        let manual = ProtocolConfiguration(isEnabled: true, configMethod: "Manual",
                                           hasManualAddresses: true)
        #expect(NetworkServices.classify(services: [service(ipv4: manual)], bridges: [])
            == .foreign(serviceID: "ABC-123", reason: .staticIPv4Address))
        // Addresses carried without the Manual method count just the same.
        let addressed = ProtocolConfiguration(isEnabled: true, configMethod: "INFORM",
                                              hasManualAddresses: true)
        #expect(NetworkServices.classify(services: [service(ipv4: addressed)], bridges: [])
            == .foreign(serviceID: "ABC-123", reason: .staticIPv4Address))
    }

    @Test("IPv4 counts as off when it is absent, disabled, or explicitly off")
    func knowsWhatOffMeans() {
        #expect(NetworkServices.isOff(nil))
        #expect(NetworkServices.isOff(ipv4Off))
        #expect(NetworkServices.isOff(ProtocolConfiguration(isEnabled: true, configMethod: "None",
                                                            hasManualAddresses: false)))
        #expect(!NetworkServices.isOff(ProtocolConfiguration(isEnabled: true, configMethod: "DHCP",
                                                             hasManualAddresses: false)))
    }

    @Test("Every service on an interface is found, because there can be more than one")
    func findsTheServicesOnAPort() {
        let services = [service(id: "one", interface: "en5"), service(id: "two", interface: "en6"),
                        service(id: "three", interface: "en6")]
        #expect(NetworkServices.services(for: "en6", in: services).map(\.serviceID)
            == ["two", "three"])
        #expect(NetworkServices.services(for: "en9", in: services).isEmpty)
    }

    @Test("Two services on one port is not what RDMALink would have made")
    func countsASecondService() {
        #expect(NetworkServices.classify(services: [service(id: "one"), service(id: "two")],
                                         bridges: [])
            == .nearMatch(serviceID: "one", differences: [.severalServices(count: 2)]))
    }

    @Test("A fixed address on the port's second service is still a fixed address")
    func looksAtEveryServiceForAStaticAddress() {
        let manual = ProtocolConfiguration(isEnabled: true, configMethod: "Manual",
                                           hasManualAddresses: true)
        #expect(NetworkServices.classify(
            services: [service(id: "one"), service(id: "two", ipv4: manual)], bridges: [])
            == .foreign(serviceID: "two", reason: .staticIPv4Address))
    }
}
