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

    @Test("The Thunderbolt domain identities this Mac reports")
    func readsDomainIdentities() throws {
        let rows = try PortInventory.readRows()
        let partners = PortInventory.loopedBackPartners(rows)
        for row in rows.sorted(by: { $0.receptacle < $1.receptacle }) {
            print("  \(row.bsdName) · own \(row.domainUUID ?? "not published") · "
                + "peers \(row.peerDomainUUIDs) · looped back to \(partners[row.bsdName] ?? "none")")
        }
        // Private keys: a Mac may publish none of them. When it does, each is
        // a UUID in its canonical spelling, and a loop is only ever mutual.
        for row in rows {
            #expect(row.domainUUID.map { PortInventory.domainUUID($0) == $0 } ?? true)
            #expect(row.peerDomainUUIDs.allSatisfy { PortInventory.domainUUID($0) == $0 })
        }
        for (name, partner) in partners {
            #expect(partners[partner] == name)
            #expect(name != partner)
        }
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
        // The claim under test is that cancelling the consumer finishes the
        // stream — not that a tick lands inside a fixed wait. On a loaded
        // GitHub runner the consuming task was not scheduled within 120 ms
        // and the old fixed sleep saw zero ticks, so the test waits for the
        // first wake-up and only then cancels; the time limit above is the
        // guard against a watcher that never ticks at all.
        let (firstTick, seen) = AsyncStream<Void>.makeStream()
        let task = Task {
            var ticks = 0
            for await _ in watcher.changes() {
                ticks += 1
                if ticks == 1 {
                    seen.yield()
                    seen.finish()
                }
            }
            return ticks
        }
        for await _ in firstTick { break }
        task.cancel()
        let ticks = await task.value
        print("watcher saw \(ticks) wake-ups before cancellation")
        #expect(ticks >= 1)
    }
}
