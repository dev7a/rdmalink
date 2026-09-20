import Testing
@testable import RDMALinkCore

@Suite("Hardware model")
struct InventoryHardwareTests {

    @Test("The catalogue names the Macs the spec draws")
    func catalogueNamesKnownMacs() {
        #expect(HardwareModel.catalog["Mac15,14"]
            == HardwareModel.KnownMac(marketingName: "Mac Studio", archetype: .studioSix))
        #expect(HardwareModel.catalog["Mac16,9"]
            == HardwareModel.KnownMac(marketingName: "Mac Studio", archetype: .studioFour))
        #expect(HardwareModel.catalog["Mac16,11"]
            == HardwareModel.KnownMac(marketingName: "Mac mini", archetype: .mini))
        #expect(HardwareModel.catalog["Mac16,6"]
            == HardwareModel.KnownMac(marketingName: "MacBook Pro", archetype: .notebook))
        #expect(HardwareModel.catalog["Mac17,1"]?.archetype == .notebook)
    }

    @Test("An identifier nobody has checked is unknown, not guessed")
    func unknownIdentifierStaysUnknown() {
        #expect(HardwareModel.catalog["Mac99,99"] == nil)
        // A Mac Studio identifier that does not exist yet must not be inferred
        // from the ones that do.
        #expect(HardwareModel.catalog["Mac16,10"]?.archetype == .mini)
        #expect(HardwareModel.catalog["Mac15,13"] == nil)
    }

    @Test("The chip name drops Apple's prefix and nothing else")
    func chipNameStripsPrefix() {
        #expect(HardwareModel.chipName(fromBrandString: "Apple M3 Ultra") == "M3 Ultra")
        #expect(HardwareModel.chipName(fromBrandString: "Apple M4 Pro") == "M4 Pro")
        #expect(HardwareModel.chipName(fromBrandString: " Apple M5 \n") == "M5")
        #expect(HardwareModel.chipName(fromBrandString: "M5 Ultra") == "M5 Ultra")
        #expect(HardwareModel.chipName(fromBrandString: "") == "")
    }

    @Test("An unrecognized Mac is still a working Mac")
    func unrecognizedModelIsFunctional() {
        let model = HardwareModel(
            identifier: "Mac99,99", marketingName: "Mac", chip: "M9", archetype: .unknown
        )
        #expect(!model.isRecognized)
        #expect(model.marketingName == "Mac")
    }
}
