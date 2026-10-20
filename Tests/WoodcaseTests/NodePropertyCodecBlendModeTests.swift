//
//  NodePropertyCodecBlendModeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `kind.blendMode` is a natural path: every caller reads and writes it as before, and
/// Woodcase stores it in `metadata.woodcase.blendMode` (leaf TesTbK). It is the first
/// row of the natural-path table 9Sw8C0 generalizes
/// (`project/2026-10-20-natural-paths-for-woodcase-properties.md`).
@MainActor
struct NodePropertyCodecBlendModeTests {
    private static let json = """
    {"version": "2.19", "children": [
      {"type": "frame", "id": "Board", "width": 400, "height": 400, "layout": "none", "children": [
        {"type": "rectangle", "id": "Card", "x": 10, "y": 10, "width": 50, "height": 30, "fill": "#FF0000",
         "metadata": {"type": "component", "woodcase": {"role": "card"}}},
        {"type": "group", "id": "Mix", "metadata": {"type": "woodcase", "woodcase": {"blendMode": "screen"}}}
      ]}
    ]}
    """

    private func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Self.json))
    }

    private func node(_ id: String) throws -> PenNode {
        try #require(document().node(id: id))
    }

    // MARK: - The table

    @Test("The blend key names kind.blendMode as its natural path")
    func keyNamesNaturalPath() {
        #expect(PenMetadata.WoodcaseKey.blendMode.naturalPath == "kind.blendMode")
        #expect(PenMetadata.WoodcaseKey(naturalPath: "kind.blendMode") == .blendMode)
        #expect(PenMetadata.WoodcaseKey(naturalPath: "kind.fills") == nil)
        #expect(PenMetadata.WoodcaseKey.blendMode.group == .compositing)
    }

    @Test("Only the blend key has a natural path yet")
    func onlyBlendHasOne() {
        #expect(PenMetadata.WoodcaseKey.allCases.filter { $0.naturalPath != nil } == [.blendMode])
    }

    // MARK: - Reading

    @Test("Reading kind.blendMode reads the stored key")
    func readsStorage() throws {
        #expect(try NodePropertyCodec.value(at: "kind.blendMode", of: node("Mix")) == .string("screen"))
        #expect(try NodePropertyCodec.value(at: "kind.blendMode", of: node("Card")) == .null)
    }

    @Test("kind.blendMode is still in the vocabulary of every type that takes a blend")
    func stillInVocabulary() throws {
        #expect(try NodePropertyCodec.paths(for: node("Card")).contains("kind.blendMode"))
        #expect(try NodePropertyCodec.paths(for: node("Mix")).contains("kind.blendMode"))
    }

    // MARK: - Writing

    @Test("Writing kind.blendMode stores it in metadata.woodcase and keeps the rest of the metadata")
    func writesStorage() throws {
        let card = try NodePropertyCodec.setting(.string("multiply"), at: "kind.blendMode", on: node("Card"))
        #expect(card.blendMode == .multiply)
        #expect(card.common.metadata?[woodcase: .blendMode] == .string("multiply"))
        #expect(card.common.metadata?[woodcase: .role] == .string("card"))
        #expect(card.common.metadata?.type == "component")
        #expect(try NodePropertyCodec.value(at: "kind.blendMode", of: card) == .string("multiply"))
    }

    @Test("Writing null to kind.blendMode removes the stored key, and metadata it emptied")
    func nullClears() throws {
        let mix = try NodePropertyCodec.setting(.null, at: "kind.blendMode", on: node("Mix"))
        #expect(mix.blendMode == nil)
        #expect(mix.common.metadata == nil)
    }

    @Test("A value that is not a string is refused under kind.blendMode")
    func nonStringRefused() throws {
        #expect {
            try NodePropertyCodec.setting(.int(3), at: "kind.blendMode", on: node("Card"))
        } throws: { error in
            guard case let .propertyTypeMismatch(_, key, _, _)? = error as? EditingError else { return false }
            return key == "kind.blendMode"
        }
    }

    @Test("Folding turns kind.blendMode into a write of the node's metadata")
    func foldingStoresIt() throws {
        let folded = try NodePropertyCodec.folding(["kind.blendMode": .string("multiply")], onto: node("Card"))
        #expect(folded["kind.blendMode"] == nil)
        guard case let .dictionary(metadata)? = folded[NodePropertyCodec.metadataPath] else {
            Issue.record("no metadata write: \(folded)")
            return
        }
        #expect(PenMetadata(object: metadata)[woodcase: .blendMode] == .string("multiply"))
        #expect(PenMetadata(object: metadata)[woodcase: .role] == .string("card"))
    }

    @Test("A set through the planner writes metadata.woodcase, not a top-level blendMode")
    func plannedSetWritesMetadata() throws {
        let document = try document()
        let plan = try EditPlanner.plan(
            .set(["kind.blendMode": .string("multiply")]), routedAt: .node(id: "Card"), in: document
        )
        for operation in plan.operations {
            guard case let .setProperties(write) = operation else { continue }
            #expect(write.properties.keys.sorted() == [NodePropertyCodec.metadataPath])
        }
        for operation in plan.operations {
            try document.apply(operation)
        }
        let card = try #require(document.node(id: "Card"))
        #expect(card.blendMode == .multiply)
        guard case let .dictionary(written) = try NodePropertyCodec.encode(card) else {
            Issue.record("the node did not encode as an object")
            return
        }
        #expect(written["blendMode"] == nil)
        guard case let .dictionary(metadata)? = written["metadata"],
              case let .dictionary(keys)? = metadata[PenMetadata.woodcaseNamespace]
        else {
            Issue.record("no metadata.woodcase written: \(written)")
            return
        }
        #expect(keys["blendMode"] == .string("multiply"))
        #expect(keys["role"] == .string("card"))
    }

    @Test("An unplanned setProperties of kind.blendMode normalizes into a metadata write")
    func normalizedWritesMetadata() throws {
        let document = try document()
        let operation = EditOperation.setProperties(
            EditOperation.SetProperties(nodeID: "Card", properties: ["kind.blendMode": .string("multiply")])
        ).normalized(in: document)
        guard case let .setProperties(write) = operation else {
            Issue.record("not a set: \(operation)")
            return
        }
        #expect(write.properties.keys.sorted() == [NodePropertyCodec.metadataPath])
    }

    // MARK: - Schema

    @Test("The schema row for kind.blendMode names where the file stores it")
    func schemaNamesStorage() {
        let row = PenSchema.field("kind.blendMode", for: .frame)
        #expect(row?.path == "kind.blendMode")
        #expect(row?.key == .key("metadata.woodcase.blendMode"))
    }

    // MARK: - Change tracking

    @Test("A blend change is a metadata change, render-only")
    func diffIsMetadata() throws {
        let card = try node("Card")
        var blended = card
        blended.blendMode = .multiply
        #expect(PropertyDiff.diffCommon(old: card.common, new: blended.common) == ["common.metadata"])
        #expect(PropertyDiff.diffKind(old: card.kind, new: blended.kind).isEmpty)
        #expect(ChangeCategory.categorize(oldCommon: card.common, newCommon: blended.common) == .renderOnly)
    }
}
