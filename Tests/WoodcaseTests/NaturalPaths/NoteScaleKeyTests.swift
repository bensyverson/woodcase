//
//  NoteScaleKeyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A note's look scale is a key of its own (``PenMetadata/WoodcaseKey/scale``), read and
/// written at `note.scale` beside `note.fontSize` (session 41's ruling), its raw key accepted
/// like its siblings': `get`, `tree` and `schema` print it, and a write of a factor that is
/// not a positive finite number is refused.
@MainActor
struct NoteScaleKeyTests {
    private static let board = """
    {
      "version": "2.20",
      "children": [
        {
          "id": "Brd01", "name": "Board", "type": "frame", "x": 0, "y": 0,
          "width": 1000, "height": 1000, "layout": "none",
          "children": [
            { "id": "Nte01", "name": "Sticky", "type": "note", "content": "hi",
              "metadata": { "type": "woodcase", "woodcase": { "fontSize": 18, "scale": 1.5 } } },
            { "id": "Nte02", "name": "Plain", "type": "note", "content": "hi" }
          ]
        }
      ]
    }
    """

    private func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Self.board))
    }

    private func set(_ properties: [String: AnyCodable], on id: String, in document: EditableDocument) throws {
        let plan = try EditPlanner.plan(.set(properties), routedAt: .node(id: id), in: document)
        for operation in plan.operations {
            try document.apply(operation)
        }
    }

    @Test("The key is note.scale, a note text-style alias on the three note types, its raw key accepted")
    func table() {
        let key = PenMetadata.WoodcaseKey.scale
        #expect(key.rawValue == "scale")
        #expect(key.group == .noteTextStyle)
        #expect(key.naturalPath == "note.scale")
        #expect(key.naturalPathTypes == [.note, .prompt, .context])
        #expect(key.storagePathRule == .accepted)
        #expect(key.shape == .number)
        #expect(key.oldSpelling == nil)
        #expect(key.constraint == PenValueConstraint(unit: .factor, minimum: .exclusive(0)))
        #expect(PenPostIt.keys.contains(.scale))
    }

    @Test("note.scale and the raw key write the same metadata.woodcase.scale")
    func bothSpellings() throws {
        let aliased = try document()
        try set(["note.scale": 2], on: "Nte02", in: aliased)
        let raw = try document()
        try set(["common.metadata.woodcase.scale": 2], on: "Nte02", in: raw)
        #expect(aliased.node(id: "Nte02")?.common.metadata?[woodcase: .scale] == 2)
        #expect(aliased.node(id: "Nte02")?.common.metadata == raw.node(id: "Nte02")?.common.metadata)
    }

    @Test("A factor that is not above zero, or not finite, is refused as out of range", arguments: [
        AnyCodable.int(0), .int(-1), .double(-0.5), .double(.infinity), .double(.nan),
    ])
    func refusesNonPositive(value: AnyCodable) throws {
        let refusal = try #require(PlannerFixture.refusal(.set(["note.scale": value]), at: "#Nte01", in: document()))
        #expect(refusal.property == "note.scale")
        #expect(refusal.code == .outOfRange)
    }

    @Test("A factor that is not a number is refused for its form")
    func refusesString() throws {
        let refusal = try #require(PlannerFixture.refusal(.set(["note.scale": "big"]), at: "#Nte01", in: document()))
        #expect(refusal.property == "note.scale")
    }

    @Test("The authoring check refuses a non-positive factor in a whole metadata write")
    func authoringCheck() {
        let violation = PenPostIt.violation(
            in: ["type": "woodcase", "woodcase": .dictionary(["scale": .int(0)])], comparedTo: nil
        )
        #expect(violation?.key == .scale)
        #expect(PenPostIt.violation(
            in: ["type": "woodcase", "woodcase": .dictionary(["scale": .double(2.5)])], comparedTo: nil
        ) == nil)
    }

    @Test("get, tree and the codec print note.scale")
    func readersPrint() throws {
        let document = try document()
        let note = try #require(document.node(id: "Nte01"))
        #expect(try NodePropertyCodec.value(at: "note.scale", of: note) == 1.5)
        #expect(NodePropertyCodec.paths(for: note).contains("note.scale"))
        let report = try NodeLookup.find("Board/Sticky", in: document, expanding: false).report
        #expect(report.properties?["note.scale"] == 1.5)
        let rows = try TreeView.rows(of: document, root: "Board/Sticky", properties: ["note.scale"])
        #expect(rows.first?.properties?["note.scale"] == 1.5)
    }

    @Test("The schema lists note.scale with its range, and the post-it table names it")
    func schema() {
        let row = PenSchema.field("note.scale", for: .note)
        #expect(row?.key == .key("metadata.woodcase.scale"))
        #expect(row?.shape.constraint?.summary == "> 0, a scale factor")
        #expect(PenSchema.field("note.scale", for: .prompt) != nil)
        let entry = SchemaPostItReport().keys.first { $0.key == "note.scale" }
        #expect(entry?.takes == "> 0, a scale factor")
    }

    @Test("A change to a note's scale needs layout, since its padding and author line grow the note")
    func changeNeedsLayout() throws {
        let document = try document()
        let before = try #require(document.node(id: "Nte01"))
        try set(["note.scale": 3], on: "Nte01", in: document)
        let after = try #require(document.node(id: "Nte01"))
        #expect(ChangeCategory.categorize(oldCommon: before.common, newCommon: after.common) == .layout)
    }

    @Test("A note's scale is drawn from its metadata, or the default")
    func source() throws {
        let document = try document()
        #expect(document.node(id: "Nte01")?.noteTextStyleSource(of: .scale) == .metadata)
        #expect(document.node(id: "Nte02")?.noteTextStyleSource(of: .scale) == .default)
    }
}
