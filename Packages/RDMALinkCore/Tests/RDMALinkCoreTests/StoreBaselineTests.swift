import Foundation
import Testing
@testable import RDMALinkCore

/// A scratch folder that goes away with the test.
private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "rdmalink-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func permissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

/// A note with every field filled in, so a round trip proves the whole shape.
/// The timestamp is a whole second: notes are stored as ISO 8601.
private func sampleBaseline(port: String = "en6") -> PortBaseline {
    PortBaseline(
        bsdName: port,
        receptacle: 1,
        positionName: "Back, far left",
        bridges: [
            BridgeMembership(
                bridgeName: "bridge0",
                serviceIdentifier: "B0B0B0B0-0000-0000-0000-000000000001",
                displayName: "Thunderbolt Bridge",
                members: ["en5", "en6", "en7", "en8"],
                isActive: true),
            BridgeMembership(
                bridgeName: "bridge1",
                serviceIdentifier: nil,
                displayName: "Thunderbolt Bridge 2",
                members: ["en6"],
                isActive: false),
        ],
        existingService: ServiceRecord(
            identifier: "5E5E5E5E-0000-0000-0000-000000000002",
            name: "Thunderbolt Bridge",
            orderIndex: 3),
        ipv4: ProtocolConfiguration(isEnabled: false, configMethod: nil, hasManualAddresses: false),
        ipv6: ProtocolConfiguration(isEnabled: true, configMethod: "LinkLocal", hasManualAddresses: false),
        createdService: CreatedServiceRecord(
            identifier: "C0C0C0C0-0000-0000-0000-000000000003",
            interfaceBSDName: port,
            name: "RDMA — Back, far left",
            isEnabled: true,
            ipv4: ProtocolConfiguration(isEnabled: false, configMethod: nil,
                                        hasManualAddresses: false),
            ipv6: ProtocolConfiguration(isEnabled: true, configMethod: "LinkLocal",
                                        hasManualAddresses: false)),
        recordedAt: Date(timeIntervalSince1970: 1_756_909_260),
        systemBuild: "26B5086k")
}

@Suite("Undo notes")
struct StoreBaselineTests {

    @Test("A note reads back exactly as it was written")
    func roundTrips() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BaselineStore(directory: root.appending(path: "baselines"))
        let baseline = sampleBaseline()

