//
//  EditPlannerTextGrowthTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Changing a text's `textGrowth` keeps the size it is drawn at: each dimension that stops
/// following the text is written as the number it was drawn at, and each that starts
/// following it again drops its number (Penumbra spec §4.4, the integrator's ruling of
/// 2026-10-15, leaf Q2hXKO).
@MainActor
struct EditPlannerTextGrowthTests {
    /// `Auto` follows its text both ways; `Wide` holds a width of 120 and grows down;
    /// `Boxed` holds 120 × 40; `Filled` fills a stack's width; `Chip` is an instance of
    /// `Card`, whose `Label` follows its text.
    private static let json = """
    {
      "version": "2.19",
      "children": [
        { "type": "frame", "id": "Board", "x": 0, "y": 0, "width": 800, "height": 600, "layout": "none", "children": [
          { "type": "text", "id": "Auto", "x": 10, "y": 10, "content": "Hello world",
            "fontFamily": "Inter", "fontSize": 16 },
          { "type": "text", "id": "Wide", "x": 10, "y": 100, "textGrowth": "fixed-width", "width": 120,
            "content": "A longer sentence that wraps onto more than one line", "fontFamily": "Inter", "fontSize": 16 },
          { "type": "text", "id": "Boxed", "x": 10, "y": 300, "textGrowth": "fixed-width-height",
            "width": 120, "height": 40, "content": "Boxed", "fontFamily": "Inter", "fontSize": 16 },
          { "type": "frame", "id": "Col", "x": 300, "y": 10, "width": 200, "height": "fit_content",
            "layout": "vertical", "children": [
            { "type": "text", "id": "Filled", "width": "fill_container", "content": "Filled",
              "fontFamily": "Inter", "fontSize": 16 }
          ] }
        ] },
        { "type": "ref", "id": "Chip", "ref": "Card", "x": 900, "y": 0 },
        { "type": "frame", "id": "Card", "reusable": true, "x": 900, "y": 200, "width": 200, "height": 60,
          "layout": "none", "children": [
          { "type": "text", "id": "Label", "x": 4, "y": 4, "content": "Label text", "fontFamily": "Inter", "fontSize": 16 }
        ] }
      ]
    }
    """

    /// The size a node is drawn at, as the document stands.
    private func drawn(_ address: ResolvedNodeAddress, in document: EditableDocument) throws -> PenSize {
        let layout = WrapFixture.layout(of: document)
        return try #require(layout.rects[document.expandedID(of: address)]?.drawnSize)
    }

    /// Plans and applies a set of `kind.textGrowth`, plus any other values, on a node.
    private func setGrowth(
        _ growth: String, extra: [String: AnyCodable] = [:], on id: String, in document: EditableDocument
    ) throws -> PenNode {
        var properties = extra
        properties["kind.textGrowth"] = .string(growth)
        let plan = try EditPlanner.plan(.set(properties), at: .path([id]), in: document)
        try WrapFixture.apply(plan.operations, to: document)
        return try #require(document.node(id: id))
    }

    private func number(_ path: String, of node: PenNode) throws -> Double? {
        switch try NodePropertyCodec.value(at: path, of: node) {
        case let .int(whole): Double(whole)
        case let .double(fraction): fraction
        default: nil
        }
    }

    private func value(_ path: String, of node: PenNode) throws -> AnyCodable {
        try NodePropertyCodec.value(at: path, of: node)
    }

    /// Whether a node stores nothing at a path, so it reads as its default.
    private func isUnset(_ path: String, of node: PenNode) -> Bool {
        ((try? NodePropertyCodec.value(at: path, of: node)) ?? .null) == .null
    }

    @Test("Auto to fixed width writes the width it was drawn at, and leaves the height to the text")
    func autoToFixedWidth() throws {
        let document = try WrapFixture.document(Self.json)
        let before = try drawn(.node(id: "Auto"), in: document)
        let node = try setGrowth("fixed-width", on: "Auto", in: document)
        #expect(try abs((number("kind.width", of: node) ?? 0) - before.width) < 1e-3)
        #expect(isUnset("kind.height", of: node))
        let after = try drawn(.node(id: "Auto"), in: document)
        #expect(abs(after.width - before.width) < 1e-3 && abs(after.height - before.height) < 1e-3)
    }

