//
//  PenFontDeclarationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Covers the root `fonts` array: the font files a document declares, typed as
/// ``PenFontDeclaration`` rather than carried as an opaque extra. The keys and forms are
/// the ones Pen's own validator accepts — `name`, `url`, `style` (`normal` | `italic`)
/// and `weight` (a number, or `[min, max]` for a variable font).
struct PenFontDeclarationTests {
    // MARK: - Helpers

    private func declaration(_ json: String) throws -> PenFontDeclaration {
        try JSONDecoder().decode(PenFontDeclaration.self, from: Data(json.utf8))
    }

    private func authored(_ json: String) throws -> PenFontDeclaration {
        let decoder = JSONDecoder()
        decoder.userInfo[PenDecodingMode.userInfoKey] = PenDecodingMode.authoring
        return try decoder.decode(PenFontDeclaration.self, from: Data(json.utf8))
    }

    private func object(_ data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    private let fontsDocument = #"""
    {"version":"2.19","children":[],"fonts":[
      {"name":"Brand Sans","url":"fonts/BrandSans.ttf"},
      {"name":"Brand Sans","url":"fonts/BrandSans-Italic.ttf","style":"italic","weight":[100,900]},
      {"name":"Display","url":"https://example.com/display.woff2","weight":700}]}
    """#

    // MARK: - Decoding

    @Test("A name and a url are the whole of a minimal declaration")
    func minimal() throws {
        let font = try declaration(#"{"name":"Brand Sans","url":"fonts/BrandSans.ttf"}"#)
        #expect(font.name == "Brand Sans")
        #expect(font.url == "fonts/BrandSans.ttf")
        #expect(font.style == nil)
        #expect(font.weight == nil)
        #expect(font.extras.isEmpty)
    }

    @Test("A number is a single weight")
    func singleWeight() throws {
        let font = try declaration(#"{"name":"D","url":"d.ttf","weight":700}"#)
        #expect(font.weight == .single(700))
        #expect(font.weightRange == 700 ... 700)
    }

    @Test("A two-number array is the weight range of a variable font")
    func weightRange() throws {
        let font = try declaration(#"{"name":"V","url":"v.ttf","weight":[100,900]}"#)
        #expect(font.weight == .range(from: 100, to: 900))
        #expect(font.weightRange == 100 ... 900)
    }

    @Test("A range written high-to-low still spans the same weights")
    func reversedRange() throws {
        let font = try declaration(#"{"name":"V","url":"v.ttf","weight":[900,100]}"#)
        #expect(font.weightRange == 100 ... 900)
    }

    @Test("An absent weight is the regular weight, 400")
    func absentWeightIsRegular() throws {
        #expect(try declaration(#"{"name":"R","url":"r.ttf"}"#).weightRange == 400 ... 400)
    }

    @Test("style is normal or italic", arguments: PenFontDeclaration.Style.allCases)
    func style(style: PenFontDeclaration.Style) throws {
        let font = try declaration(#"{"name":"I","url":"i.ttf","style":"\#(style.rawValue)"}"#)
        #expect(font.style == style)
    }

    @Test("A weight that is neither a number nor two numbers is refused",
          arguments: [#""100 900""#, "[100]", "[100,200,300]", #"{"min":100}"#])
    func malformedWeightIsRefused(weight: String) {
        #expect(throws: DecodingError.self) {
            _ = try declaration(#"{"name":"W","url":"w.ttf","weight":\#(weight)}"#)
        }
    }

    @Test("A style Pen does not take is refused")
    func obliqueIsRefused() {
        #expect(throws: DecodingError.self) {
            _ = try declaration(#"{"name":"O","url":"o.ttf","style":"oblique"}"#)
        }
    }

    // MARK: - Encoding

    @Test("A declaration encodes back to the keys it was read from")
    func roundTrip() throws {
        let json = #"{"name":"V","url":"v.ttf","style":"italic","weight":[100,900]}"#
        let written = try JSONEncoder().encode(declaration(json))
        #expect(try object(written) == object(Data(json.utf8)))
    }

    // MARK: - Unknown keys

    @Test("A file keeps a key the model does not claim; authoring refuses it")
    func unknownKey() throws {
        let json = #"{"name":"K","url":"k.ttf","family":"K"}"#
        #expect(try declaration(json).extras["family"] == "K")
        #expect(throws: DecodingError.self) { _ = try authored(json) }
    }

    // MARK: - The document

    @Test("The document root's fonts are typed, and no longer an extra")
    func documentFonts() throws {
        let document = try PenParser.parse(fontsDocument)
        let fonts = try #require(document.fonts)
        #expect(fonts.map(\.url) == ["fonts/BrandSans.ttf", "fonts/BrandSans-Italic.ttf", "https://example.com/display.woff2"])
        #expect(fonts[1].style == .italic)
        #expect(document.extras["fonts"] == nil)
    }

    @Test("A document with fonts writes them back unchanged")
    func documentRoundTrip() throws {
        let written = try PenParser.encode(PenParser.parse(fontsDocument))
        let fonts = try #require(object(written)["fonts"] as? [NSDictionary])
        let original = try #require(object(Data(fontsDocument.utf8))["fonts"] as? [NSDictionary])
        #expect(fonts == original)
    }

    @Test("A document with no fonts writes no fonts key")
    func noFontsNoKey() throws {
        let written = try PenParser.encodeToString(PenParser.parse(#"{"version":"2.19","children":[]}"#))
        #expect(!written.contains("fonts"))
    }

    @Test("An edit carries the fonts through, and they are part of the document's revision")
    func editableDocumentCarriesFonts() throws {
        let document = try PenParser.parse(fontsDocument)
        let editable = EditableDocument(from: document)
        #expect(editable.fonts == document.fonts)
        #expect(editable.materialize().fonts == document.fonts)

        var changed = document
        changed.fonts = [PenFontDeclaration(name: "Other", url: "o.ttf")]
        #expect(EditableDocument(from: changed).documentRevision != editable.documentRevision)
    }

    // MARK: - Where the file is

    @Test("A relative url resolves against the .pen file's directory")
    func relativeURL() {
        let directory = URL(fileURLWithPath: "/designs/brand")
        let font = PenFontDeclaration(name: "B", url: "fonts/B.ttf")
        #expect(font.resolvedURL(relativeTo: directory) == URL(fileURLWithPath: "/designs/brand/fonts/B.ttf"))
    }

    @Test("An absolute path or a URL with a scheme is kept as written")
    func absoluteURL() {
        let directory = URL(fileURLWithPath: "/designs/brand")
        #expect(PenFontDeclaration(name: "H", url: "https://example.com/h.woff2").resolvedURL(relativeTo: directory)
            == URL(string: "https://example.com/h.woff2"))
        #expect(PenFontDeclaration(name: "A", url: "/Library/Fonts/A.ttf").resolvedURL(relativeTo: directory)
            == URL(fileURLWithPath: "/Library/Fonts/A.ttf"))
    }
}
