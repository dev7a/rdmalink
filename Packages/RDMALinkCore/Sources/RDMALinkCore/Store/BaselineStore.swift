import Darwin
import Foundation

/// Why a note could not be written, found or read. R14 is raised from
/// ``BaselineStoreError/cannotWrite(_:)`` and the writability probe; R19 from
/// ``BaselineStoreError/missing(_:)``, ``BaselineStoreError/unreadable(_:)``,
/// ``BaselineStoreError/malformed(_:)`` and
/// ``BaselineStoreError/unsupportedVersion(_:)``.
public enum BaselineStoreError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The port name would not be a safe file name.
    case invalidPortName(String)
    /// There is no note for that port.
    case missing(String)
    /// The note is there and could not be read.
    case unreadable(String)
    /// The note was read and does not hold together.
    case malformed(String)
    /// The note was written by a different schema.
    case unsupportedVersion(Int)
    /// The note could not be written, which stops everything (R14).
    case cannotWrite(String)

    public var description: String {
        switch self {
        case .invalidPortName(let name): "\(name) is not an interface name"
        case .missing(let name): "No undo note for \(name)"
        case .unreadable(let reason): reason
        case .malformed(let reason): reason
        case .unsupportedVersion(let version): "Undo note schema \(version) is not supported"
        case .cannotWrite(let reason): reason
        }
    }
}

/// Whether the notes folder can take a note right now, and what to say if not.
public enum BaselineWritability: Sendable, Equatable {
    /// A note can be written. The free space is reported when the volume says.
    case writable(availableBytes: Int64?)
    /// There is not enough room. R14's detail line reads
    /// "2 KB is all it needs. There's 0 bytes free on Macintosh HD."
    case outOfSpace(availableBytes: Int64, volumeName: String?)
    /// The folder will not take a file. R14's detail line reads
    /// "The folder isn't writable."
    case notWritable(reason: String)

    /// True when a note can be written.
    public var isWritable: Bool {
        if case .writable = self { return true }
        return false
    }
}

/// The undo notes: one small JSON file per port, in Application Support.
///
/// Every write is atomic — a temporary file in the same folder, flushed, then
/// renamed — so a note is either the old one or the new one and never half of
/// either. Notes are private to the user: the folder is `0700` and each note
/// `0600`.
public struct BaselineStore: Sendable {

    /// The app's folder inside Application Support.
    public static let applicationFolderName = "RDMALink"
    /// The notes folder inside it.
    public static let notesFolderName = "baselines"
    /// What one note needs, and what R14's copy quotes: "2 KB is all it needs."
    public static let requiredBytes: Int64 = 2048
    /// A note larger than this is not a note.
    public static let maximumNoteBytes = 1024 * 1024

