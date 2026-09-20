import Foundation
import Testing
@testable import RDMALinkCore

private func temporaryLogURL() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "rdmalink-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appending(path: "RDMALink").appending(path: ChangeLog.fileName)
}

@Suite("Change log")
struct StoreChangeLogTests {

    @Test("Entries come back in the order they happened")
    func appendsInOrder() throws {
        let url = try temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = ChangeLog(url: url)

        #expect(try log.entries() == [])
        let first = ChangeEntry.setUp(
            port: "en6", positionName: "Back, far left",
            date: Date(timeIntervalSince1970: 1_756_909_260))
        let second = ChangeEntry.adopted(
            port: "en7", positionName: "Back, far right",
            date: Date(timeIntervalSince1970: 1_756_910_400))
        try log.append(first)
        try log.append(second)

        #expect(try log.entries() == [first, second])
    }

    @Test("An entry is one line, and it is the spec's sentence")
    func writesOneLinePerEntry() throws {
        let url = try temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = ChangeLog(url: url)

        try log.append(ChangeEntry.setUp(port: "en6", positionName: "Back, far left"))
        try log.append(ChangeEntry.adopted(port: "en7", positionName: "Back, far right"))

        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 3)  // two entries and the trailing newline
        #expect(lines[2].isEmpty)
        #expect(text.contains(ChangeSentence.setUp))
        #expect(text.contains(ChangeSentence.adopted))
    }

    @Test("Nothing already written is ever rewritten")
    func neverRewritesThePast() throws {
        let url = try temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = ChangeLog(url: url)

        try log.append(ChangeEntry.setUp(port: "en6", positionName: "Back, far left"))
        let afterFirst = try Data(contentsOf: url)

        try log.append(ChangeEntry(
            port: "en6", positionName: "Back, far left", kind: .restored,
            sentence: ChangeSentence.alreadyPutBack(moment: "3 September at 15:10")))
        let afterSecond = try Data(contentsOf: url)

        #expect(afterSecond.count > afterFirst.count)
        #expect(afterSecond.prefix(afterFirst.count) == afterFirst)
        #expect(try log.entries().count == 2)
        #expect(try log.entries()[0].kind == .setUp)
    }

    @Test("The log is the user's own")
    func writesAPrivateFile() throws {
        let url = try temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = ChangeLog(url: url)

        try log.append(ChangeEntry.setUp(port: "en6", positionName: "Back, far left"))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("A line that cannot be read hides nothing else")
    func skipsDamagedLines() throws {
        let url = try temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = ChangeLog(url: url)

        try log.append(ChangeEntry.setUp(port: "en6", positionName: "Back, far left"))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{ not an entry\n".utf8))
        try handle.close()
        try log.append(ChangeEntry.adopted(port: "en7", positionName: "Back, far right"))

        #expect(try log.entries().count == 2)
        #expect(try log.unreadableLines() == 1)
    }

    @Test("Every kind the spec names")
    func carriesEveryKind() {
        #expect(Set(ChangeKind.allCases) ==
                [.setUp, .adopted, .restored, .returned, .stoppedManaging, .forgotten])
        let returned = ChangeEntry.returned(port: "en5", positionName: "Back, far left",
                                            bridgeName: "Thunderbolt Bridge", removedService: true)
        #expect(returned.kind == .returned)
        #expect(returned.sentence ==
                "Put it back in Thunderbolt Bridge and removed its standalone service.")
        #expect(ChangeEntry.returned(port: "en5", positionName: "Back, far left",
                                     bridgeName: "Thunderbolt Bridge", removedService: false)
                .sentence == "Put it back in Thunderbolt Bridge.")
        #expect(ChangeEntry.setUp(port: "en6", positionName: "Back, far left").kind == .setUp)
        #expect(ChangeEntry.setUp(port: "en6", positionName: "Back, far left").sentence ==
                ChangeSentence.setUp)
        #expect(ChangeEntry.adopted(port: "en7", positionName: "Back, far right").kind == .adopted)
        #expect(ChangeEntry.adopted(port: "en7", positionName: "Back, far right").sentence ==
                ChangeSentence.adopted)
    }

    @Test("The sentences read exactly as the spec writes them")
    func carriesTheSpecCopy() {
        #expect(ChangeSentence.setUp ==
                "Took it out of Thunderbolt Bridge and gave it its own service, with IPv4 off and IPv6 link-local only.")
        #expect(ChangeSentence.adopted ==
                "Adopted. RDMALink noted how it was already set up and changed nothing.")
        #expect(ChangeSentence.alreadyPutBack(moment: "3 September at 15:10") ==
                "Already put back on 3 September at 15:10.")
        #expect(ChangeSentence.stoppedLookingAfter(moment: "3 September at 15:12") ==
                "RDMALink stopped looking after this port on 3 September at 15:12.")
        #expect(ChangeSentence.returned(bridgeName: "Thunderbolt Bridge", removedService: true) ==
                "Put it back in Thunderbolt Bridge and removed its standalone service.")
        #expect(ChangeSentence.returned(bridgeName: "Thunderbolt Bridge", removedService: false) ==
                "Put it back in Thunderbolt Bridge.")
        #expect(ChangeSentence.returned(bridgeName: "bridge0", removedService: false) ==
                "Put it back in bridge0.")
        #expect(ChangeSentence.setUpAgain(moment: "20 September at 11:52") ==
                "Set up again on 20 September at 11:52.")
        #expect(ChangeSentence.putBackInBridge(moment: "20 September at 11:40") ==
                "Put back in the bridge on 20 September at 11:40.")
    }

    @Test("A later entry answers an earlier one, and the note quotes the answer's moment")
    func answersEntriesWithoutRewritingThem() {
        let day = Date(timeIntervalSince1970: 1_758_382_800)
        let setUp = ChangeEntry.setUp(port: "en5", positionName: "Back, far left", date: day)
        let restored = ChangeEntry(
            date: day + 60, port: "en5", positionName: "Back, far left", kind: .restored,
            sentence: ChangeSentence.alreadyPutBack(moment: Moment.text(day + 60)))
        let returned = ChangeEntry.returned(
            port: "en5", positionName: "Back, far left", bridgeName: "Thunderbolt Bridge",
            removedService: false, date: day + 120)
        let setUpAgain = ChangeEntry.setUp(port: "en5", positionName: "Back, far left",
                                           date: day + 180)
        let otherPort = ChangeEntry.setUp(port: "en6", positionName: "Back, left middle",
                                          date: day + 240)
        let entries = [setUp, restored, returned, setUpAgain, otherPort]

        // An undone set-up: "Already put back on…", as today.
        #expect(ChangeLog.answer(to: setUp, in: entries) == restored)
        #expect(ChangeLog.note(for: setUp, answeredBy: restored) ==
                ChangeSentence.alreadyPutBack(moment: Moment.text(restored.date)))
        // A return, once the port is set up again: "Set up again on…".
        #expect(ChangeLog.answer(to: returned, in: entries) == setUpAgain)
        #expect(ChangeLog.note(for: returned, answeredBy: setUpAgain) ==
                ChangeSentence.setUpAgain(moment: Moment.text(setUpAgain.date)))
        // The newest set-up stands, and so does the other port's; an answer
        // is never one that answers.
        #expect(ChangeLog.answer(to: setUpAgain, in: entries) == nil)
        #expect(ChangeLog.answer(to: otherPort, in: entries) == nil)
        #expect(ChangeLog.answer(to: restored, in: entries) == nil)
        // A returned note that was cleared instead.
        let forgotten = ChangeEntry(
            date: day + 150, port: "en5", positionName: "Back, far left", kind: .forgotten,
            sentence: ChangeSentence.stoppedLookingAfter(moment: Moment.text(day + 150)))
        #expect(ChangeLog.answer(to: returned, in: entries + [forgotten]) == forgotten)
        #expect(ChangeLog.note(for: returned, answeredBy: forgotten) ==
                ChangeSentence.stoppedLookingAfter(moment: Moment.text(forgotten.date)))
        // An adopted port that was returned: §S11's "Put back in the bridge on…".
        let adopted = ChangeEntry.adopted(port: "en5", positionName: "Back, far left",
                                          date: day + 90)
        #expect(ChangeLog.answer(to: adopted, in: entries + [adopted]) == returned)
        #expect(ChangeLog.note(for: adopted, answeredBy: returned) ==
                ChangeSentence.putBackInBridge(moment: Moment.text(returned.date)))
        // A returned port set up again by hand and then adopted: the adoption
        // replaces the return record, so it answers the returned entry, with
        // the one note §S11 gives a returned entry.
        let adoptedLater = ChangeEntry.adopted(port: "en5", positionName: "Back, far left",
                                               date: day + 170)
        #expect(ChangeLog.answer(to: returned, in: entries + [adoptedLater]) == adoptedLater)
        #expect(ChangeLog.note(for: returned, answeredBy: adoptedLater) ==
                ChangeSentence.setUpAgain(moment: Moment.text(adoptedLater.date)))
        #expect(ChangeLog.answer(to: adoptedLater, in: entries + [adoptedLater]) == nil)
    }

    @Test("The notes and the log live together")
    func livesBesideTheNotes() {
        let folder = BaselineStore.applicationDirectory.path
        #expect(ChangeLog.defaultURL.deletingLastPathComponent().path == folder)
        #expect(BaselineStore.defaultDirectory.deletingLastPathComponent().path == folder)
        #expect(BaselineStore.defaultDirectory.lastPathComponent == "baselines")
        #expect(folder.hasSuffix("/Library/Application Support/RDMALink"))
        #expect(ChangeLog.defaultURL.lastPathComponent == "changes.jsonl")
    }
}
