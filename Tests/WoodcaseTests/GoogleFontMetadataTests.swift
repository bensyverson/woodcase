//
//  GoogleFontMetadataTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

@Suite("GoogleFontMetadata")
struct GoogleFontMetadataTests {
    // MARK: - Variable font parsing

    static let manropeMetadata = """
    name: "Manrope"
    designer: "Mikhail Sharanda"
    license: "OFL"
    category: "SANS_SERIF"
    date_added: "2019-10-03"
    fonts {
      name: "Manrope"
      style: "normal"
      weight: 400
      filename: "Manrope[wght].ttf"
      post_script_name: "Manrope-ExtraLight"
      full_name: "Manrope ExtraLight"
      copyright: "Copyright 2019 The Manrope Project Authors"
    }
    subsets: "latin"
    axes {
      tag: "wght"
      min_value: 200.0
      max_value: 800.0
    }
    """

    @Test("Parses variable font family name")
    func parsesVariableFontName() throws {
        let metadata = try GoogleFontMetadata.parse(Data(Self.manropeMetadata.utf8))
        #expect(metadata.name == "Manrope")
    }

    @Test("Parses variable font entry")
    func parsesVariableFontEntry() throws {
        let metadata = try GoogleFontMetadata.parse(Data(Self.manropeMetadata.utf8))
        #expect(metadata.fonts.count == 1)
        #expect(metadata.fonts[0].filename == "Manrope[wght].ttf")
        #expect(metadata.fonts[0].weight == 400)
        #expect(metadata.fonts[0].style == "normal")
    }

    @Test("Detects variable font via isVariable")
    func detectsVariableFont() throws {
        let metadata = try GoogleFontMetadata.parse(Data(Self.manropeMetadata.utf8))
        #expect(metadata.isVariable)
    }

    // MARK: - Static font parsing

    static let latoMetadata = """
    name: "Lato"
    designer: "Łukasz Dziedzic"
    license: "OFL"
    category: "SANS_SERIF"
    fonts {
      name: "Lato"
      style: "normal"
      weight: 100
      filename: "Lato-Thin.ttf"
      post_script_name: "Lato-Thin"
      full_name: "Lato Thin"
    }
    fonts {
      name: "Lato"
      style: "italic"
      weight: 100
      filename: "Lato-ThinItalic.ttf"
      post_script_name: "Lato-ThinItalic"
      full_name: "Lato Thin Italic"
    }
    fonts {
      name: "Lato"
      style: "normal"
      weight: 400
      filename: "Lato-Regular.ttf"
      post_script_name: "Lato-Regular"
      full_name: "Lato Regular"
    }
    fonts {
      name: "Lato"
      style: "normal"
      weight: 700
      filename: "Lato-Bold.ttf"
      post_script_name: "Lato-Bold"
      full_name: "Lato Bold"
    }
    subsets: "latin"
    """

    @Test("Parses static font family name")
    func parsesStaticFontName() throws {
        let metadata = try GoogleFontMetadata.parse(Data(Self.latoMetadata.utf8))
        #expect(metadata.name == "Lato")
    }

    @Test("Parses multiple static font entries")
    func parsesMultipleStaticFontEntries() throws {
        let metadata = try GoogleFontMetadata.parse(Data(Self.latoMetadata.utf8))
        #expect(metadata.fonts.count == 4)
    }

    @Test("Static font entries have correct weights")
    func staticFontWeights() throws {
        let metadata = try GoogleFontMetadata.parse(Data(Self.latoMetadata.utf8))
        let weights = metadata.fonts.map(\.weight)
        #expect(weights == [100, 100, 400, 700])
    }

    @Test("Static font entries have correct styles")
    func staticFontStyles() throws {
        let metadata = try GoogleFontMetadata.parse(Data(Self.latoMetadata.utf8))
        let styles = metadata.fonts.map(\.style)
        #expect(styles == ["normal", "italic", "normal", "normal"])
    }

    @Test("Static font is not detected as variable")
    func staticFontIsNotVariable() throws {
        let metadata = try GoogleFontMetadata.parse(Data(Self.latoMetadata.utf8))
        #expect(!metadata.isVariable)
    }

    // MARK: - Face matching

    /// A variable family with a separate italic file, as Lora and Inter ship.
    static let loraMetadata = """
    name: "Lora"
    fonts {
      name: "Lora"
      style: "normal"
      weight: 400
      filename: "Lora[wght].ttf"
    }
    fonts {
      name: "Lora"
      style: "italic"
      weight: 400
      filename: "Lora-Italic[wght].ttf"
    }
    """

    @Test("A static face that exists is its own entry, italic included")
    func matchesExactStaticFace() throws {
        let metadata = try GoogleFontMetadata.parse(Data(Self.latoMetadata.utf8))
        #expect(metadata.entry(weight: 700, style: .normal)?.filename == "Lato-Bold.ttf")
        #expect(metadata.entry(weight: 100, style: .italic)?.filename == "Lato-ThinItalic.ttf")
    }

    /// Previously `font(weight:style:)` answered `nil` for a weight the family does not
    /// ship, so nothing was fetched for it; the resolver now fetches the face a browser
    /// would draw, which CSS font matching picks.
    @Test("A weight the family does not ship takes the face CSS font matching picks")
    func matchesNearestWeightAsCSSDoes() throws {
        let metadata = try GoogleFontMetadata.parse(Data(Self.latoMetadata.utf8))
        // Above 500: heavier first.
        #expect(metadata.entry(weight: 600, style: .normal)?.filename == "Lato-Bold.ttf")
        #expect(metadata.entry(weight: 900, style: .normal)?.filename == "Lato-Bold.ttf")
        // Below 400: lighter first.
        #expect(metadata.entry(weight: 300, style: .normal)?.filename == "Lato-Thin.ttf")
        // 400 to 500: up to 500, then lighter.
        #expect(metadata.entry(weight: 450, style: .normal)?.filename == "Lato-Regular.ttf")
    }

    @Test("Style is matched before weight, and a family with no italic serves its upright")
    func matchesStyleBeforeWeight() throws {
        let lato = try GoogleFontMetadata.parse(Data(Self.latoMetadata.utf8))
        #expect(lato.entry(weight: 700, style: .italic)?.filename == "Lato-ThinItalic.ttf")
        let manrope = try GoogleFontMetadata.parse(Data(Self.manropeMetadata.utf8))
        #expect(manrope.entry(weight: 400, style: .italic)?.filename == "Manrope[wght].ttf")
    }

    @Test("A variable family serves one file per style at every weight")
    func matchesVariableFilePerStyle() throws {
        let metadata = try GoogleFontMetadata.parse(Data(Self.loraMetadata.utf8))
        #expect(metadata.entry(weight: 700, style: .normal)?.filename == "Lora[wght].ttf")
        #expect(metadata.entry(weight: 300, style: .italic)?.filename == "Lora-Italic[wght].ttf")
    }

    // MARK: - Error handling

    @Test("Throws on empty input")
    func throwsOnEmptyInput() throws {
        #expect(throws: GoogleFontError.self) {
            try GoogleFontMetadata.parse(Data())
        }
    }

    @Test("Throws on input with no font name")
    func throwsOnMissingName() throws {
        let input = """
        designer: "Someone"
        fonts {
          style: "normal"
          weight: 400
          filename: "Font.ttf"
        }
        """
        #expect(throws: GoogleFontError.self) {
            try GoogleFontMetadata.parse(Data(input.utf8))
        }
    }
}
