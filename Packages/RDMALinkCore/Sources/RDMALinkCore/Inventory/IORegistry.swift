import Foundation
import IOKit

/// Typed, leak-free wrappers over the handful of IORegistry calls the Inventory
/// module needs. Every `io_object_t` this file creates is released here, so no
/// registry handle ever escapes into Swift code.
enum IORegistry {
    /// Visits every registered service whose class is `className` or a subclass.
    ///
    /// An unknown class name is not an error: the iterator is simply empty,
    /// which is how the undocumented enrichment degrades on hardware that does
    /// not publish it.
    static func forEachService(
        matchingClass className: String,
        _ body: (io_registry_entry_t) throws -> Void
    ) throws {
        guard let matching = IOServiceMatching(className) else {
            throw InventoryError(step: "build a match for \(className)", code: KERN_FAILURE)
        }
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard status == KERN_SUCCESS else {
            throw InventoryError(step: "look up \(className)", code: status)
        }
        defer { IOObjectRelease(iterator) }
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }
            try body(entry)
        }
    }

    /// The first non-nil value `transform` produces anywhere in `entry`'s
    /// subtree, walking `plane` depth-first. `entry` itself is not visited.
    static func firstDescendant<Value>(
        of entry: io_registry_entry_t,
        plane: String,
        _ transform: (io_registry_entry_t) -> Value?
    ) -> Value? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            entry, plane, IOOptionBits(kIORegistryIterateRecursively), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while true {
            let child = IOIteratorNext(iterator)
            if child == 0 { break }
            defer { IOObjectRelease(child) }
            if let value = transform(child) { return value }
        }
        return nil
    }

    /// The first non-nil value `transform` produces among `entry`'s direct
    /// children in `plane`.
    static func firstChild<Value>(
        of entry: io_registry_entry_t,
        plane: String,
        _ transform: (io_registry_entry_t) -> Value?
    ) -> Value? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, plane, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        while true {
            let child = IOIteratorNext(iterator)
            if child == 0 { break }
            defer { IOObjectRelease(child) }
            if let value = transform(child) { return value }
        }
        return nil
    }

    /// This entry's name in `plane`, for example `acio0`.
    static func name(_ entry: io_registry_entry_t, plane: String) -> String? {
        var buffer = [CChar](repeating: 0, count: 128)
        let status = buffer.withUnsafeMutableBufferPointer { pointer in
            IORegistryEntryGetNameInPlane(entry, plane, pointer.baseAddress)
        }
        guard status == KERN_SUCCESS else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> AnyObject? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }

    /// An integer property. Accepts a number *or* a decimal string, because
    /// `IOLocation` is published as a string.
    static func integer(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        switch property(entry, key) {
        case let number as NSNumber: number.intValue
        case let text as NSString: Int(text as String)
        default: nil
        }
    }

    /// A boolean property.
    static func boolean(_ entry: io_registry_entry_t, _ key: String) -> Bool? {
        (property(entry, key) as? NSNumber)?.boolValue
    }

    /// A string property. Accepts a `CFString` or the NUL-terminated `CFData`
    /// that device-tree properties such as `port-location` are published as.
    static func string(_ entry: io_registry_entry_t, _ key: String) -> String? {
        switch property(entry, key) {
        case let text as NSString: text as String
        case let data as NSData: DeviceTree.string(Data(referencing: data))
        default: nil
        }
    }

    /// Raw bytes of a property, for example the `acio-parent` phandle.
    static func data(_ entry: io_registry_entry_t, _ key: String) -> Data? {
        (property(entry, key) as? NSData).map { Data(referencing: $0) }
    }
}

/// Decodes the raw byte properties an `IODeviceTree` node carries.
enum DeviceTree {
    /// A string property: UTF-8 bytes, usually NUL-terminated.
    static func string(_ data: Data) -> String? {
        let bytes = data.prefix { $0 != 0 }
        return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
    }

    /// A phandle: exactly four little-endian bytes.
    ///
    /// A wrong length is nil rather than a guess — a mis-decoded phandle would
    /// attach a position name to the wrong receptacle.
    static func phandle(_ data: Data) -> UInt32? {
        guard data.count == 4 else { return nil }
        return data.reversed().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}
