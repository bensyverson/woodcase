//
//  MetadataMergeGranularityTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `common.metadata` merges per key — each top-level key, and each key inside
/// `metadata.woodcase` — in both the three-way merge and the CRDT, so concurrent edits
/// to one note's tint and state both survive. A value below that level (one entry of
/// `woodcase.props`) merges as part of its key. See DocC `PenMetadataNamespace`.
@MainActor
struct MetadataMergeGranularityTests {
    private typealias F = MergeFixture

    /// A note carrying the given metadata JSON.
    private func note(_ metadata: String) -> String {
        F.frame("page", #"{"type":"note","id":"n","content":"hi","metadata":\#(metadata)}"#)
    }

    // MARK: - Three-way

    @Test("Three-way: edits to different namespaced keys of one note both survive")
    func threeWayDifferentNamespacedKeys() throws {
        let result = try F.resolve(
            base: note(##"{"woodcase":{"tint":"#FFF59D","state":"open"}}"##),
            ours: note(##"{"woodcase":{"tint":"#A5D6A7","state":"open"}}"##),
            theirs: note(##"{"woodcase":{"tint":"#FFF59D","state":"resolved"}}"##)
        )

        let merged = try #require(result.nodes["n"]?.node.common.metadata)
        #expect(merged[woodcase: .tint] == .string("#A5D6A7"))
        #expect(merged[woodcase: .state] == .string("resolved"))
        #expect(result.conflicts.isEmpty)
    }

    @Test("Three-way: one namespaced key both changed keeps ours and reports that key")
    func threeWaySameNamespacedKey() throws {
        let result = try F.resolve(
            base: note(#"{"woodcase":{"state":"open","author":"ana"}}"#),
            ours: note(#"{"woodcase":{"state":"resolved","author":"ana"}}"#),
            theirs: note(#"{"woodcase":{"state":"open","author":"claude"}}"#)
        )

        let merged = try #require(result.nodes["n"]?.node.common.metadata)
        #expect(merged[woodcase: .author] == .string("claude"))
        #expect(merged[woodcase: .state] == .string("resolved"))
        #expect(result.conflicts.isEmpty)

        let clash = try F.resolve(
            base: note(#"{"woodcase":{"state":"open"}}"#),
            ours: note(#"{"woodcase":{"state":"resolved"}}"#),
            theirs: note(#"{"woodcase":{"state":"closed"}}"#)
        )
        #expect(clash.nodes.isEmpty)
        #expect(clash.conflicts == [MergeConflict(
            subject: .property(nodeID: "n", path: "common.metadata.woodcase.state"), kind: .bothChanged,
            base: .string("open"), ours: .string("resolved"), theirs: .string("closed")
        )])
    }

    @Test("Three-way: top-level metadata keys merge per key, and a namespace one side adds is taken")
    func threeWayTopLevelKeys() throws {
        let result = try F.resolve(
            base: note(#"{"type":"scratch"}"#),
            ours: note(#"{"type":"scratch","mine":1}"#),
            theirs: note(##"{"type":"board","woodcase":{"tint":"#FFFFFF"}}"##)
        )

        let merged = try #require(result.nodes["n"]?.node.common.metadata)
        #expect(merged.type == "board")
        #expect(merged.extensions["mine"] == .int(1))
        #expect(merged[woodcase: .tint] == .string("#FFFFFF"))
        #expect(result.conflicts.isEmpty)
    }

    @Test("Three-way: a namespaced value merges whole, below the per-key level")
    func threeWayNestedValueIsWhole() throws {
        let result = try F.resolve(
            base: note(#"{"woodcase":{"props":{"a":"A"}}}"#),
            ours: note(#"{"woodcase":{"props":{"a":"A2"}}}"#),
            theirs: note(#"{"woodcase":{"props":{"a":"A","b":"B"}}}"#)
        )

        #expect(result.conflicts.map(\.subject) == [.property(nodeID: "n", path: "common.metadata.woodcase.props")])
    }

    @Test("Three-way: metadata the merge leaves with entries but no type takes type woodcase")
    func threeWayTypelessResultIsTyped() throws {
        let result = try F.resolve(
            base: note(#"{"type":"scratch","a":1}"#),
            ours: note(#"{"type":"scratch","a":2}"#),
            theirs: note(#"{"a":1}"#)
        )

        let merged = try #require(result.nodes["n"]?.node.common.metadata)
        #expect(merged.type == "woodcase")
        #expect(merged.extensions["a"] == .int(2))
    }

    @Test("Three-way: metadata the merge empties is removed, not left typeless")
    func threeWayEmptiedMetadataIsRemoved() throws {
        let result = try F.resolve(
            base: note(#"{"type":"scratch","a":1}"#),
            ours: note(#"{"type":"scratch"}"#),
            theirs: note(#"{"a":1}"#)
        )

        let merged = try #require(result.nodes["n"]?.node)
        #expect(merged.common.metadata == nil)
    }

    // MARK: - CRDT

    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    private func makePair() throws -> (EditableDocument, EditableDocument) {
        let doc = try PenParser.parse(#"""
        {"version":"2.20","children":[{"type":"note","id":"n","content":"hi",
          "metadata":{"type":"scratch","woodcase":{"tint":"#FFF59D","state":"open"}}}]}
        """#)
        return (EditableDocument(from: doc, peerID: peerA), EditableDocument(from: doc, peerID: peerB))
    }

    /// A `set` of the note's whole metadata, as a deep-key write folds to.
    private func setMetadata(_ metadata: AnyCodable) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: "n", properties: ["common.metadata": metadata]))
    }

    private func metadata(type: String = "scratch", _ woodcase: [String: AnyCodable]) -> AnyCodable {
        .dictionary(["type": .string(type), "woodcase": .dictionary(woodcase)])
    }

    @Test("CRDT: a metadata write replicates one write per changed namespaced key")
    func crdtEmitsPerKey() throws {
        let (a, _) = try makePair()

        let ops = try a.applyLocal(setMetadata(metadata(["tint": .string("#A5D6A7"), "state": .string("open")])))

        let paths = ops.compactMap { op -> String? in
            if case let .setProperty(p) = op.payload { return p.property }
            return nil
        }
        #expect(paths == ["common.metadata.woodcase.tint"])
    }

    @Test("CRDT: concurrent edits to one note's tint and state both survive")
    func crdtDifferentNamespacedKeysSurvive() throws {
        let (a, b) = try makePair()

        let opsA = try a.applyLocal(setMetadata(metadata(["tint": .string("#A5D6A7"), "state": .string("open")])))
        let opsB = try b.applyLocal(setMetadata(metadata(["tint": .string("#FFF59D"), "state": .string("resolved")])))
        b.applyRemote(opsA)
        a.applyRemote(opsB)

        #expect(a.nodes["n"] == b.nodes["n"])
        let merged = try #require(a.nodes["n"]?.common.metadata)
        #expect(merged[woodcase: .tint] == .string("#A5D6A7"))
        #expect(merged[woodcase: .state] == .string("resolved"))
        #expect(merged.type == "scratch")
    }

    @Test("CRDT: concurrent edits to one namespaced key converge on one winner")
    func crdtSameKeyConverges() throws {
        let (a, b) = try makePair()

        let opsA = try a.applyLocal(setMetadata(metadata(["tint": .string("#A5D6A7"), "state": .string("open")])))
        let opsB = try b.applyLocal(setMetadata(metadata(["tint": .string("#000000"), "state": .string("open")])))
        b.applyRemote(opsA)
        a.applyRemote(opsB)

        #expect(a.nodes["n"] == b.nodes["n"])
    }

    @Test("CRDT: a removed key and a top-level change replicate and converge")
    func crdtRemovalAndTopLevel() throws {
        let (a, b) = try makePair()

        let ops = try a.applyLocal(setMetadata(metadata(type: "board", ["state": .string("open")])))
        b.applyRemote(ops)

        #expect(a.nodes["n"] == b.nodes["n"])
        let merged = try #require(b.nodes["n"]?.common.metadata)
        #expect(merged.type == "board")
        #expect(merged[woodcase: .tint] == nil)
        #expect(merged[woodcase: .state] == .string("open"))
    }

    @Test("CRDT: clearing the whole metadata object converges")
    func crdtClearConverges() throws {
        let (a, b) = try makePair()

        let ops = try a.applyLocal(setMetadata(.null))
        b.applyRemote(ops)

        #expect(b.nodes["n"]?.common.metadata == nil)
        #expect(a.nodes["n"] == b.nodes["n"])
    }

    @Test("CRDT: an authored write's type replicates as its own entry, and the peers converge")
    func crdtAuthoredTypeReplicates() throws {
        let doc = try PenParser.parse(#"{"version":"2.20","children":[{"type":"note","id":"n","content":"hi"}]}"#)
        let a = EditableDocument(from: doc, peerID: peerA)
        let b = EditableDocument(from: doc, peerID: peerB)
        let target = try #require(NodeAddress("#n"))
        let set = BatchOperation.set(BatchOperation.SetOp(target: target, props: [
            "common.metadata.woodcase.state": .string("open"),
        ]))

        let plan = try BatchApplier.plan(set, in: a, tags: [:])
        let ops = try plan.operations.flatMap { try a.applyLocal($0) }
        b.applyRemote(ops)

        let paths = ops.compactMap { op -> String? in
            if case let .setProperty(p) = op.payload { return p.property }
            return nil
        }
        #expect(paths.contains("common.metadata.type"))
        #expect(a.nodes["n"] == b.nodes["n"])
        #expect(b.nodes["n"]?.common.metadata?.type == "woodcase")
    }

    @Test("CRDT: an updateCommon that changes metadata replicates per key too")
    func crdtUpdateCommonPerKey() throws {
        let (a, b) = try makePair()
        var commonA = try #require(a.nodes["n"]?.common)
        commonA.metadata?[woodcase: .tint] = .string("#A5D6A7")
        var commonB = try #require(b.nodes["n"]?.common)
        commonB.metadata?[woodcase: .state] = .string("resolved")

        let opsA = try a.applyLocal(.updateCommon(EditOperation.UpdateCommon(nodeID: "n", common: commonA)))
        let opsB = try b.applyLocal(.updateCommon(EditOperation.UpdateCommon(nodeID: "n", common: commonB)))
        b.applyRemote(opsA)
        a.applyRemote(opsB)

        #expect(a.nodes["n"] == b.nodes["n"])
        let merged = try #require(a.nodes["n"]?.common.metadata)
        #expect(merged[woodcase: .tint] == .string("#A5D6A7"))
        #expect(merged[woodcase: .state] == .string("resolved"))
    }
}
