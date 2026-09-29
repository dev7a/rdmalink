import Foundation
import Testing
@testable import RDMALinkCore

/// A signature that differs from another only in what `link` says.
private func sample(link: Int = 1) -> PortStateSignature {
    PortStateSignature(
        rows: [PortInventory.PortRow(receptacle: 1, bsdName: "en5", linkStatus: link)],
        enrichment: ChassisEnrichment(),
        interfaces: [],
        preferences: nil,
        notes: nil
    )
}

/// One wake-up of the diff: when, what the signature said, and whether the
/// store spoke.
private struct Wake {
    var second: Double
    var signature: PortStateSignature? = sample()
    var storeEvent = false
}

/// The seconds at which the gate owed the full read.
private func reads(_ wakes: [Wake]) -> [Double] {
    let start = ContinuousClock().now
    var gate = PortReadGate()
    return wakes.filter { wake in
        gate.shouldRead(
            signature: wake.signature, storeEvent: wake.storeEvent,
            at: start + .milliseconds(Int(wake.second * 1000))
        )
    }.map(\.second)
}

/// A wake-up every second from `from` through `to`, the signature unmoved.
private func still(_ from: Int, _ to: Int) -> [Wake] {
    (from...to).map { Wake(second: Double($0)) }
}

@Suite("The one-second state diff")
struct InventorySignatureTests {

    @Test("The first wake-up reads, and a still Mac is not read again until the backstop")
    func stillMacWaitsForTheBackstop() {
        // The first read is a change from nothing, so it settles like any
        // other, and the backstop counts from the last read the settling made.
        #expect(reads(still(0, 25)) == [0, 1, 2, 3, 4, 14, 24])
    }

    @Test("A moved signature reads at once, and keeps reading while it settles")
    func movedSignatureReadsAndSettles() {
        let moved = [7, 8, 9, 10, 11, 12].map { Wake(second: Double($0), signature: sample(link: 0)) }
        #expect(reads(still(0, 6) + moved) == [0, 1, 2, 3, 4, 7, 8, 9, 10, 11])
    }

    @Test("A store notification reads even when the signature has not moved")
    func storeEventReads() {
        let wakes = still(0, 6) + [Wake(second: 7, storeEvent: true)] + still(8, 13)
        #expect(reads(wakes) == [0, 1, 2, 3, 4, 7, 8, 9, 10, 11])
    }

    @Test("A signature that could not be read is a reason to read, every time")
    func unreadableSignatureReads() {
        let unreadable = [6, 20].map { Wake(second: Double($0), signature: nil) }
        // Coming back is a change of its own.
        #expect(reads(still(0, 5) + unreadable + still(21, 22)) == [0, 1, 2, 3, 4, 6, 20, 21, 22])
    }

    @Test("A file's mark moves when it is renamed over, and not when it is left alone")
    func fileMarkFollowsAtomicReplace() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "rdmalink-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "preferences.plist")

        #expect(FileMark.read(file.path) == nil)
        try Data("one".utf8).write(to: file, options: .atomic)
        let first = try #require(FileMark.read(file.path))
        let folderBefore = try #require(FileMark.read(folder.path))
        #expect(FileMark.read(file.path) == first)

        // Same size, written the way SCPreferences and the notes are written.
        try Data("two".utf8).write(to: file, options: .atomic)
        #expect(FileMark.read(file.path) != first)
        #expect(FileMark.read(folder.path) != folderBefore)
    }

    @Test("This Mac's signature reads, and holds still between two looks")
    func readsThisMacsSignature() throws {
        let notes = FileManager.default.temporaryDirectory
            .appending(path: "rdmalink-tests-\(UUID().uuidString)")
        let first = try #require(PortStateSignature.read(notesDirectory: notes))
        let names = Set(first.rows.map(\.bsdName))
        print("signature: \(first.rows.count) receptacles, \(first.interfaces.count) interface entries")
        #expect(first.interfaces.allSatisfy { names.contains($0.name) || $0.name.hasPrefix("bridge") })
        #expect(first.notes == nil)
        #expect(PortStateSignature.read(notesDirectory: notes) == first)
    }
}
