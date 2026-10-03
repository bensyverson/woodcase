//
//  PenImageFillModeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Format 2.20 spells an image paint's `mode` cover / contain / stretch, and a missing mode
/// means cover. Every spelling ever written is read leniently: 2.19's `fill` and `fit` read as
/// cover and contain, and an unknown value is kept as written and placed as cover.
struct PenImageFillModeTests {
    /// The image payload of a fill object written as JSON.
    private static func imageFill(_ json: String) throws -> PenFill.PenImageFill {
        let fill = try JSONDecoder().decode(PenFill.self, from: Data(json.utf8))
        guard case let .image(image) = fill else {
            Issue.record("expected an image fill, got \(fill)")
            throw CancellationError()
        }
        return image
    }

    /// The JSON object an image fill encodes to.
    private static func encodedObject(_ fill: PenFill.PenImageFill) throws -> [String: Any] {
        let data = try JSONEncoder().encode(PenFill.image(fill))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Decoding

    static let spellings: [(written: String, mode: PenImageFillMode)] = [
        ("cover", .cover),
        ("contain", .contain),
        ("stretch", .stretch),
        ("fill", .cover),
        ("fit", .contain),
        ("tile", .unknown("tile")),
    ]

    @Test("Every mode spelling decodes", arguments: spellings)
    func decodesEverySpelling(sample: (written: String, mode: PenImageFillMode)) throws {
        let fill = try Self.imageFill(#"{"type":"image","url":"a.png","mode":"\#(sample.written)"}"#)
        #expect(fill.mode == sample.mode)
    }

    @Test("A missing mode decodes as no mode")
    func missingModeDecodesAsNil() throws {
        let fill = try Self.imageFill(#"{"type":"image","url":"a.png"}"#)
        #expect(fill.mode == nil)
    }

    // MARK: - Encoding

    static let encodings: [(written: String, reencoded: String)] = [
        ("cover", "cover"),
        ("contain", "contain"),
        ("stretch", "stretch"),
        ("fill", "cover"),
        ("fit", "contain"),
        ("tile", "tile"),
    ]

    @Test("Each mode re-encodes in its 2.20 spelling, and an unknown one as written", arguments: encodings)
    func reencodesEverySpelling(sample: (written: String, reencoded: String)) throws {
        let fill = try Self.imageFill(#"{"type":"image","url":"a.png","mode":"\#(sample.written)"}"#)
        let object = try Self.encodedObject(fill)
        #expect(object["mode"] as? String == sample.reencoded)
        let again = try Self.imageFill(String(decoding: JSONEncoder().encode(PenFill.image(fill)), as: UTF8.self))
        #expect(again == fill)
    }

    @Test("A missing mode stays missing on encode")
    func missingModeStaysMissing() throws {
        let fill = try Self.imageFill(#"{"type":"image","url":"a.png"}"#)
        #expect(try Self.encodedObject(fill)["mode"] == nil)
    }

    // MARK: - Placement

    @Test("The placement a paint uses: missing and unknown modes are cover")
    func placementResolvesEveryMode() {
        #expect(PenFill.PenImageFill(mode: nil).placement == .cover)
        #expect(PenFill.PenImageFill(mode: .cover).placement == .cover)
        #expect(PenFill.PenImageFill(mode: .contain).placement == .contain)
        #expect(PenFill.PenImageFill(mode: .stretch).placement == .stretch)
        #expect(PenFill.PenImageFill(mode: .unknown("tile")).placement == .cover)
    }

    @Test("Only the three real modes are listed as the vocabulary")
    func allCasesListsTheRealModes() {
        #expect(PenImageFillMode.allCases == [.stretch, .cover, .contain])
        #expect(PenImageFillMode.allCases.map(\.rawString) == ["stretch", "cover", "contain"])
    }

    // MARK: - Transform

    @Test("A transform decodes as six coefficients and re-encodes as the same array")
    func transformRoundTrips() throws {
        let fill = try Self.imageFill(#"{"type":"image","url":"a.png","transform":[2,0,0.5,1,-1,0.25]}"#)
        #expect(fill.transform == PenImageTransform(a: 2, b: 0, c: 0.5, d: 1, tx: -1, ty: 0.25))
        #expect(fill.extras.isEmpty, "transform fell into extras")
        let object = try Self.encodedObject(fill)
        #expect(object["transform"] as? [Double] == [2, 0, 0.5, 1, -1, 0.25])
    }

    @Test("A missing transform stays missing")
    func missingTransformStaysMissing() throws {
        let fill = try Self.imageFill(#"{"type":"image","url":"a.png","mode":"cover"}"#)
        #expect(fill.transform == nil)
        #expect(try Self.encodedObject(fill)["transform"] == nil)
    }

    @Test("A transform that is not six numbers is refused")
    func malformedTransformIsRefused() {
        #expect(throws: DecodingError.self) {
            try Self.imageFill(#"{"type":"image","url":"a.png","transform":[1,0,0,1]}"#)
        }
    }

    @Test("A missing transform is the identity")
    func identityIsTheDefault() {
        #expect(PenImageTransform() == PenImageTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
        #expect(PenImageTransform.identity == PenImageTransform())
    }

    #if canImport(CoreGraphics)
        @Test("A transform converts to the Core Graphics transform with the same coefficients")
        func convertsToCoreGraphics() {
            let transform = PenImageTransform(a: 2, b: 0.1, c: 0.5, d: 3, tx: -1, ty: 0.25).cgAffineTransform
            #expect(transform.a == 2)
            #expect(transform.b == 0.1)
            #expect(transform.c == 0.5)
            #expect(transform.d == 3)
            #expect(transform.tx == -1)
            #expect(transform.ty == 0.25)
        }
    #endif

    // MARK: - A whole document

    @Test("A 2.20 document with every mode and a crop parses")
    func wholeDocumentParses() throws {
        let modes = [#""mode":"cover","#, #""mode":"contain","#, #""mode":"stretch","#, #""mode":"fill","#,
                     #""mode":"fit","#, #""mode":"tile","#, ""]
        let children = modes.enumerated().map { index, mode in
            #"{"type":"rectangle","id":"r\#(index)","width":10,"height":10,"#
                + #""fill":{"type":"image",\#(mode)"url":"a.png","transform":[2,0,0,1,-1,0]}}"#
        }
        let json = #"{"version":"2.20","children":[\#(children.joined(separator: ","))]}"#
        let document = try PenParser.parse(json)
        let placements = document.children.compactMap { node -> PenImageFillMode.Placement? in
            guard case let .rectangle(data) = node.kind, case let .image(image)? = data.fills?.all.first else {
                return nil
            }
            #expect(image.transform == PenImageTransform(a: 2, d: 1, tx: -1))
            return image.placement
        }
        #expect(placements == [.cover, .contain, .stretch, .cover, .contain, .cover, .cover])
    }

    // MARK: - Schema

    @Test("The image fill's schema lists cover, contain, stretch and transform")
    func schemaListsTheModesAndTransform() throws {
        let image = try #require(PenFill.schema.variants.first { $0.spelling == "image" })
        let mode = try #require(image.fields.first { $0.key == "mode" })
        #expect(Set(mode.forms.map(\.signature)) == [#""cover""#, #""contain""#, #""stretch""#])
        let transform = try #require(image.fields.first { $0.key == "transform" })
        #expect(transform.value == "[a, b, c, d, tx, ty]")
    }
}
