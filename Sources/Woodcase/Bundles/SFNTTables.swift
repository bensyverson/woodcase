//
//  SFNTTables.swift
//  Woodcase
//

import Foundation

/// The tables of a font file, found through its table directory: a TrueType or OpenType
/// file, or the first font of a collection (`ttcf`).
///
/// Pure byte reading, so it builds everywhere; ``PenFontEmbedding`` and ``PenFontMaker``
/// read their tables through it.
struct SFNTTables {
    /// The whole file.
    let data: Data

    /// Where the font's offset table starts: 0, or the first font's offset in a collection.
    let fontStart: Int

    /// The tables of `fontFile`, or `nil` when the bytes are not an sfnt font.
    ///
    /// - Parameter fontFile: The whole file.
    init?(fontFile: Data) {
        let data = Data(fontFile)
        var fontStart = 0
        if data.prefix(4) == Data("ttcf".utf8) {
            guard let first = Self.uint32(in: data, at: 12) else { return nil }
            fontStart = Int(first)
        }
        guard Self.uint16(in: data, at: fontStart + 4) != nil else { return nil }
        self.data = data
        self.fontStart = fontStart
    }

    /// The table tagged `tag`, or `nil` when the font has none, its directory runs past
    /// the end of the file before reaching it, or the table itself does.
    ///
    /// - Parameter tag: The four-letter tag, such as `OS/2` or `name`.
    /// - Returns: The table's bytes, a slice of ``data``.
    func table(_ tag: String) -> Data? {
        guard let tableCount = Self.uint16(in: data, at: fontStart + 4) else { return nil }
        let tagBytes = Data(tag.utf8)
        for index in 0 ..< Int(tableCount) {
            let record = fontStart + 12 + 16 * index
            guard record + 16 <= data.count else { return nil }
            guard data[record ..< record + 4] == tagBytes else { continue }
            guard let offset = Self.uint32(in: data, at: record + 8),
                  let length = Self.uint32(in: data, at: record + 12),
                  Int(offset) + Int(length) <= data.count
            else { return nil }
            return data[Int(offset) ..< Int(offset) + Int(length)]
        }
        return nil
    }

    /// The big-endian 16-bit value `offset` bytes from `data`'s start, or `nil` past its end.
    static func uint16(in data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        let start = data.startIndex + offset
        return UInt16(data[start]) << 8 | UInt16(data[start + 1])
    }

    /// The big-endian 32-bit value `offset` bytes from `data`'s start, or `nil` past its end.
    static func uint32(in data: Data, at offset: Int) -> UInt32? {
        guard let high = uint16(in: data, at: offset), let low = uint16(in: data, at: offset + 2) else { return nil }
        return UInt32(high) << 16 | UInt32(low)
    }
}
