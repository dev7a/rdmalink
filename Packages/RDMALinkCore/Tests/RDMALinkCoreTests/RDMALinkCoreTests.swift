import Testing
@testable import RDMALinkCore

@Test func versionIsSet() {
    #expect(!RDMALinkCore.version.isEmpty)
}
