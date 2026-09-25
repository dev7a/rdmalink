import Darwin
import Foundation

/// What an entry records RDMALink having done.
public enum ChangeKind: String, Sendable, Codable, CaseIterable {
    /// A port was taken out of its bridges and given its own service.
    case setUp
    /// A port someone else configured was taken into RDMALink's care.
    case adopted
    /// A port was put back the way it was found, and verified.
    case restored
    /// A standalone port was put back into the Thunderbolt Bridge, the
    /// ordinary way rather than the remembered way (§7.5), and verified.
    case returned
    /// RDMALink stopped looking after an adopted port, changing nothing.
    case stoppedManaging
    /// A note was cleared for a port that had drifted or gone away.
    case forgotten
}

/// One line of the change log.
///
/// `sentence` is the plain sentence as it was written at the time. The screen
/// may render the line from `kind` instead — the record is kept, never rewritten.
public struct ChangeEntry: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    /// When it happened.
    public var date: Date
    /// The kernel interface name, such as `en6`, so the log can light the
    /// receptacle it refers to.
    public var port: String
    /// The position name in the words the rest of the app uses.
    public var positionName: String
    /// What happened.
    public var kind: ChangeKind
    /// One plain sentence, from ``ChangeSentence``.
    public var sentence: String

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        port: String,
        positionName: String,
        kind: ChangeKind,
        sentence: String
    ) {
        self.id = id
        self.date = date
        self.port = port
        self.positionName = positionName
        self.kind = kind
        self.sentence = sentence
    }

    /// The entry for a port RDMALink set up.
    public static func setUp(port: String, positionName: String, date: Date = Date()) -> ChangeEntry {
        ChangeEntry(date: date, port: port, positionName: positionName,
                    kind: .setUp, sentence: ChangeSentence.setUp)
    }

    /// The entry for a port RDMALink adopted.
    public static func adopted(port: String, positionName: String, date: Date = Date()) -> ChangeEntry {
        ChangeEntry(date: date, port: port, positionName: positionName,
                    kind: .adopted, sentence: ChangeSentence.adopted)
    }

    /// The entry for a port RDMALink returned to the bridge (§7.5, §S11).
    ///
    /// - Parameter removedService: whether a standalone service went with it.
    ///   Without one the sentence says only that the port was put back.
    public static func returned(
        port: String,
        positionName: String,
        bridgeName: String,
        removedService: Bool,
        date: Date = Date()
    ) -> ChangeEntry {
        ChangeEntry(date: date, port: port, positionName: positionName, kind: .returned,
                    sentence: ChangeSentence.returned(bridgeName: bridgeName,
                                                      removedService: removedService))
    }
}

/// The change log: a line of JSON per entry, appended and never rewritten.
///
/// It lives beside the undo notes, so `Show Notes in Finder` reveals both.
/// There is deliberately no API here that edits or removes an entry: an entry
/// that has been undone is answered by a later entry, not by editing the old
/// one.
public struct ChangeLog: Sendable {

    /// The file name inside the app's Application Support folder.
    public static let fileName = "changes.jsonl"

    /// `~/Library/Application Support/RDMALink/changes.jsonl`.
    public static let defaultURL = BaselineStore.applicationDirectory.appending(path: fileName)

    /// A line longer than this is not an entry.
    public static let maximumLineBytes = 64 * 1024

    /// Where the log lives.
    public var url: URL

    public init(url: URL = ChangeLog.defaultURL) {
        self.url = url
    }

    /// Adds one entry to the end of the log and flushes it.
    ///
    /// - Throws: ``BaselineStoreError/cannotWrite(_:)``.
    public func append(_ entry: ChangeEntry) throws {
        let data: Data
        do {
            data = try JSONCoding.encoder().encode(entry)
        } catch {
            throw BaselineStoreError.cannotWrite("Cannot write down the change for \(entry.port): \(error)")
        }
        guard !data.contains(0x0a) else {
            throw BaselineStoreError.cannotWrite("The change for \(entry.port) would break the log's one line per entry")
        }
        try makeDirectory()

        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw BaselineStoreError.cannotWrite("Cannot open the change log (\(errno))")
        }
        defer { close(descriptor) }
        _ = fchmod(descriptor, 0o600)

