//
//  PenFontEmbeddingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A font's embedding permissions, read from the OS/2 table's `fsType` as bytes: the
/// table alone, a single-font file's table directory, and a collection's first font.
@Suite("PenFontEmbedding")
struct PenFontEmbeddingTests {
    private static let fonts = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fonts")

    /// An OS/2 table of `length` bytes whose `fsType` (bytes 8–9) is `fsType`.
    private static func os2Table(fsType: UInt16, length: Int = 96) -> Data {
        SyntheticFont.os2Table(fsType: fsType, length: length)
    }

    /// A minimal sfnt of `tables`; see ``SyntheticFont/sfnt(_:placedAt:)``.
    private static func sfnt(_ tables: [(tag: String, data: Data)], placedAt base: Int = 0) -> Data {
        SyntheticFont.sfnt(tables, placedAt: base)
    }

    @Test("Each permission bit reads as its class, and no bit reads as installable")
    func readsEachPermission() {
        #expect(PenFontEmbedding(fsType: 0).permission == .installable)
        #expect(PenFontEmbedding(fsType: 0x2).permission == .restricted)
        #expect(PenFontEmbedding(fsType: 0x4).permission == .previewAndPrint)
        #expect(PenFontEmbedding(fsType: 0x8).permission == .editable)
    }

    @Test("Several permission bits read as the least restrictive, as the OpenType spec says")
    func leastRestrictiveWins() {
        #expect(PenFontEmbedding(fsType: 0x2 | 0x4).permission == .previewAndPrint)
        #expect(PenFontEmbedding(fsType: 0x2 | 0x8).permission == .editable)
        #expect(PenFontEmbedding(fsType: 0x4 | 0x8).permission == .editable)
    }

    @Test("The subsetting and bitmap bits are read, and do not change the permission")
    func readsSubsettingAndBitmapBits() {
        let embedding = PenFontEmbedding(fsType: 0x8 | 0x100 | 0x200)
        #expect(embedding.permission == .editable)
        #expect(embedding.forbidsSubsetting)
        #expect(embedding.isBitmapOnly)
        let plain = PenFontEmbedding(fsType: 0)
        #expect(!plain.forbidsSubsetting)
        #expect(!plain.isBitmapOnly)
    }

    @Test("An OS/2 table's fsType is its bytes 8 and 9, big-endian")
    func readsTheTable() {
        #expect(PenFontEmbedding(os2Table: Self.os2Table(fsType: 0x0104))?.fsType == 0x0104)
        #expect(PenFontEmbedding(os2Table: Self.os2Table(fsType: 0x0002))?.permission == .restricted)
    }

    @Test("A table too short to hold fsType reads as nothing")
    func shortTableIsUnreadable() {
        #expect(PenFontEmbedding(os2Table: Data(count: 9)) == nil)
    }

    @Test("A slice of a larger buffer is read from its own start")
    func readsASlice() {
        let padded = Data(count: 5) + Self.os2Table(fsType: 0x8)
        #expect(PenFontEmbedding(os2Table: padded.dropFirst(5))?.permission == .editable)
    }

    @Test("A font file's OS/2 table is found through its table directory")
    func readsAFontFile() {
        let file = Self.sfnt([
            (tag: "cmap", data: Data(count: 20)),
            (tag: "OS/2", data: Self.os2Table(fsType: 0x4)),
        ])
        #expect(PenFontEmbedding(fontFile: file)?.permission == .previewAndPrint)
    }

    @Test("A collection is read through its first font")
    func readsACollection() {
        let header: [UInt8] = Array("ttcf".utf8) + SyntheticFont.u32(0x0001_0000) + SyntheticFont.u32(1) + SyntheticFont.u32(16)
        let font = Self.sfnt([(tag: "OS/2", data: Self.os2Table(fsType: 0x2))], placedAt: 16)
        #expect(PenFontEmbedding(fontFile: Data(header) + font)?.permission == .restricted)
    }

    @Test("A file with no OS/2 table, a truncated one, or no font at all reads as nothing")
    func unreadableFiles() {
        #expect(PenFontEmbedding(fontFile: Self.sfnt([(tag: "cmap", data: Data(count: 20))])) == nil)
        var truncated = Self.sfnt([(tag: "OS/2", data: Self.os2Table(fsType: 0))])
        truncated = truncated.prefix(truncated.count - 90)
        #expect(PenFontEmbedding(fontFile: truncated) == nil)
        #expect(PenFontEmbedding(fontFile: Data("not a font".utf8)) == nil)
        #expect(PenFontEmbedding(fontFile: Data()) == nil)
    }

    @Test("A real font file reads: the test fixtures are installable")
    func readsARealFile() throws {
        let data = try Data(contentsOf: Self.fonts.appendingPathComponent("WoodcaseDeclaredMono.ttf"))
        #expect(PenFontEmbedding(fontFile: data)?.permission == .installable)
    }
}