        try store.save(baseline)
        #expect(try store.load(port: "en6") == baseline)
    }

    @Test("An adopted note has no history to put back")
    func adoptedNoteHasNoBridges() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BaselineStore(directory: root.appending(path: "baselines"))
        let adopted = PortBaseline.adopted(
            bsdName: "en7",
            receptacle: 2,
            positionName: "Back, far right",
            recordedAt: Date(timeIntervalSince1970: 1_756_909_260),
            systemBuild: "26B5086k")

        try store.save(adopted)
        let loaded = try store.load(port: "en7")
        #expect(loaded.isAdopted)
        #expect(loaded.bridges.isEmpty)
        #expect(loaded.createdServiceIdentifier == nil)
    }

    @Test("A return record reads back whole, and says what it is")
    func returnRecordRoundTrips() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BaselineStore(directory: root.appending(path: "baselines"))
        let returned = PortBaseline(
            bsdName: "en5", receptacle: 4, positionName: "Back, far left",
            existingService: ServiceRecord(identifier: "F0F0", name: "Thunderbolt 5"),
            returnedToBridge: BridgeReturn(bsdName: "bridge0", displayName: "Thunderbolt Bridge"),
            recordedAt: Date(timeIntervalSince1970: 1_758_382_823),
            systemBuild: "26B5086k")

        try store.save(returned)
        let loaded = try store.load(port: "en5")
        #expect(loaded == returned)
        #expect(loaded.isReturned)
        #expect(loaded.returnedToBridge?.name == "Thunderbolt Bridge")
        #expect(loaded.version == PortBaseline.currentVersion)
        #expect(!sampleBaseline().isReturned)
        #expect(!PortBaseline.adopted(bsdName: "en7", receptacle: 2,
                                      positionName: "Back, far right").isReturned)
    }

    @Test("A return record describes the port only while it is still in that bridge, bare")
    func returnRecordDescribesThePortWhileItHolds() {
        let returned = PortBaseline(
            bsdName: "en5", receptacle: 4, positionName: "Back, far left",
            returnedToBridge: BridgeReturn(bsdName: "bridge0", displayName: "Thunderbolt Bridge"))

        // §4.3: in the bridge it was put back into, with no service of its own.
        #expect(returned.describesTheReturnedPort(bridges: ["bridge0"], hasService: false))
        // Either read counts, and a second bridge changes nothing.
        #expect(returned.describesTheReturnedPort(bridges: ["bridge1", "bridge0"], hasService: false))
        // Taken out of that bridge again, or given a service: the record
        // describes nothing current.
        #expect(!returned.describesTheReturnedPort(bridges: [], hasService: false))
        #expect(!returned.describesTheReturnedPort(bridges: ["bridge1"], hasService: false))
        #expect(!returned.describesTheReturnedPort(bridges: ["bridge0"], hasService: true))
        // Only a return record can say this, whatever the port is doing.
        #expect(!sampleBaseline().describesTheReturnedPort(bridges: ["bridge0"], hasService: false))
        #expect(!PortBaseline.adopted(bsdName: "en7", receptacle: 2, positionName: "Back, far right")
            .describesTheReturnedPort(bridges: ["bridge0"], hasService: false))
    }

    @Test("A note written before the return field existed still loads, as not returned")
    func olderNoteLoadsWithoutTheField() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "baselines")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = BaselineStore(directory: directory)
        // Byte for byte the note Return to Bridge left on the rig on
        // 2026-09-20, before the field existed.
        let older = """
            {"bridges":[],"bsdName":"en5","isAdopted":false,"positionName":"Back, far left",\
            "receptacle":4,"recordedAt":"2026-09-20T15:40:23Z","systemBuild":"26B5086k","version":1}
            """
        try Data(older.utf8).write(to: directory.appending(path: "en5.json"))

        let loaded = try store.load(port: "en5")
        #expect(loaded.returnedToBridge == nil)
        #expect(!loaded.isReturned)
        #expect(loaded.version == 1)
        #expect(loaded.bridges.isEmpty)
    }

    @Test("A return record that claims a history is not a note")
    func returnRecordWithHistoryIsRefused() {
        var invented = sampleBaseline()
        invented.returnedToBridge = BridgeReturn(bsdName: "bridge0")
        #expect(throws: BaselineStoreError.self) { try invented.validate() }

        var adopted = PortBaseline.adopted(bsdName: "en7", receptacle: 2,
                                           positionName: "Back, far right")
        adopted.returnedToBridge = BridgeReturn(bsdName: "bridge0")
        #expect(throws: BaselineStoreError.self) { try adopted.validate() }

        var nameless = PortBaseline(bsdName: "en7", receptacle: 2, positionName: "Back, far right",
                                    returnedToBridge: BridgeReturn(bsdName: ""))
        #expect(throws: BaselineStoreError.self) { try nameless.validate() }
        nameless.returnedToBridge = BridgeReturn(bsdName: "bridge0")
        #expect(throws: Never.self) { try nameless.validate() }
    }

    @Test("An adopted note that claims a history is not a note")
    func adoptedNoteWithHistoryIsRefused() {
        var invented = sampleBaseline()
        invented.isAdopted = true
        #expect(throws: BaselineStoreError.self) { try invented.validate() }
    }

    @Test("The folder is the user's own, and so is every note")
    func writesPrivateFiles() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "baselines")
        let store = BaselineStore(directory: directory)

        try store.save(sampleBaseline())
        #expect(try permissions(directory) == 0o700)
        #expect(try permissions(directory.appending(path: "en6.json")) == 0o600)
    }

    @Test("A write leaves the folder holding notes and nothing else")
    func leavesNoTemporaryFiles() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "baselines")
        let store = BaselineStore(directory: directory)

        try store.save(sampleBaseline())
        try store.save(sampleBaseline())
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(contents == ["en6.json"])
    }

    @Test("Writing a note again replaces it whole")
    func replacesInPlace() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BaselineStore(directory: root.appending(path: "baselines"))

        try store.save(sampleBaseline())
        var updated = sampleBaseline()
        updated.createdService?.identifier = "D0D0D0D0-0000-0000-0000-000000000004"
        try store.save(updated)

        #expect(try store.load(port: "en6").createdServiceIdentifier ==
                "D0D0D0D0-0000-0000-0000-000000000004")
    }

    @Test("Listing, then forgetting")
    func listsAndDeletes() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BaselineStore(directory: root.appending(path: "baselines"))

        #expect(try store.list() == [])
        try store.save(sampleBaseline(port: "en7"))
        try store.save(sampleBaseline(port: "en6"))
        #expect(try store.list() == ["en6", "en7"])

        try store.delete(port: "en6")
        #expect(try store.list() == ["en7"])
        try store.delete(port: "en6")  // already gone counts as done
        #expect(throws: BaselineStoreError.missing("en6")) { try store.load(port: "en6") }
    }

    @Test("A note's name can only ever be an interface name")
    func refusesUnsafeNames() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BaselineStore(directory: root.appending(path: "baselines"))

        for name in ["../evil", "en6/../en7", "en 6", ".", "", "en6.json", "enormouslylonginterface"] {
            #expect(!PortBaseline.isValidBSDName(name), "\(name) must not be a note name")
            #expect(throws: BaselineStoreError.invalidPortName(name)) { try store.url(forPort: name) }
        }
        #expect(PortBaseline.isValidBSDName("en6"))
        #expect(PortBaseline.isValidBSDName("bridge0"))
    }

    @Test("A note can only ever claim a service on its own port")
    func refusesACreatedServiceOnAnotherPort() {
        // The notes are plain user-writable JSON. A note for en6 whose created
        // identifier has been hand-edited to the Wi-Fi service's would otherwise
        // decode cleanly and let Restore delete the only route out.
        var wrong = sampleBaseline()
        wrong.createdService?.interfaceBSDName = "en1"
        #expect(throws: BaselineStoreError.self) { try wrong.validate() }
    }

    @Test("A note from another schema is not read")
    func refusesAnotherSchema() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "baselines")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = BaselineStore(directory: directory)

        var future = sampleBaseline()
        future.version = 2
        let data = try JSONCoding.encoder().encode(future)
        try data.write(to: directory.appending(path: "en6.json"))

        #expect(throws: BaselineStoreError.unsupportedVersion(2)) { try store.load(port: "en6") }
    }

    @Test("A note that is not a note is said to be, not guessed at")
    func refusesDamagedNotes() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "baselines")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = BaselineStore(directory: directory)

        try Data("not a note".utf8).write(to: directory.appending(path: "en6.json"))
        #expect(throws: BaselineStoreError.self) { try store.load(port: "en6") }

        // A note about a different port, under this port's name.
        try JSONCoding.encoder().encode(sampleBaseline(port: "en7"))
            .write(to: directory.appending(path: "en5.json"))
        #expect(throws: BaselineStoreError.self) { try store.load(port: "en5") }
    }

    @Test("R14: the folder either takes a note or says why not")
    func probesWritability() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "baselines")
        let store = BaselineStore(directory: directory)

        let writable = store.checkWritable()
        #expect(writable.isWritable)
        // The probe makes the folder and leaves nothing behind.
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [])
        #expect(try permissions(directory) == 0o700)
    }

    @Test("R14: a folder that will not take a file")
    func reportsUnwritableFolder() throws {
        let root = try temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        let store = BaselineStore(directory: root.appending(path: "baselines"))

        let writability = store.checkWritable()
        #expect(!writability.isWritable)
        if case .notWritable = writability {} else {
            Issue.record("Expected an unwritable folder, got \(writability)")
        }
        // R14 comes before the first write, and nothing is written after it.
        #expect(throws: BaselineStoreError.self) { try store.save(sampleBaseline()) }
    }
}
