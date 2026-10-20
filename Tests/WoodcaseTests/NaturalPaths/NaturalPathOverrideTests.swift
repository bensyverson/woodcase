//
//  NaturalPathOverrideTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Rule 6: an instance override of a Woodcase-owned key is stored in the override's own
/// `metadata.woodcase` and merged key by key over the component node's on expansion; the
/// instance root takes the `ref` node's own `metadata.woodcase` merged key by key over the
/// component root's (Ben's ruling, 2026-10-20). Pen drops both (pen CLI, leaf 9Sw8C0), which
/// Ben accepts: transfers run one way, Pen to Penumbra.
@MainActor
struct NaturalPathOverrideTests {
    private typealias Fixture = NaturalPathFixture

    private func override(
        _ properties: [String: AnyCodable], unset: [String] = [], at target: ResolvedNodeAddress,
        in document: EditableDocument
    ) throws {
        try Fixture.apply(EditPlanner.plan(.override(properties, unset: unset), at: target, in: document), to: document)
    }

    private static let box = ResolvedNodeAddress.instanceDescendant(refID: "Ins01", descendantKey: "Box01")

    /// The `descendants` entry the instance stores for the box.
    private func boxOverride(in document: EditableDocument) -> [String: AnyCodable]? {
        guard case let .ref(data)? = document.node(id: "Ins01")?.kind else { return nil }
        return data.descendants?["Box01"]?.properties
    }

    /// The `woodcase` object of an override's metadata.
    private func woodcase(_ properties: [String: AnyCodable]?) -> [String: AnyCodable]? {
        guard case let .dictionary(metadata)? = properties?["metadata"],
              case let .dictionary(keys)? = metadata[PenMetadata.woodcaseNamespace]
        else { return nil }
        return keys
    }

    // MARK: - Descendants

    @Test("A descendant override of kind.strokeDash is stored in the override's own metadata.woodcase")
    func storedInOverrideMetadata() throws {
        let document = try Fixture.document()
        try override(["kind.strokeDash": [4, 2]], at: Self.box, in: document)
        let stored = boxOverride(in: document)
        #expect(stored?["strokeDash"] == nil)
        #expect(woodcase(stored)?["strokeDash"] == [4, 2])
    }

    @Test("The override merges per key: the component node's other metadata keys reach the instance")
    func mergesPerKey() throws {
        let document = try Fixture.document()
        try override(["kind.strokeDash": [4, 2]], at: Self.box, in: document)
        let box = try #require(Fixture.expanded("Ins01/Box01", in: document))
        #expect(box.strokeDash?.lengths == [4, 2])
        #expect(box.strokeMiterLimit == 6)
        #expect(box.common.metadata?.extensions["note"] == .string("keep me"))
        #expect(document.node(id: "Box01")?.strokeDash?.lengths == [1, 1])
    }

    @Test("A second override keeps the first in the override's metadata")
    func secondOverrideKeepsFirst() throws {
        let document = try Fixture.document()
        try override(["kind.strokeDash": [4, 2]], at: Self.box, in: document)
        try override(["blendMode": "screen"], at: Self.box, in: document)
        let keys = woodcase(boxOverride(in: document))
        #expect(keys?["strokeDash"] == [4, 2])
        #expect(keys?["blendMode"] == "screen")
    }

    @Test("A later edit to the component's other metadata keys still reaches an overridden instance")
    func componentEditsFlowThrough() throws {
        let document = try Fixture.document()
        try override(["kind.strokeDash": [4, 2]], at: Self.box, in: document)
        try Fixture.apply(
            EditPlanner.plan(.set(["kind.strokeMiterLimit": 9]), routedAt: .node(id: "Box01"), in: document), to: document
        )
        let box = try #require(Fixture.expanded("Ins01/Box01", in: document))
        #expect(box.strokeMiterLimit == 9)
        #expect(box.strokeDash?.lengths == [4, 2])
    }

    @Test("An override of null clears the key on the instance only")
    func nullClears() throws {
        let document = try Fixture.document()
        try override(["kind.strokeDash": .null], at: Self.box, in: document)
        let box = try #require(Fixture.expanded("Ins01/Box01", in: document))
        #expect(box.strokeDash == nil)
        #expect(box.strokeMiterLimit == 6)
    }

    @Test("Unsetting a natural path removes it from the override's metadata")
    func unsetRemoves() throws {
        let document = try Fixture.document()
        try override(["kind.strokeDash": [4, 2]], at: Self.box, in: document)
        try override([:], unset: ["kind.strokeDash"], at: Self.box, in: document)
        #expect(boxOverride(in: document) == nil)
        #expect(Fixture.expanded("Ins01/Box01", in: document)?.strokeDash?.lengths == [1, 1])
    }

