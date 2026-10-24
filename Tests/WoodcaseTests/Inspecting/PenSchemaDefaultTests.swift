//
//  PenSchemaDefaultTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What the schema says a property is when a node leaves it unset
/// (``PenSchemaTable/Property/default``), and the string roles of the typography
/// properties. `PenSchemaDefaultEngineTests` holds each default to the engine.
struct PenSchemaDefaultTests {
    private func unset(_ property: String, on type: PenNode.NodeType) -> PenPropertyDefault? {
        PenSchema.field(property, for: type)?.default
    }

    // MARK: - Defaults

    @Test("A frame lays out horizontally from the start, with no gap, padding, radius or clip")
    func frameDefaults() {
        #expect(unset("kind.layout", on: .frame) == .string("horizontal"))
        #expect(unset("kind.justifyContent", on: .frame) == .string("start"))
        #expect(unset("kind.alignItems", on: .frame) == .string("start"))
        #expect(unset("kind.gap", on: .frame) == .number(0))
        #expect(unset("kind.padding", on: .frame) == .number(0))
        #expect(unset("kind.cornerRadius", on: .frame) == .number(0))
        #expect(unset("kind.clip", on: .frame) == .boolean(false))
        #expect(unset("kind.width", on: .frame) == .string("fit_content"))
        #expect(unset("kind.fills", on: .frame) == nil)
        #expect(unset("kind.effects", on: .frame) == nil)
        #expect(unset("common.name", on: .frame) == nil)
    }

    @Test("A text is set in SF Pro 16, regular, upright, left and top, growing to fit")
    func textDefaults() {
        #expect(unset("kind.fontFamily", on: .text) == .string("SF Pro"))
        #expect(unset("kind.fontSize", on: .text) == .number(16))
        #expect(unset("kind.fontWeight", on: .text) == .string("400"))
        #expect(unset("kind.fontStyle", on: .text) == .string("normal"))
        #expect(unset("kind.textAlign", on: .text) == .string("left"))
        #expect(unset("kind.textAlignVertical", on: .text) == .string("top"))
        #expect(unset("kind.textGrowth", on: .text) == .string("auto"))
        #expect(unset("kind.underline", on: .text) == .boolean(false))
        #expect(unset("kind.strikethrough", on: .text) == .boolean(false))
        #expect(unset("kind.content", on: .text) == nil)
    }

    @Test("A text's line height and letter spacing come from its font, not a number")
    func derivedDefaults() {
        #expect(unset("kind.lineHeight", on: .text) == .derived(.fontLineHeight))
        #expect(unset("kind.letterSpacing", on: .text) == .derived(.fontKerning))
        #expect(PenPropertyDefault.derived(.fontLineHeight).value == nil)
    }

    @Test("A note, prompt or context is set at 13 points with 1.35 leading")
    func postItDefaults() {
        for type in [PenNode.NodeType.note, .prompt, .context] {
            #expect(unset("kind.fontSize", on: type) == .number(13), "\(type)")
            #expect(unset("kind.lineHeight", on: type) == .number(1.35), "\(type)")
            #expect(unset("kind.fontFamily", on: type) == .string("SF Pro"), "\(type)")
        }
        #expect(unset("kind.width", on: .note) == .number(PenPostIt.defaultSize))
        #expect(unset("kind.width", on: .prompt) == .number(PenPostIt.cardDefaultWidth))
        #expect(unset("kind.height", on: .context) == .number(PenPostIt.cardDefaultHeight))
    }

    @Test("Every node is placed at the origin, upright, opaque, enabled and in flow")
    func commonDefaults() {
        #expect(unset("common.x", on: .rectangle) == .number(0))
        #expect(unset("common.rotation", on: .rectangle) == .number(0))
        #expect(unset("common.opacity", on: .rectangle) == .number(1))
        #expect(unset("common.enabled", on: .rectangle) == .boolean(true))
        #expect(unset("common.flipX", on: .rectangle) == .boolean(false))
        #expect(unset("common.layoutPosition", on: .rectangle) == .string("auto"))
    }

    @Test("Strokes are no width (no stroke, as Pen draws one), centered, mitered and butt-capped; shapes have their own")
    func strokeAndShapeDefaults() {
        #expect(unset("kind.strokeWidth", on: .rectangle) == .number(0))
        #expect(unset("kind.strokeAlignment", on: .line) == .string("center"))
        #expect(unset("kind.strokeLinejoin", on: .polygon) == .string("miter"))
        #expect(unset("kind.strokeLinecap", on: .line) == .string("butt"))
        #expect(unset("kind.blendMode", on: .group) == .string("normal"))
        #expect(unset("kind.sweepAngle", on: .ellipse) == .number(360))
        #expect(unset("kind.polygonCount", on: .polygon) == .number(6))
        #expect(unset("kind.fillRule", on: .path) == .string("nonzero"))
    }

    @Test("Each enumerated default is one of the property's own spellings")
    func defaultsAreSpellings() {
        var checked = 0
        for type in PenNode.NodeType.allCases {
            for property in PenSchema.fields(for: type) where !property.spellings.isEmpty {
                guard case let .string(spelling)? = property.default else { continue }
                #expect(property.spellings.contains(spelling), "\(type) \(property.path)")
                checked += 1
            }
        }
        #expect(checked > 0)
    }

    // MARK: - String roles

    @Test("fontFamily, fontWeight and fontStyle carry string roles of their own")
    func typographyRoles() throws {
        for type in [PenNode.NodeType.text, .note] {
            let family = try #require(PenSchema.field("kind.fontFamily", for: type))
            #expect(family.shape.forms == [.text(.fontFamily), .variable(.string)])
            let weight = try #require(PenSchema.field("kind.fontWeight", for: type))
            #expect(weight.shape.forms == [.text(.fontWeight), .variable(.string)])
            let style = try #require(PenSchema.field("kind.fontStyle", for: type))
            #expect(style.shape.forms == [.text(.fontStyle), .variable(.string)])
        }
    }

    @Test("The weight role's keywords read as every CSS weight from 100 to 900")
    func weightKeywords() {
        let keywords = PenValueForm.StringRole.fontWeight.keywords
        #expect(keywords.contains("bold"))
        #expect(keywords.contains("normal"))
        #expect(Set(keywords.map(PenFontWeight.cssWeight)) == Set(stride(from: 100.0, through: 900, by: 100)))
    }

    @Test("The style role's keywords are its two faces; other roles name none")
    func otherKeywords() {
        #expect(PenValueForm.StringRole.fontStyle.keywords == ["normal", "italic"])
        #expect(PenValueForm.StringRole.fontFamily.keywords.isEmpty)
        #expect(PenValueForm.StringRole.plain.keywords.isEmpty)
    }

    @Test("A number written to a typography string is still stored as the string it spells")
    func numberCoercion() {
        let text = PenNode.Kind.text(PenNode.TextData())
        #expect(NodePropertyCodec.coercing(700, at: "kind.fontWeight", on: text) == "700")
        #expect(NodePropertyCodec.coercing(12, at: "kind.fontFamily", on: text) == "12")
    }
}
