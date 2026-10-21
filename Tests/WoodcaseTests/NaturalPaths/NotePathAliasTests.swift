//
//  NotePathAliasTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The note keys and a note's text style read and write through `note.*` aliases (leaf
/// DPY8DH; `project/2026-10-20-natural-paths-for-woodcase-properties.md`, rule 4 widened):
/// `note.state=done` writes `metadata.woodcase.state`, the same key the raw
/// `common.metadata.woodcase.state` write does, and the raw write stays accepted, because
/// the note convention is published for tools without Woodcase. Woodcase's own readers print
/// the `note.*` spelling.
@MainActor
struct NotePathAliasTests {
    private static let board = """
    {
      "version": "2.20",
      "children": [
        {
          "id": "Brd01", "name": "Board", "type": "frame", "x": 0, "y": 0,
          "width": 1000, "height": 1000, "layout": "none",
          "children": [
            { "id": "Prm01", "name": "Ask", "type": "prompt", "content": "Tighten the copy", "model": "claude-opus-5-5",
              "metadata": { "type": "woodcase", "woodcase": { "state": "queued", "requestedBy": "ben" } } },
            { "id": "Nte01", "name": "Sticky", "type": "note", "content": "hi",
              "metadata": { "type": "woodcase", "woodcase": { "tint": "#A5D6A7", "fontSize": 18 } } },
            { "id": "Rct01", "name": "Box", "type": "rectangle", "width": 10, "height": 10 }
          ]
        }
      ]
    }
    """

    private static let noteKeys: [PenMetadata.WoodcaseKey] = PenMetadata.WoodcaseKey.allCases.filter {
        $0.group == .note || $0.group == .noteTextStyle
    }

    private func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Self.board))
    }

    private func set(_ properties: [String: AnyCodable], on id: String, in document: EditableDocument) throws {
        let plan = try EditPlanner.plan(.set(properties), routedAt: .node(id: id), in: document)
        for operation in plan.operations {
            try document.apply(operation)
        }
    }

    // MARK: - The table

    @Test("Each note key's alias is note.<key>, on the three note types, and its raw write stays accepted")
    func table() {
        #expect(Self.noteKeys.count == 19)
        for key in Self.noteKeys {
            #expect(key.naturalPath == "note.\(key.rawValue)")
            #expect(key.naturalPathTypes == [.note, .prompt, .context])
            #expect(key.storagePathRule == .accepted)
        }
        #expect(PenMetadata.WoodcaseKey.strokeDash.storagePathRule == .refused)
        #expect(PenMetadata.WoodcaseKey.role.storagePathRule == .refused)
        #expect(PenMetadata.WoodcaseKey.shadowSpread.storagePathRule == .refused)
    }

    // MARK: - Writing

    @Test("note.state=done writes the same key a raw write does, and both spellings are accepted")
    func bothSpellingsWriteOneKey() throws {
        let aliased = try document()
        try set(["note.state": "done"], on: "Prm01", in: aliased)
        let raw = try document()
        try set(["common.metadata.woodcase.state": "done"], on: "Prm01", in: raw)
        let viaAlias = try #require(aliased.node(id: "Prm01")?.common.metadata)
        #expect(viaAlias[woodcase: .state] == "done")
        #expect(viaAlias[woodcase: .requestedBy] == "ben")
        #expect(viaAlias == raw.node(id: "Prm01")?.common.metadata)
    }

    @Test("A note.* value is held to the key's form, and the refusal names note.*")
    func formIsHeld() throws {
        let refusal = try #require(PlannerFixture.refusal(.set(["note.state": "resolved"]), at: "#Prm01", in: document()))
        #expect(refusal.property == "note.state")
        #expect(refusal.code == .invalidForm, "refused as \(refusal.code), not for its form")
    }

    @Test("A refusal keeps the caller's spelling: the alias for an alias write, the raw path for a raw one")
    func refusalKeepsSpelling() throws {
        let raw = try #require(PlannerFixture.refusal(
            .set(["common.metadata.woodcase.state": "resolved"]), at: "#Prm01", in: document()
        ))
        #expect(raw.property == "common.metadata.woodcase.state")
        let size = try #require(PlannerFixture.refusal(.set(["note.fontSize": 0]), at: "#Nte01", in: document()))
        #expect(size.property == "note.fontSize")
    }

    @Test("A note.* alias is no property of a node that is not a note")
    func notOnOtherTypes() throws {
        #expect(try PlannerFixture.refusal(.set(["note.tint": "#A5D6A7"]), at: "#Nte01", in: document()) == nil)
        #expect(try PlannerFixture.refusal(.set(["note.tint": "#A5D6A7"]), at: "#Rct01", in: document()) != nil)
        #expect(throws: EditingError.self) {
            try NodePropertyCodec.value(at: "note.tint", of: #require(document().node(id: "Rct01")))
        }
    }

    // MARK: - Reading

    @Test("get, tree and the codec print the note.* spelling")
    func readersPrintAlias() throws {
        let document = try document()
        let note = try #require(document.node(id: "Nte01"))
        #expect(try NodePropertyCodec.value(at: "note.tint", of: note) == "#A5D6A7")
        #expect(NodePropertyCodec.paths(for: note).contains("note.fontSize"))
        let report = try NodeLookup.find("Board/Sticky", in: document, expanding: false).report
        #expect(report.properties?["note.tint"] == "#A5D6A7")
        #expect(report.properties?["note.fontSize"] == 18)
        let rows = try TreeView.rows(of: document, root: "Board/Ask", properties: ["note.state"])
        #expect(rows.first?.properties?["note.state"] == "queued")
    }

    @Test("The schema lists each note key at its note.* path, with the metadata key the file stores it under")
    func schema() {
        for key in Self.noteKeys {
            let row = PenSchema.field("note.\(key.rawValue)", for: .note)
            #expect(row?.key == .key("metadata.woodcase.\(key.rawValue)"), "\(key)")
        }
        #expect(SchemaPostItReport().keys.map(\.key).allSatisfy { $0.hasPrefix("note.") })
    }
}
