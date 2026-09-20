import Foundation

/// One shape for everything RDMALink writes to disk: sorted keys so a note can
/// be diffed by eye, and ISO 8601 dates so a note read years later still says
/// when it was taken.
enum JSONCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