        var line = data
        line.append(0x0a)
        var offset = 0
        while offset < line.count {
            let written = line.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return Darwin.write(descriptor, base.advanced(by: offset), line.count - offset)
            }
            if written < 0 && errno == EINTR { continue }
            guard written > 0 else {
                throw BaselineStoreError.cannotWrite("Cannot add to the change log (\(errno))")
            }
            offset += written
        }
        guard fsync(descriptor) == 0 else {
            throw BaselineStoreError.cannotWrite("Cannot flush the change log (\(errno))")
        }
    }

    /// Every entry, oldest first. An empty log and no log at all read the same.
    ///
    /// A line that cannot be read is skipped rather than allowed to hide the
    /// rest of the record; ``unreadableLines(_:)`` counts them for the
    /// diagnostics file.
    public func entries() throws -> [ChangeEntry] {
        try lines().compactMap { decode($0) }
    }

    /// How many lines of the log could not be read back.
    public func unreadableLines() throws -> Int {
        try lines().filter { decode($0) == nil }.count
    }

    // MARK: - What answered what

    /// The later entry that answers `entry`, so §S11 can grey it and replace
    /// its action with a note — without anything in the file being rewritten.
    ///
    /// A set-up entry is answered by the restore, stop or forget that undid
    /// it; an adopted entry by those and by a return to the bridge; a
    /// returned entry by the port being set up again — by RDMALink, or by
    /// hand and then adopted, which replaces the return record the same way —
    /// or by its note being cleared. Entries that only ever answer are never
    /// answered themselves.
    public static func answer(to entry: ChangeEntry, in entries: [ChangeEntry]) -> ChangeEntry? {
        let answering: Set<ChangeKind>
        switch entry.kind {
        case .setUp: answering = [.restored, .stoppedManaging, .forgotten]
        case .adopted: answering = [.restored, .returned, .stoppedManaging, .forgotten]
        case .returned: answering = [.setUp, .adopted, .stoppedManaging, .forgotten]
        case .restored, .stoppedManaging, .forgotten: return nil
        }
        // The earliest by date, not the first in the file: the log is written
        // in order, but the answer is a fact about time either way.
        return entries
            .filter { $0.port == entry.port && $0.date > entry.date && answering.contains($0.kind) }
            .min { $0.date < $1.date }
    }

    /// §S11's note on an answered entry, quoting the moment of the answer:
    /// "Already put back on…", "Set up again on…", "Put back in the bridge
    /// on…" or "RDMALink stopped looking after this port on…".
    ///
    /// A returned entry answered by an adoption reads "Set up again on…" (the
    /// port was set up again by hand, then adopted — §S11 says "set up again,
    /// or adopted"); an adopted entry answered by a return reads "Put back in
    /// the bridge on…".
    public static func note(for entry: ChangeEntry, answeredBy later: ChangeEntry) -> String {
        let moment = Moment.text(later.date)
        if entry.kind == .returned, later.kind == .adopted {
            return ChangeSentence.setUpAgain(moment: moment)
        }
        switch later.kind {
        case .returned: return ChangeSentence.putBackInBridge(moment: moment)
        case .restored: return ChangeSentence.alreadyPutBack(moment: moment)
        case .setUp: return ChangeSentence.setUpAgain(moment: moment)
        case .adopted, .stoppedManaging, .forgotten:
            return ChangeSentence.stoppedLookingAfter(moment: moment)
        }
    }

    // MARK: - Private

    private func lines() throws -> [Data] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BaselineStoreError.unreadable("Cannot read the change log: \(error.localizedDescription)")
        }
        return data.split(separator: 0x0a, omittingEmptySubsequences: true).map { Data($0) }
    }

    private func decode(_ line: Data) -> ChangeEntry? {
        guard line.count <= Self.maximumLineBytes else { return nil }
        return try? JSONCoding.decoder().decode(ChangeEntry.self, from: line)
    }

    private func makeDirectory() throws {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw BaselineStoreError.cannotWrite(
                "Cannot use \(directory.path): \(error.localizedDescription)"
            )
        }
    }
}
