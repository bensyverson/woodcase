//
//  PenFontMaker.swift
//  Woodcase
//

import Foundation

/// Who made a font, as its own tables say: the OS/2 table's vendor ID and the name
/// table's manufacturer and copyright.
///
/// A Pen Folder export asks it whether Apple made a font (``isApple``), because Apple's
/// license lets nobody pass on Apple's fonts wherever they are installed — the SF Pro and
/// New York families from Apple's developer downloads live in `/Library/Fonts`, outside
/// the system's folders (``PenFolderFontPlan/Source/system``).
///
/// Reading is pure byte parsing, so it builds everywhere: ``init(fontFile:)`` walks a font
/// file's table directory, ``init(os2Table:nameTable:)`` takes the tables Core Text's
/// `CTFontCopyTable` returns.
public struct PenFontMaker: Friendly {
    /// The OS/2 table's `achVendID`, its trailing spaces and NULs trimmed; `nil` when
    /// blank or unreadable. Apple's fonts say `APPL`.
    public var vendorID: String?

    /// The Manufacturer Name (name ID 8), or `nil`.
    public var manufacturer: String?

    /// The Copyright Notice (name ID 0), or `nil`.
    public var copyright: String?

    /// A maker from what a font says.
    ///
    /// - Parameters:
    ///   - vendorID: The OS/2 vendor ID, or `nil`.
    ///   - manufacturer: The manufacturer name, or `nil`.
    ///   - copyright: The copyright notice, or `nil`.
    public init(vendorID: String?, manufacturer: String?, copyright: String?) {
        self.vendorID = vendorID
        self.manufacturer = manufacturer
        self.copyright = copyright
    }

    /// Whether Apple made the font: its vendor ID is `APPL`, or its manufacturer or
    /// copyright names Apple Inc. or Apple Computer.
    public var isApple: Bool {
        if vendorID == Self.appleVendorID { return true }
        return [manufacturer, copyright].contains { name in
            name?.contains(#/\bApple\s+(Inc|Computer)\b/#.ignoresCase()) == true
        }
    }

    /// Reads the maker from a font's OS/2 and name tables.
    ///
    /// - Parameters:
    ///   - os2Table: The OS/2 table, or `nil`; a slice is read from its own start.
    ///   - nameTable: The name table, or `nil`; a slice is read from its own start.
    /// - Returns: `nil` when neither table can be read.
    public init?(os2Table: Data?, nameTable: Data?) {
        let vendor = os2Table.flatMap(Self.vendorID(in:))
        let names = nameTable.flatMap(Self.names(in:))
        guard vendor != nil || names != nil else { return nil }
        self.init(
            vendorID: vendor.flatMap { $0.isEmpty ? nil : $0 },
            manufacturer: names?[Self.manufacturerNameID],
            copyright: names?[Self.copyrightNameID]
        )
    }

    /// Reads the maker from a font file's bytes: a TrueType or OpenType file, or the
    /// first font of a collection (`ttcf`).
    ///
    /// - Parameter fontFile: The whole file.
    /// - Returns: `nil` when the bytes are not an sfnt font or it has neither table.
    public init?(fontFile: Data) {
        guard let tables = SFNTTables(fontFile: fontFile) else { return nil }
        self.init(os2Table: tables.table("OS/2"), nameTable: tables.table("name"))
    }

    // MARK: - Private

    /// The vendor ID Apple's fonts carry.
    private static let appleVendorID = "APPL"

    /// Where `achVendID` sits in the OS/2 table, and its length.
    private static let vendorIDRange = 58 ..< 62

    /// The name IDs read.
    private static let copyrightNameID: UInt16 = 0
    private static let manufacturerNameID: UInt16 = 8

    /// The OS/2 table's vendor ID, trimmed — empty when blank — or `nil` when the table
    /// is too short to hold one.
    private static func vendorID(in os2Table: Data) -> String? {
        let table = Data(os2Table)
        guard table.count >= vendorIDRange.upperBound else { return nil }
        let bytes = table[vendorIDRange].filter { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }

    /// Each name ID's string the table holds, preferring a Windows record to a Unicode
    /// one to a Macintosh one; `nil` when the table's header or records run past its end.
    private static func names(in nameTable: Data) -> [UInt16: String]? {
        let table = Data(nameTable)
        guard let count = SFNTTables.uint16(in: table, at: 2),
              let storage = SFNTTables.uint16(in: table, at: 4),
              6 + 12 * Int(count) <= table.count
        else { return nil }
        var best: [UInt16: (rank: Int, string: String)] = [:]
        for index in 0 ..< Int(count) {
            let record = 6 + 12 * index
            guard let platform = SFNTTables.uint16(in: table, at: record),
                  let encoding = SFNTTables.uint16(in: table, at: record + 2),
                  let nameID = SFNTTables.uint16(in: table, at: record + 6),
                  nameID == copyrightNameID || nameID == manufacturerNameID,
                  let length = SFNTTables.uint16(in: table, at: record + 8),
                  let offset = SFNTTables.uint16(in: table, at: record + 10),
                  let rank = platformRank[platform]
            else { continue }
            let start = Int(storage) + Int(offset)
            guard start + Int(length) <= table.count,
                  let string = decode(table[start ..< start + Int(length)], platform: platform, encoding: encoding)
            else { continue }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, rank < best[nameID]?.rank ?? .max {
                best[nameID] = (rank, trimmed)
            }
        }
        return best.mapValues(\.string)
    }

    /// The platforms read, best first: Windows (3), Unicode (0), Macintosh (1).
    private static let platformRank: [UInt16: Int] = [3: 0, 0: 1, 1: 2]

    /// A name record's string: UTF-16BE on the Windows and Unicode platforms, Mac Roman
    /// on the Macintosh platform's Roman encoding (0); `nil` for any other.
    private static func decode(_ bytes: Data, platform: UInt16, encoding: UInt16) -> String? {
        switch platform {
        case 1: encoding == 0 ? String(data: bytes, encoding: .macOSRoman) : nil
        default: String(data: bytes, encoding: .utf16BigEndian)
        }
    }
}
