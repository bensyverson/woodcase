//
//  SlotFillRewriteTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An override addressed to content an instance wrote into its own slot is rewritten into
/// that slot's `children`.
///
/// Pen drops a `descendants` key naming such content
/// (`project/2026-09-26-slot-override-keys.md`, rule 5), so the key is never written: the
/// property lands on the node inside the fill, where Pen reads it, and the write says so.
@MainActor
struct SlotFillRewriteTests {
    // MARK: - Fixtures

    private func slotFill() throws -> EditableDocument {
        let url = try #require(Bundle.module.url(
            forResource: "slot-fill", withExtension: "pen", subdirectory: "Fixtures"
        ))
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    /// `Card` has a `Body` slot, `Badge` a `Hole` slot. `Inst` fills `Body` with a frame
    /// `Box1` holding `Deep1`, and with `Tag`, a `Badge` instance filling its own `Hole`
    /// with `Inner`. `Use` fills the slot of `Box`'s nested `Inn` with `NewY`.
    private func nested() throws -> EditableDocument {
        let json = """
        {"version": "2.17", "children": [
          {"id": "Card", "type": "frame", "reusable": true, "width": 200, "height": 100, "children": [
            {"id": "Body", "name": "Body", "type": "frame", "slot": ["frame", "ref"], "width": 150, "height": 80}]},
          {"id": "Badge", "type": "frame", "reusable": true, "width": 60, "height": 20, "children": [
            {"id": "Hole", "name": "Hole", "type": "frame", "slot": ["text"], "width": 40, "height": 12}]},
          {"id": "Slt", "type": "frame", "reusable": true, "width": 200, "height": 40, "children": [
            {"id": "Hole2", "type": "frame", "name": "Hole2", "width": 150, "height": 30, "children": []}]},
          {"id": "Box", "type": "frame", "reusable": true, "width": 200, "height": 40, "children": [
            {"id": "Inn", "type": "ref", "name": "Inner", "ref": "Slt"}]},
          {"id": "Inst", "type": "ref", "name": "Inst", "ref": "Card", "descendants": {
            "Body": {"gap": 4, "children": [
              {"id": "Box1", "type": "frame", "name": "Box1", "width": 50, "height": 50, "children": [
                {"id": "Deep1", "type": "rectangle", "name": "Deep", "width": 10, "height": 10, "fill": "#FF0000"}]},
              {"id": "Tag", "type": "ref", "name": "Tag", "ref": "Badge", "descendants": {
                "Hole": {"children": [{"id": "Inner", "type": "text", "name": "Inner", "content": "in"}]}}}]}}},
          {"id": "Use", "type": "ref", "name": "Use", "ref": "Box", "descendants": {
            "Inn/Hole2": {"children": [{"id": "NewY", "type": "rectangle", "width": 20, "height": 20}]}}}
        ]}
        """
        return try EditableDocument(from: PenParser.parse(Data(json.utf8)))
    }

    // MARK: - Helpers

    private func override(
        _ address: String,
        _ props: [String: AnyCodable] = [:],
        unset: [String] = []
    ) throws -> BatchOperation {
        try .override(BatchOperation.OverrideOp(
            target: #require(NodeAddress(address)), props: props, unset: unset
        ))
    }

    private func descendants(of refID: String, in document: EditableDocument) -> [String: PenDescendantOverride] {
        guard case let .ref(data) = document.nodes[refID]?.kind else { return [:] }
        return data.descendants ?? [:]
    }

    /// The node JSON with this id anywhere in a list of node JSONs, descending through
    /// inline `children` and through a ref's `descendants` fills.
    private func find(_ id: String, in nodes: [AnyCodable]) -> [String: AnyCodable]? {
        for case let .dictionary(node) in nodes {
            if node["id"] == .string(id) { return node }
            if case let .array(children)? = node["children"], let hit = find(id, in: children) { return hit }
            if case let .dictionary(map)? = node["descendants"] {
                for case let .dictionary(entry) in map.values {
                    if case let .array(children)? = entry["children"], let hit = find(id, in: children) {
                        return hit
                    }
                }
            }
        }
        return nil
    }

    private func fill(_ key: String, of refID: String, in document: EditableDocument) -> [AnyCodable] {
        guard case let .array(children)? = descendants(of: refID, in: document)[key]?.properties["children"]
        else { return [] }
        return children
    }

    // MARK: - The rewrite

    @Test("An override on an injected child lands on the child inside the slot's children")
    func overrideLandsInTheFill() throws {
        let doc = try slotFill()

        let result = try BatchApplier.applyOne(override("Inst0/Note0", ["content": .string("Hi")]), to: doc)

        #expect(Set(descendants(of: "Inst0", in: doc).keys) == ["CSlt0"])
        let note = find("Note0", in: fill("CSlt0", of: "Inst0", in: doc))
        #expect(note?["content"] == .string("Hi"))
        #expect(note?["fontSize"] == .int(12))
        let rewrite = result.divergences.first { $0.kind == .slotFillRewrite }
        #expect(rewrite?.severity == .note)
        #expect(rewrite?.requested == "Inst0/Note0")
        #expect(rewrite?.applied == "Page/Filled/Body")
    }

    @Test("The expansion draws the rewritten child")
    func expansionDrawsTheRewrite() throws {
        let doc = try slotFill()

        _ = try BatchApplier.applyOne(override("Page/Filled/Body/Note", ["content": .string("Hi")]), to: doc)

        let rows = try TreeView.rows(of: doc, root: "Page0", expandInstances: true, properties: ["kind.content"])
        #expect(rows.first { $0.id == "Inst0/Note0" }?.properties?["kind.content"] == .string("Hi"))
    }

    @Test("A node inside an injected ref is overridden on that ref, inside the fill")
    func injectedRefDescendantLandsOnTheRef() throws {
        let doc = try slotFill()

        _ = try BatchApplier.applyOne(override("Inst0/Tag00/BTxt0", ["content": .string("Hi")]), to: doc)

        #expect(Set(descendants(of: "Inst0", in: doc).keys) == ["CSlt0"])
        let tag = find("Tag00", in: fill("CSlt0", of: "Inst0", in: doc))
        #expect(tag?["descendants"] == .dictionary(["BTxt0": .dictionary(["content": .string("Hi")])]))
    }

    @Test("--unset removes the property from the child in the fill")
    func unsetRemovesFromTheChild() throws {
        let doc = try slotFill()

        _ = try BatchApplier.applyOne(override("Inst0/Note0", unset: ["fill"]), to: doc)

        let note = find("Note0", in: fill("CSlt0", of: "Inst0", in: doc))
        #expect(note != nil)
        #expect(note?["fill"] == nil)
        #expect(note?["content"] == .string("filled from the instance"))
    }

    @Test("A deeper node of the fill is rewritten where it sits, and the slot's other keys stay")
    func deeperNodeOfTheFill() throws {
        let doc = try nested()

        _ = try BatchApplier.applyOne(override("Inst/Deep1", ["fill": .string("#00FF00")]), to: doc)

        #expect(Set(descendants(of: "Inst", in: doc).keys) == ["Body"])
        #expect(descendants(of: "Inst", in: doc)["Body"]?.properties["gap"] == .int(4))
        #expect(find("Deep1", in: fill("Body", of: "Inst", in: doc))?["fill"] == .string("#00FF00"))
    }

    @Test("Content an injected ref wrote into its own slot is rewritten into that ref's fill")
    func injectedRefsOwnFill() throws {
        let doc = try nested()

        _ = try BatchApplier.applyOne(override("Inst/Tag/Inner", ["content": .string("Hi")]), to: doc)

        let tag = try #require(find("Tag", in: fill("Body", of: "Inst", in: doc)))
        guard case let .dictionary(map)? = tag["descendants"] else {
            Issue.record("Tag lost its descendants")
            return
        }
        #expect(Set(map.keys) == ["Hole"])
        #expect(find("Inner", in: [.dictionary(tag)])?["content"] == .string("Hi"))
    }

    @Test("An instance's own fill of a nested instance's slot is rewritten under its cross-ref key")
    func ownFillOfANestedSlot() throws {
        let doc = try nested()

        let result = try BatchApplier.applyOne(override("Use/Inn/NewY", ["fill": .string("#0000FF")]), to: doc)

        #expect(Set(descendants(of: "Use", in: doc).keys) == ["Inn/Hole2"])
        #expect(find("NewY", in: fill("Inn/Hole2", of: "Use", in: doc))?["fill"] == .string("#0000FF"))
        #expect(result.divergences.first { $0.kind == .slotFillRewrite }?.applied == "Use/Inner/Hole2")
    }

    @Test("A batch rewrites exactly as a single write does")
    func batchAgreesWithApplyOne() throws {
        let single = try slotFill()
        _ = try BatchApplier.applyOne(override("Inst0/Note0", ["content": .string("Hi")]), to: single)

        let batched = try slotFill()
        let report = try BatchApplier.apply(
            BatchOperation.decodeJSONL(#"{"op":"override","target":"Inst0/Note0","props":{"content":"Hi"}}"#),
            to: batched
        )

        #expect(report.lines.map(\.status) == [.applied])
        #expect(descendants(of: "Inst0", in: batched) == descendants(of: "Inst0", in: single))
        #expect(report.lines.first?.divergences.contains { $0.kind == .slotFillRewrite } == true)
    }

    @Test("The recorded inverse restores the fill as it was")
    func inverseRestoresTheFill() throws {
        let doc = try slotFill()
        let before = descendants(of: "Inst0", in: doc)
        let recorder = ActivityRecorder(
            document: doc, file: URL(fileURLWithPath: "/tmp/slot-fill.pen"), identity: "ana", batch: "b"
        )

        _ = try BatchApplier.applyOne(
            override("Inst0/Note0", ["content": .string("Hi")]), to: doc, recorder: recorder
        )
        #expect(descendants(of: "Inst0", in: doc) != before)

        for event in recorder.events.reversed() {
            for inverse in event.inverse {
                try doc.apply(inverse)
            }
        }
        #expect(descendants(of: "Inst0", in: doc) == before)
    }

    @Test("A value the child cannot take is refused naming the child, and nothing is written")
    func rejectedValueNamesTheChild() throws {
        let doc = try slotFill()
        let before = descendants(of: "Inst0", in: doc)

        let error = #expect(throws: EditingError.self) {
            try BatchApplier.applyOne(override("Inst0/Note0", ["fontSize": .array([.int(1)])]), to: doc)
        }

        guard case let .overrideValueRejected(_, descendantKey, key, _, _)? = error else {
            Issue.record("expected overrideValueRejected, got \(String(describing: error))")
            return
        }
        #expect(descendantKey == "Note0")
        #expect(key == "fontSize")
        #expect(descendants(of: "Inst0", in: doc) == before)
    }
}