    @Test("A raw override operation of a natural key is stored the same way")
    func rawOperationStoresMetadata() throws {
        let document = try Fixture.document()
        try document.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "Ins01", descendantID: "Box01", properties: ["strokeDash": [5, 5]]
        )))
        let stored = boxOverride(in: document)
        #expect(stored?["strokeDash"] == nil)
        #expect(woodcase(stored)?["strokeDash"] == [5, 5])
    }

    @Test("A locked override reaches the instance's node")
    func lockedOverride() throws {
        let document = try Fixture.document()
        try override(["common.locked": true], at: Self.box, in: document)
        #expect(Fixture.expanded("Ins01/Box01", in: document)?.isLocked == true)
        #expect(document.node(id: "Box01")?.isLocked == false)
        #expect(woodcase(boxOverride(in: document))?["locked"] == true)
    }

    @Test("An override of kind.blendMode round-trips through save and load in the override's metadata")
    func blendOverrideRoundTrips() throws {
        let document = try Fixture.document()
        try override(["kind.blendMode": "screen"], at: Self.box, in: document)
        let reread = try EditableDocument(from: PenParser.parse(PenParser.encode(document.materialize())))
        #expect(woodcase(boxOverride(in: reread))?["blendMode"] == "screen")
        let box = try #require(Fixture.expanded("Ins01/Box01", in: reread))
        #expect(box.blendMode == .screen)
        #expect(box.strokeDash?.lengths == [1, 1])
    }

    // MARK: - The instance root

    @Test("A root override of a natural path is stored in the ref node's own metadata.woodcase")
    func rootStoredOnRef() throws {
        let document = try Fixture.document()
        try override(["kind.strokeDash": [6, 3]], at: .node(id: "Ins01"), in: document)
        let ref = try #require(document.node(id: "Ins01"))
        #expect(ref.common.metadata?[woodcase: .strokeDash] == [6, 3])
        guard case let .ref(data) = ref.kind else { Issue.record("not a ref"); return }
        #expect(data.rootOverrides?["strokeDash"] == nil)
    }

    @Test("The instance root takes the ref's metadata.woodcase per key over the component root's")
    func rootMergesPerKey() throws {
        let document = try Fixture.document()
        try override(["kind.strokeDash": [6, 3]], at: .node(id: "Ins01"), in: document)
        let root = try #require(Fixture.expanded("Ins01/Bdg01", in: document))
        #expect(root.strokeDash?.lengths == [6, 3])
        #expect(root.common.metadata?[woodcase: .role] == .string("badge"))
        #expect(root.common.metadata?.type == "component")
        #expect(document.node(id: "Bdg01")?.strokeDash?.lengths == [2, 2])
    }

    @Test("Locking an instance locks its root, and the component stays unlocked")
    func instanceLock() throws {
        let document = try Fixture.document()
        try Fixture.apply(
            EditPlanner.plan(.set(["common.locked": true]), routedAt: .node(id: "Ins01"), in: document), to: document
        )
        #expect(document.node(id: "Ins01")?.isLocked == true)
        #expect(Fixture.expanded("Ins01/Bdg01", in: document)?.isLocked == true)
        #expect(document.node(id: "Bdg01")?.isLocked == false)
    }

    // MARK: - Inspecting

    @Test("An inspection lists a natural override at its natural path, with its value")
    func inspectionListsNaturalOverride() throws {
        let document = try Fixture.document()
        try override(["kind.strokeDash": [4, 2]], at: Self.box, in: document)
        let inspection = try #require(document.inspect(Self.box))
        #expect(inspection.isOverridden("kind.strokeDash"))
        #expect(inspection.overrides.first { $0.path == "kind.strokeDash" }?.value == [4, 2])
        #expect(!inspection.isOverridden("kind.strokeMiterLimit"))
    }

    @Test("An instance root's inspection lists the ref's own natural keys as its overrides")
    func rootInspectionListsRefKeys() throws {
        let document = try Fixture.document()
        try override(["kind.strokeDash": [6, 3]], at: .node(id: "Ins01"), in: document)
        let inspection = try #require(document.inspect(.node(id: "Ins01")))
        #expect(inspection.isOverridden("kind.strokeDash"))
        #expect(inspection.overrides.first { $0.path == "kind.strokeDash" }?.value == [6, 3])
    }

    // MARK: - Old files

    @Test("A raw natural key in a descendants override is read into the override's metadata.woodcase")
    func rawDescendantKeyMigrates() throws {
        let json = """
        {"version": "2.20", "children": [
          {"type": "frame", "id": "C", "reusable": true, "width": 10, "height": 10, "children": [
            {"type": "rectangle", "id": "B", "width": 5, "height": 5,
             "metadata": {"type": "woodcase", "note": "keep", "woodcase": {"strokeDash": [1, 1]}}}
          ]},
          {"type": "ref", "id": "I", "ref": "C", "blendMode": "multiply",
           "descendants": {"B": {"blendMode": "screen", "fill": "#FF0000"}}}
        ]}
        """
        let document = try EditableDocument(from: PenParser.parse(json))
        guard case let .ref(data)? = document.node(id: "I")?.kind else { Issue.record("not a ref"); return }
        let entry = data.descendants?["B"]?.properties
        #expect(entry?["blendMode"] == nil)
        #expect(entry?["fill"] == "#FF0000")
        #expect(woodcase(entry)?["blendMode"] == "screen")
        // A root override written raw moves onto the ref's own metadata.
        #expect(data.rootOverrides?["blendMode"] == nil)
        #expect(document.node(id: "I")?.common.metadata?[woodcase: .blendMode] == "multiply")
        let box = try #require(Fixture.expanded("I/B", in: document))
        #expect(box.blendMode == .screen)
        #expect(box.strokeDash?.lengths == [1, 1])
        #expect(box.common.metadata?.extensions["note"] == .string("keep"))
        #expect(Fixture.expanded("I/C", in: document)?.blendMode == .multiply)
    }
}
