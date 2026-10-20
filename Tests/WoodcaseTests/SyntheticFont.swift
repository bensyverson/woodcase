//
//  SyntheticFont.swift
//  WoodcaseTests
//

import Foundation

/// The bytes of minimal sfnt fonts and their tables, for tests that read a font's own
/// statements — `fsType`, vendor ID, names — without a real font file. Core Text cannot
/// draw them: they carry no glyphs.
enum SyntheticFont {
    /// One record of a name table: a string for `nameID` on a platform.
    struct NameRecord {
        /// The platform: 0 Unicode, 1 Macintosh, 3 Windows.
        var platform: Int
        /// The platform's encoding: 1 for Windows Unicode BMP, 0 for Mac Roman.
        var encoding: Int
        /// The language: 0x409 for Windows US English, 0 for Mac English.
        var language: Int
        /// The name ID: 0 copyright, 1 family, 8 manufacturer.
        var nameID: Int
        /// The string.
        var string: String

        /// A Windows US English record, the form most fonts carry.
        static func windows(_ nameID: Int, _ string: String) -> Self {
            Self(platform: 3, encoding: 1, language: 0x409, nameID: nameID, string: string)
        }

        /// A Macintosh Roman English record, the form old fonts carry.
        static func mac(_ nameID: Int, _ string: String) -> Self {
            Self(platform: 1, encoding: 0, language: 0, nameID: nameID, string: string)
        }

        /// The string's bytes in the platform's encoding.
        var encoded: Data {
            platform == 1
                ? string.data(using: .macOSRoman) ?? Data()
                : string.data(using: .utf16BigEndian) ?? Data()
        }
    }

    /// A big-endian 16-bit value's bytes.
    static func u16(_ value: Int) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    /// A big-endian 32-bit value's bytes.
    static func u32(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    /// An OS/2 table of `length` bytes whose `fsType` (bytes 8–9) is `fsType` and whose
    /// `achVendID` (bytes 58–61) is `vendor`, padded with spaces.
    static func os2Table(fsType: UInt16 = 0, vendor: String = "UKWN", length: Int = 96) -> Data {
        var table = Data(count: length)
        table[8] = UInt8(fsType >> 8)
        table[9] = UInt8(fsType & 0xFF)
        if length >= 62 {
            for (index, byte) in Array(vendor.utf8.prefix(4)).padded(to: 4, with: 0x20).enumerated() {
                table[58 + index] = byte
            }
        }
        return table
    }

    /// A format 0 name table holding `records`, their strings stored in order.
    static func nameTable(_ records: [NameRecord]) -> Data {
        let storageOffset = 6 + 12 * records.count
        var header: [UInt8] = u16(0) + u16(records.count) + u16(storageOffset)
        var storage = Data()
        for record in records {
            let bytes = record.encoded
            header += u16(record.platform) + u16(record.encoding) + u16(record.language) + u16(record.nameID)
            header += u16(bytes.count) + u16(storage.count)
            storage += bytes
        }
        return Data(header) + storage
    }

    /// A minimal sfnt: a header, a table directory of `tables` and each table's bytes, in
    /// order, after the directory. The bytes start `base` bytes into the file they will
    /// sit in, so offsets can be checked inside a collection.
    static func sfnt(_ tables: [(tag: String, data: Data)], placedAt base: Int = 0) -> Data {
        var bytes: [UInt8] = u32(0x0001_0000) + u16(tables.count) + u16(0) + u16(0) + u16(0)
        var offset = base + 12 + 16 * tables.count
        for table in tables {
            bytes += Array(table.tag.utf8) + u32(0) + u32(offset) + u32(table.data.count)
            offset += table.data.count
        }
        for table in tables {
            bytes += Array(table.data)
        }
        return Data(bytes)
    }

    /// A font file of an OS/2 table naming `vendor` and a name table of `names`.
    static func file(vendor: String, names: [NameRecord]) -> Data {
        sfnt([(tag: "OS/2", data: os2Table(vendor: vendor)), (tag: "name", data: nameTable(names))])
    }
}

private extension Array {
    /// The array padded with `element` to `count` elements.
    func padded(to count: Int, with element: Element) -> [Element] {
        self + Array(repeating: element, count: Swift.max(0, count - self.count))
    }
}
