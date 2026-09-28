//
//  PenFontFaceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A text node's face — family, CSS weight and style — as the font resolver and the
/// SwiftUI bundler read it, and the walk that collects every face a document draws.
@Suite("PenFontFace")
struct PenFontFaceTests {
    @Test("A face reads its weight as CSS reads it, and 400 upright when nothing is set")
    func readsWeightAndStyle() {
        #expect(PenFontFace(family: "Lora", fontWeight: "bold", fontStyle: nil)
            == PenFontFace(family: "Lora", weight: 700, style: .normal))
        #expect(PenFontFace(family: "Lora", fontWeight: "650", fontStyle: "Italic")
            == PenFontFace(family: "Lora", weight: 650, style: .italic))
        #expect(PenFontFace(family: "Lora", fontWeight: nil, fontStyle: nil)
            == PenFontFace(family: "Lora", weight: 400, style: .normal))
        #expect(PenFontFace.regular(of: "Lora") == PenFontFace(family: "Lora", weight: 400, style: .normal))
    }

    @Test("A document's faces are every family, weight and style its text nodes set")
    func collectsFaces() throws {
        let document = try PenParser.parse("""
        {
          "version": "2.17",
          "children": [
            {"type": "frame", "id": "f", "children": [
              {"type": "text", "id": "a", "content": "a", "fontFamily": "Lora"},
              {"type": "text", "id": "b", "content": "b", "fontFamily": "Lora", "fontWeight": "700"},
              {"type": "group", "id": "g", "children": [
                {"type": "text", "id": "c", "content": "c", "fontFamily": "Lora", "fontWeight": "700", "fontStyle": "italic"}
              ]}
            ]},
            {"type": "text", "id": "d", "content": "d", "fontFamily": "Spectral", "fontStyle": "italic"},
            {"type": "text", "id": "e", "content": "e"}
          ]
        }
        """)
        #expect(GoogleFontResolver.collectFontFaces(from: document) == [
            PenFontFace(family: "Lora", weight: 400, style: .normal),
            PenFontFace(family: "Lora", weight: 700, style: .normal),
            PenFontFace(family: "Lora", weight: 700, style: .italic),
            PenFontFace(family: "Spectral", weight: 400, style: .italic),
        ])
        #expect(GoogleFontResolver.collectFontFamilies(from: document) == ["Lora", "Spectral"])
    }
}