    /// `~/Library/Application Support/RDMALink`.
    public static let applicationDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return base.appending(path: applicationFolderName)
    }()

    /// `~/Library/Application Support/RDMALink/baselines`.
    public static let defaultDirectory = applicationDirectory.appending(path: notesFolderName)

    /// Where the notes live. Settings reveals exactly this folder in Finder.
    public var directory: URL

    public init(directory: URL = BaselineStore.defaultDirectory) {
        self.directory = directory
    }

    /// The file a port's note lives in.
    public func url(forPort bsdName: String) throws -> URL {
        guard PortBaseline.isValidBSDName(bsdName) else {
            throw BaselineStoreError.invalidPortName(bsdName)
        }
        return directory.appending(path: "\(bsdName).json")
    }

    // MARK: - Reading

    /// The ports that have a note, in name order.
    ///
    /// A missing folder is not an error: it means nothing has been set up yet.
    public func list() throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            throw BaselineStoreError.unreadable("Cannot read \(directory.path): \(error.localizedDescription)")
        }
        return names.compactMap { name in
            guard name.hasSuffix(".json") else { return nil }
            let port = String(name.dropLast(5))
            return PortBaseline.isValidBSDName(port) ? port : nil
        }
        .sorted()
    }

    /// Reads one port's note.
    ///
    /// - Throws: ``BaselineStoreError`` — the cases R19 is raised from.
    public func load(port bsdName: String) throws -> PortBaseline {
        let url = try url(forPort: bsdName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BaselineStoreError.missing(bsdName)
        }
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw BaselineStoreError.unreadable("Cannot inspect \(url.path): \(error.localizedDescription)")
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size <= Self.maximumNoteBytes else {
            throw BaselineStoreError.malformed("\(bsdName)'s undo note is \(size) bytes")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BaselineStoreError.unreadable("Cannot read \(url.path): \(error.localizedDescription)")
        }
        let baseline: PortBaseline
        do {
            baseline = try JSONCoding.decoder().decode(PortBaseline.self, from: data)
        } catch {
            throw BaselineStoreError.malformed("\(bsdName)'s undo note could not be read back: \(error)")
        }
        try baseline.validate()
        guard baseline.bsdName == bsdName else {
            throw BaselineStoreError.malformed("\(bsdName)'s undo note is for \(baseline.bsdName)")
        }
        return baseline
    }

    // MARK: - Writing

    /// Writes a port's note: temporary file, flushed, then renamed over the
    /// old one. Both the folder and the note are private to the user.
    ///
    /// - Throws: ``BaselineStoreError/cannotWrite(_:)``, which is R14.
    public func save(_ baseline: PortBaseline) throws {
        try baseline.validate()
        let destination = try url(forPort: baseline.bsdName)
        try makeDirectory()
        let data = try encode(baseline)

        var template = Array(directory.appending(path: ".\(baseline.bsdName).json.XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else {
            throw BaselineStoreError.cannotWrite("Cannot create a note in \(directory.path) (\(errno))")
        }
        let temporaryPath = CBuffer.string(template)
        var renamed = false
        defer {
            close(descriptor)
            if !renamed { unlink(temporaryPath) }
        }

        guard fchmod(descriptor, 0o600) == 0 else {
            throw BaselineStoreError.cannotWrite("Cannot protect the note for \(baseline.bsdName) (\(errno))")
        }
        if let code = write(data, to: descriptor) {
            throw BaselineStoreError.cannotWrite("Cannot write the note for \(baseline.bsdName) (\(code))")
        }
        guard fsync(descriptor) == 0 else {
            throw BaselineStoreError.cannotWrite("Cannot flush the note for \(baseline.bsdName) (\(errno))")
        }
        guard rename(temporaryPath, destination.path) == 0 else {
            throw BaselineStoreError.cannotWrite("Cannot put the note for \(baseline.bsdName) in place (\(errno))")
        }
        renamed = true
        flushDirectory()
    }

    /// Forgets a port's note. Already gone counts as done.
    public func delete(port bsdName: String) throws {
        let url = try url(forPort: bsdName)
        if unlink(url.path) != 0 && errno != ENOENT {
            throw BaselineStoreError.cannotWrite("Cannot remove the note for \(bsdName) (\(errno))")
        }
        flushDirectory()
    }

    // MARK: - R14

    /// Can a note be written right now? Asked at preflight and again
    /// immediately before the first write, because this is the promise every
    /// other promise in the app rests on.
    ///
    /// The probe creates the folder if it has to, writes a small file, flushes
    /// it and removes it again. It never touches an existing note.
    public func checkWritable() -> BaselineWritability {
        do {
            try makeDirectory()
        } catch {
            return .notWritable(reason: "\(error)")
        }
        let space = freeSpace()
        if let available = space.availableBytes, available < Self.requiredBytes {
            return .outOfSpace(availableBytes: available, volumeName: space.volumeName)
        }

        var template = Array(directory.appending(path: ".writable.XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else {
            return failure(errno, space: space)
        }
        let path = CBuffer.string(template)
        defer {
            close(descriptor)
            unlink(path)
        }
        let probe = Data(repeating: 0x20, count: Int(Self.requiredBytes))
        if let code = write(probe, to: descriptor) { return failure(code, space: space) }
        guard fsync(descriptor) == 0 else { return failure(errno, space: space) }
        return .writable(availableBytes: space.availableBytes)
    }

    // MARK: - Private

    private func failure(_ code: Int32, space: (availableBytes: Int64?, volumeName: String?)) -> BaselineWritability {
        if code == ENOSPC || code == EDQUOT {
            return .outOfSpace(availableBytes: space.availableBytes ?? 0, volumeName: space.volumeName)
        }
        return .notWritable(reason: "\(directory.path) will not take a file (\(code))")
    }

    private func freeSpace() -> (availableBytes: Int64?, volumeName: String?) {
        let values = try? directory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeNameKey,
        ])
        return (values?.volumeAvailableCapacityForImportantUsage, values?.volumeName)
    }

    private func makeDirectory() throws {
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

    private func encode(_ baseline: PortBaseline) throws -> Data {
        do {
            return try JSONCoding.encoder().encode(baseline)
        } catch {
            throw BaselineStoreError.cannotWrite("Cannot write down \(baseline.bsdName)'s note: \(error)")
        }
    }

    /// Writes every byte. Returns the `errno` that stopped it, or `nil`.
    private func write(_ data: Data, to descriptor: Int32) -> Int32? {
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return Darwin.write(descriptor, base.advanced(by: offset), data.count - offset)
            }
            if written < 0 && errno == EINTR { continue }
            guard written > 0 else { return errno }
            offset += written
        }
        return nil
    }

    /// Flushes the folder itself, so a note that has been renamed into place
    /// survives a power cut as well as its contents do.
    private func flushDirectory() {
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        _ = fsync(descriptor)
    }
}
