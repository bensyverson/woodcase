//
//  PenFontEmbedding.swift
//  Woodcase
//

import Foundation

/// What a font's maker says about embedding it in a document: the OS/2 table's `fsType`.
///
/// Per the [OpenType spec](https://learn.microsoft.com/en-us/typography/opentype/spec/os2#fstype),
/// bits 0–3 carry the usage permission — 0 installable, 2 restricted, 4 preview and
/// print, 8 editable — bit 8 forbids subsetting and bit 9 allows only bitmap embedding.
/// It is the vendor's statement about embedding in a *document*; shipping the file in a
/// folder is closer to redistribution, which the vendor's license governs, so it is a
/// floor, not a grant. Apple's system fonts read 0 and still may not be passed on, which
/// is why a Pen Folder export decides "system font" by where the file is, never by this
/// (``PenFolderFontPlan/Source/system``).
///
/// Reading is pure byte parsing, so it builds everywhere; ``init(fontFile:)`` walks a
/// font file's table directory, ``init(os2Table:)`` takes the table Core Text's
/// `CTFontCopyTable` returns.
public struct PenFontEmbedding: Friendly {
    /// The usage permission bits 0–3 grant.
    public enum Permission: String, Friendly, CaseIterable {
        /// 0: may be embedded and installed on another system.
        case installable
        /// 2: must not be embedded or exchanged without the owner's permission.
        case restricted
        /// 4: may be embedded and loaded only to preview or print the document.
        case previewAndPrint
        /// 8: may be embedded and loaded to edit the document.
        case editable
    }

    /// The raw `fsType` value.
    public var fsType: UInt16

    /// An embedding from a raw `fsType`.
    public init(fsType: UInt16) {
        self.fsType = fsType
    }

    /// The permission bits 0–3 grant. When a font sets more than one, the least
    /// restrictive applies, as the spec says: editable, then preview and print, then
    /// restricted; none is installable.
    public var permission: Permission {
        if fsType & Self.editableBit != 0 { return .editable }
        if fsType & Self.previewAndPrintBit != 0 { return .previewAndPrint }
        if fsType & Self.restrictedBit != 0 { return .restricted }
        return .installable
    }

    /// Bit 8: the font may not be subset before embedding.
    public var forbidsSubsetting: Bool {
        fsType & Self.noSubsettingBit != 0
    }

    /// Bit 9: only the font's bitmaps may be embedded.
    public var isBitmapOnly: Bool {
        fsType & Self.bitmapOnlyBit != 0
    }

    /// Reads `fsType` from an OS/2 table's bytes (offset 8, big-endian).
    ///
    /// - Parameter os2Table: The table, as `CTFontCopyTable` returns it; a slice is read
    ///   from its own start.
    /// - Returns: `nil` when the table is too short to hold `fsType`.
    public init?(os2Table: Data) {
        guard let value = Self.uint16(in: os2Table, at: Self.fsTypeOffset) else { return nil }
        self.init(fsType: value)
    }

    /// Reads `fsType` from a font file's bytes: a TrueType or OpenType file, or the first
    /// font of a collection (`ttcf`).
    ///
    /// - Parameter fontFile: The whole file.
    /// - Returns: `nil` when the bytes are not an sfnt font, it has no OS/2 table, or the
    ///   table runs past the end of the file.
    public init?(fontFile: Data) {
        let data = Data(fontFile)
        var fontStart = 0
        if data.prefix(4) == Data("ttcf".utf8) {
            guard let first = Self.uint32(in: data, at: 12) else { return nil }
            fontStart = Int(first)
        }
        guard let tableCount = Self.uint16(in: data, at: fontStart + 4) else { return nil }
        for index in 0 ..< Int(tableCount) {
            let record = fontStart + 12 + 16 * index
            guard record + 16 <= data.count else { return nil }
            guard data[record ..< record + 4] == Data("OS/2".utf8) else { continue }
            guard let offset = Self.uint32(in: data, at: record + 8),
                  let length = Self.uint32(in: data, at: record + 12),
                  Int(offset) + Int(length) <= data.count
            else { return nil }
            self.init(os2Table: data[Int(offset) ..< Int(offset) + Int(length)])
            return
        }
        return nil
    }

    // MARK: - Private

    private static let restrictedBit: UInt16 = 0x2
    private static let previewAndPrintBit: UInt16 = 0x4
    private static let editableBit: UInt16 = 0x8
    private static let noSubsettingBit: UInt16 = 0x100
    private static let bitmapOnlyBit: UInt16 = 0x200

    /// Where `fsType` sits in the OS/2 table.
    private static let fsTypeOffset = 8

    /// The big-endian 16-bit value `offset` bytes from `data`'s start, or `nil` past its end.
    private static func uint16(in data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        let start = data.startIndex + offset
        return UInt16(data[start]) << 8 | UInt16(data[start + 1])
    }

    /// The big-endian 32-bit value `offset` bytes from `data`'s start, or `nil` past its end.
    private static func uint32(in data: Data, at offset: Int) -> UInt32? {
        guard let high = uint16(in: data, at: offset), let low = uint16(in: data, at: offset + 2) else { return nil }
        return UInt32(high) << 16 | UInt32(low)
    }
}