    @Test("Auto to fixed size writes the width and height it was drawn at")
    func autoToFixedSize() throws {
        let document = try WrapFixture.document(Self.json)
        let before = try drawn(.node(id: "Auto"), in: document)
        let node = try setGrowth("fixed-width-height", on: "Auto", in: document)
        #expect(try abs((number("kind.width", of: node) ?? 0) - before.width) < 1e-3)
        #expect(try abs((number("kind.height", of: node) ?? 0) - before.height) < 1e-3)
    }

    @Test("Fixed width to fixed size writes only the height it was drawn at")
    func fixedWidthToFixedSize() throws {
        let document = try WrapFixture.document(Self.json)
        let before = try drawn(.node(id: "Wide"), in: document)
        let node = try setGrowth("fixed-width-height", on: "Wide", in: document)
        #expect(try number("kind.width", of: node) == 120)
        #expect(try abs((number("kind.height", of: node) ?? 0) - before.height) < 1e-3)
        #expect(before.height > 20, "the fixture's text should wrap")
    }

    @Test("Fixed width to auto drops the width, so it follows the text again")
    func fixedWidthToAuto() throws {
        let document = try WrapFixture.document(Self.json)
        let node = try setGrowth("auto", on: "Wide", in: document)
        #expect(isUnset("kind.width", of: node))
        #expect(try drawn(.node(id: "Wide"), in: document).width > 120)
    }

    @Test("Fixed size to auto drops both numbers; to fixed width, only the height")
    func fixedSizeDrops() throws {
        let toAuto = try WrapFixture.document(Self.json)
        let auto = try setGrowth("auto", on: "Boxed", in: toAuto)
        #expect(isUnset("kind.width", of: auto))
        #expect(isUnset("kind.height", of: auto))

        let toWidth = try WrapFixture.document(Self.json)
        let wide = try setGrowth("fixed-width", on: "Boxed", in: toWidth)
        #expect(try number("kind.width", of: wide) == 120)
        #expect(isUnset("kind.height", of: wide))
    }

    @Test("A size written with the change wins over the drawn one")
    func writtenSizeWins() throws {
        let document = try WrapFixture.document(Self.json)
        let node = try setGrowth("fixed-width", extra: ["kind.width": .int(77)], on: "Auto", in: document)
        #expect(try number("kind.width", of: node) == 77)
    }

    @Test("The same growth again writes nothing else")
    func sameGrowth() throws {
        let document = try WrapFixture.document(Self.json)
        let plan = try EditPlanner.plan(.set(["kind.textGrowth": .string("fixed-width")]), at: .path(["Wide"]), in: document)
        #expect(plan.operations == [.setProperties(EditOperation.SetProperties(
            nodeID: "Wide", properties: ["kind.textGrowth": .string("fixed-width")]
        ))])
    }

    @Test("A fill width does not follow the text, so it stays when the growth fixes the width")
    func fillWidthStays() throws {
        let document = try WrapFixture.document(Self.json)
        let node = try setGrowth("fixed-width", on: "Filled", in: document)
        #expect(try value("kind.width", of: node) == .string("fill_container"))
    }

    @Test("An override of a text's growth inside an instance writes the drawn size as overrides too")
    func overrideInsideAnInstance() throws {
        let document = try WrapFixture.document(Self.json)
        let label = ResolvedNodeAddress.instanceDescendant(refID: "Chip", descendantKey: "Label")
        let before = try drawn(label, in: document)
        let plan = try EditPlanner.plan(
            .override(["kind.textGrowth": .string("fixed-width-height")]), at: label, in: document
        )
        guard case let .overrideDescendant(override)? = plan.operations.first else {
            Issue.record("not an override: \(plan.operations)")
            return
        }
        #expect(override.properties["width"] == EditPlanner.number(before.width))
        #expect(override.properties["height"] == EditPlanner.number(before.height))
        try WrapFixture.apply(plan.operations, to: document)
        let after = try drawn(label, in: document)
        #expect(abs(after.width - before.width) < 1e-3 && abs(after.height - before.height) < 1e-3)
        let component = try #require(document.node(id: "Label"))
        #expect(isUnset("kind.width", of: component))

        // Back to auto: the override must outweigh any number, so it writes fit_content.
        let back = try EditPlanner.plan(.override(["kind.textGrowth": .string("auto")]), at: label, in: document)
        guard case let .overrideDescendant(reset)? = back.operations.first else {
            Issue.record("not an override: \(back.operations)")
            return
        }
        #expect(reset.properties["width"] == .string("fit_content"))
        #expect(reset.properties["height"] == .string("fit_content"))
    }
}
