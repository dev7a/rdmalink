import Foundation
import Security
import SystemConfiguration
import Testing
@testable import RDMALinkCore

@Suite("The one authorized burst")
struct AuthorizedSessionTests {
    @Test("configd's right, not the Network pane's")
    func namesTheRightRight() {
        #expect(AuthorizedSession.right == "system.services.systemconfiguration.network")
    }

    @Test("The right resolves through authenticate-admin-nonshared", .tags(.liveRead))
    func readsTheRightsDefinition() throws {
        // A read of the policy database. It asks for nothing and prompts for nothing.
        var definition: CFDictionary?
        let status = AuthorizationRightGet(AuthorizedSession.right, &definition)
        guard status == errAuthorizationSuccess, let rule = definition as? [String: Any] else {
            print("Authorization right \(AuthorizedSession.right) is not defined here (\(status))")
            return
        }
        print("\(AuthorizedSession.right): \(rule)")
        // One of several alternatives with k-of-n 1: root, an entitlement, the
        // setup user, or an administrator. The last is the one a person hits,
        // and it is non-shared and lasts about thirty seconds — the reason
        // every write of one operation happens in a single burst.
        let alternatives = try #require(rule["rule"] as? [String])
        #expect(alternatives.contains("authenticate-admin-nonshared"))
    }

    @Test("SCError codes are named, not guessed at")
    func mapsTheStatusCodes() {
        #expect(kSCStatusAccessError == 1003)
        #expect(NetworkConfigurationError.isBusy(Int32(kSCStatusLocked)))
        #expect(NetworkConfigurationError.isBusy(Int32(kSCStatusPrefsBusy)))
        #expect(NetworkConfigurationError.isBusy(Int32(kSCStatusNeedLock)))
        // Permission denied is not somebody else writing; it is R6's territory.
        #expect(!NetworkConfigurationError.isBusy(Int32(kSCStatusAccessError)))
        #expect(!NetworkConfigurationError.isBusy(Int32(kSCStatusFailed)))
    }

    @Test("Every failure carries the reason macOS gave")
    func describesItsFailures() {
        let busy = NetworkConfigurationError.busy(step: "Lock network preferences",
                                                  code: Int32(kSCStatusPrefsBusy))
        #expect(busy.scStatus == Int32(kSCStatusPrefsBusy))
        #expect(busy.description.hasPrefix("Lock network preferences: "))
        #expect(!NetworkConfigurationError.message(Int32(kSCStatusAccessError)).isEmpty)
        print("kSCStatusAccessError: \(NetworkConfigurationError.message(Int32(kSCStatusAccessError)))")

        let cancelled = NetworkConfigurationError.authorizationCancelled(errAuthorizationCanceled)
        #expect(cancelled.scStatus == nil)
        #expect(cancelled.description == "Authorization cancelled (-60006)")
        #expect(NetworkConfigurationError.missing("the interface en6").description
            == "Missing the interface en6")
    }

    @Test("Reading the stored services needs no authorization at all", .tags(.liveRead))
    func readsServicesWithoutAPrompt() throws {
        let services = try NetworkServices.read(clientName: "RDMALink tests")
        for service in services.prefix(12) {
            print("service \(service.serviceID) \"\(service.name)\" "
                + "on \(service.interfaceBSDName ?? "no interface") "
                + "enabled=\(service.isEnabled) "
                + "ipv4=\(service.ipv4?.configMethod ?? "-")/\(service.ipv4?.isEnabled == true) "
                + "ipv6=\(service.ipv6?.configMethod ?? "-")/\(service.ipv6?.isEnabled == true)")
        }
        print("Services: \(services.count)")
        #expect(services.allSatisfy { !$0.serviceID.isEmpty })
    }
}
