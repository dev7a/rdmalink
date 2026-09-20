import Testing
@testable import RDMALinkCore

/// Reads the Mac the tests are running on.
///
/// These assert only what must hold on *any* Mac, so a machine with no
/// Thunderbolt hardware passes them too. They print what they found, because
/// the printed table is the record of what this hardware actually reports.
@Suite("Inventory on this Mac")
struct InventoryLiveTests {

    @Test("This Mac identifies itself")
    func readsThisMac() {
        let model = HardwareModel.read()
        print("model: \(model.identifier) · \(model.marketingName) · \(model.chip) · \(model.archetype.rawValue)")
        #expect(!model.identifier.isEmpty)
        #expect(!model.marketingName.isEmpty)
    }

    @Test("This Mac's Thunderbolt receptacles read cleanly")
    func readsThisMacsPorts() throws {
        let model = HardwareModel.read()
        let ports = try PortInventory.read(archetype: model.archetype)
        print("ports on \(model.identifier) (\(model.archetype.rawValue)):")
        for port in ports {
            print("  receptacle \(port.receptacle) · \(port.bsdName) · link \(port.link) · "
                + "\(port.face.map(\.rawValue) ?? "no face") · \(port.positionName)")
        }
        #expect(ports.map(\.receptacle) == ports.map(\.receptacle).sorted())
        #expect(Set(ports.map(\.id)).count == ports.count)
        #expect(ports.allSatisfy { !$0.bsdName.isEmpty })
        #expect(ports.allSatisfy { $0.id == $0.bsdName })
        #expect(ports.allSatisfy { !$0.positionName.isEmpty })
        #expect(ports.allSatisfy { $0.isThunderbolt })
        #expect(ports.allSatisfy { $0.bridges.isEmpty && $0.linkLocal.isEmpty })
    }

    @Test("The raw link status this Mac reports")
    func readsRawLinkStatus() throws {
        let rows = try PortInventory.readRows()
        for row in rows.sorted(by: { $0.receptacle < $1.receptacle }) {
            print("  IOLocation \(row.receptacle) · BSD Name \(row.bsdName) · "
                + "IOLinkStatus \(row.linkStatus)")
        }
        let enrichment = ChassisProbe.read()
        for receptacle in enrichment.byReceptacle.keys.sorted() {
            let facts = enrichment.byReceptacle[receptacle]
            print("  receptacle \(receptacle) · position \(String(describing: facts?.position)) · "
                + "attached \(String(describing: facts?.deviceAttached))")
        }
        for position in enrichment.cabledPositions {
            print("  cabled USB-only receptacle · \(position)")
        }
        #expect(rows.allSatisfy { $0.receptacle > 0 })
    }

    @Test("The watcher ticks and tears itself down", .timeLimit(.minutes(1)))
    func watcherTicksAndStops() async {
        let watcher = LinkWatcher(bsdNames: ["en0"], pollInterval: .milliseconds(20))
        var ticks = 0
        for await _ in watcher.changes() {
            ticks += 1
            if ticks == 3 { break }
        }
        #expect(ticks == 3)
    }

    @Test("A cancelled watcher finishes its stream", .timeLimit(.minutes(1)))
    func watcherStopsOnCancellation() async {
        let names = (try? PortInventory.readRows().map(\.bsdName)) ?? []
        let watcher = LinkWatcher(bsdNames: names, pollInterval: .milliseconds(20))
        let task = Task {
            var ticks = 0
            for await _ in watcher.changes() { ticks += 1 }
            return ticks
        }
        try? await Task.sleep(for: .milliseconds(120))
        task.cancel()
        let ticks = await task.value
        print("watcher saw \(ticks) wake-ups before cancellation")
        #expect(ticks >= 1)
    }
}
