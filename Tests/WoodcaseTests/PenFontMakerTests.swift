//
//  PenFontMakerTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Who made a font, read from its own bytes — the OS/2 vendor ID and the name table's
/// manufacturer and copyright — and whether that maker is Apple.
@Suite("PenFontMaker")
struct PenFontMakerTests {
    private static let fonts = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fonts")

    @Test("The OS/2 vendor ID APPL is Apple's, whatever the names say")
    func vendorIsApple() throws {
        let file = SyntheticFont.file(vendor: "APPL", names: [.windows(8, "Somebody Else")])
        let maker = try #require(PenFontMaker(fontFile: file))
        #expect(maker.vendorID == "APPL")
        #expect(maker.manufacturer == "Somebody Else")
        #expect(maker.isApple)
    }

    @Test("A manufacturer of Apple Inc. is Apple's, whatever the vendor ID")
    func manufacturerIsApple() throws {
        let file = SyntheticFont.file(vendor: "UKWN", names: [.windows(8, "Apple Inc.")])
        let maker = try #require(PenFontMaker(fontFile: file))
        #expect(maker.isApple)
    }

    @Test("A copyright of Apple Computer is Apple's")
    func copyrightIsApple() throws {
        let file = SyntheticFont.file(
            vendor: "pyrs", names: [.windows(0, "© 1990-2006 Apple Computer Inc. © 1981 Linotype AG")]
        )
        let maker = try #require(PenFontMaker(fontFile: file))
        #expect(maker.copyright == "© 1990-2006 Apple Computer Inc. © 1981 Linotype AG")
        #expect(maker.isApple)
    }

    @Test("A Macintosh-platform name record is read in Mac Roman")
    func macRomanName() throws {
        let file = SyntheticFont.file(vendor: "", names: [.mac(0, "© 2017 Apple Inc. All rights reserved.")])
        let maker = try #require(PenFontMaker(fontFile: file))
        #expect(maker.copyright == "© 2017 Apple Inc. All rights reserved.")
        #expect(maker.isApple)
    }

    @Test("A Windows record is preferred to a Macintosh one of the same ID")
    func prefersWindows() throws {
        let file = SyntheticFont.file(vendor: "UKWN", names: [.mac(8, "Old Name"), .windows(8, "New Name")])
        #expect(try #require(PenFontMaker(fontFile: file)).manufacturer == "New Name")
    }

    @Test("A third party's font is not Apple's, even where a word ends in apple")
    func thirdPartyIsNotApple() throws {
        let grand = SyntheticFont.file(vendor: "UKWN", names: [
            .windows(0, "Copyright © 2017 by Ben Syverson. All rights reserved."),
            .windows(8, "Ben Syverson"),
        ])
        let grandMaker = try #require(PenFontMaker(fontFile: grand))
        #expect(grandMaker.vendorID == "UKWN")
        #expect(grandMaker.manufacturer == "Ben Syverson")
        #expect(!grandMaker.isApple)
        let pineapple = SyntheticFont.file(vendor: "APPX", names: [.windows(8, "Pineapple Inc.")])
        #expect(try !#require(PenFontMaker(fontFile: pineapple)).isApple)
    }

    @Test("The tables Core Text copies read the same as the file's")
    func readsTables() throws {
        let maker = try #require(PenFontMaker(
            os2Table: SyntheticFont.os2Table(vendor: "APPL"),
            nameTable: SyntheticFont.nameTable([.windows(8, "Apple Inc.")])
        ))
        #expect(maker == PenFontMaker(vendorID: "APPL", manufacturer: "Apple Inc.", copyright: nil))
        let noName = try #require(PenFontMaker(os2Table: SyntheticFont.os2Table(vendor: "APPL"), nameTable: nil))
        #expect(noName.isApple)
    }

    @Test("A vendor ID's trailing spaces and NULs are trimmed; an empty one is no vendor")
    func trimsVendor() throws {
        #expect(try #require(PenFontMaker(fontFile: SyntheticFont.file(vendor: "JB", names: []))).vendorID == "JB")
        let blank = try #require(PenFontMaker(os2Table: Data(count: 96), nameTable: nil))
        #expect(blank.vendorID == nil)
        #expect(!blank.isApple)
    }

    @Test("A file with neither table, or no font at all, reads as nothing; either table alone reads")
    func unreadable() {
        #expect(PenFontMaker(fontFile: SyntheticFont.sfnt([(tag: "OS/2", data: SyntheticFont.os2Table())])) != nil)
        let names = SyntheticFont.nameTable([.windows(0, "Copyright")])
        #expect(PenFontMaker(fontFile: SyntheticFont.sfnt([(tag: "name", data: names)])) != nil)
        #expect(PenFontMaker(fontFile: SyntheticFont.sfnt([(tag: "cmap", data: Data(count: 20))])) == nil)
        #expect(PenFontMaker(fontFile: Data("not a font".utf8)) == nil)
        #expect(PenFontMaker(os2Table: nil, nameTable: nil) == nil)
        #expect(PenFontMaker(os2Table: Data(count: 20), nameTable: Data(count: 3)) == nil)
    }

    @Test("A real file reads: the JetBrains Mono copy is JetBrains', the APPL copy Apple's")
    func readsRealFiles() throws {
        let mono = try #require(PenFontMaker(
            fontFile: Data(contentsOf: Self.fonts.appendingPathComponent("WoodcaseDeclaredMono.ttf"))
        ))
        #expect(mono.vendorID == "JB")
        #expect(mono.manufacturer == "JetBrains")
        #expect(mono.copyright?.hasPrefix("Copyright 2020 The JetBrains Mono Project Authors") == true)
        #expect(!mono.isApple)
        let appleMade = try #require(PenFontMaker(
            fontFile: Data(contentsOf: Self.fonts.appendingPathComponent("WoodcaseAppleMadeMono.ttf"))
        ))
        #expect(appleMade.vendorID == "APPL")
        #expect(appleMade.isApple)
    }
}
