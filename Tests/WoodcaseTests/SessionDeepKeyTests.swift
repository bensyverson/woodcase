//
//  SessionDeepKeyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A session edit takes deep metadata keys — `common.metadata.woodcase.spans` — and
/// folds them onto the node's metadata exactly as the CLI's batch planner does
/// (``NodePropertyCodec/folding(_:onto:)``), so an editor writes one entry without
/// rewriting the object. Its keys, its inverse and its undo are per entry.
struct SessionDeepKeyTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))

    /// The spans a text's deep-key write stores.
    static let spans: AnyCodable = .dictionary([
        "text": "hi",
        "runs": .array([.dictionary(["start": 0, "end": 2, "fontWeight": "700"])]),
    ])

    /// A session over the shared test document, `c2` (a text) and `c1` carrying the
    /// given metadata objects.
    static func session(
        author: Author,
        c1: [String: AnyCodable]? = nil,
        c2: [String: AnyCodable]? = nil,
        file: URL? = nil,
        collaborative: Bool = false
    ) throws -> DocumentSession {
        let document = SessionTestDocuments.make()
        for (id, metadata) in [("c1", c1), ("c2", c2)] {
            guard let metadata else { continue }
            try document.apply(.setProperties(EditOperation.SetProperties(
                nodeID: id, properties: ["common.metadata": .dictionary(metadata)]
            )))
        }
        return DocumentSession(document: document.materialize(), author: author, file: file, collaborative: collaborative)
    }

    private func set(_ nodeID: String, _ properties: [String: AnyCodable]) -> SessionOrigin {
        .local(LocalEdit(operations: [.setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: properties))]))
    }

    private func metadata(_ nodeID: String, in session: DocumentSession) -> [String: AnyCodable]? {
        session.document.nodes[nodeID]?.common.metadata?.object
    }

    // MARK: - Writing

    @Test("a deep key writes one entry and keeps every other key of the object")
    func deepKeyMergesOneEntry() throws {
        let original: [String: AnyCodable] = ["type": "design", "owner": "ana", "woodcase": ["tint": "#FFF59D"]]
        let session = try Self.session(author: ana, c2: original)

        let change = try session.submit(set("c2", ["common.metadata.woodcase.spans": Self.spans]))

        #expect(metadata("c2", in: session) == [
            "type": "design", "owner": "ana", "woodcase": ["tint": "#FFF59D", "spans": Self.spans],
        ])
        #expect(change.applied.first?.forward == .setProperties(EditOperation.SetProperties(
            nodeID: "c2", properties: ["common.metadata": .dictionary(metadata("c2", in: session) ?? [:])]
        )))
    }

    @Test("a deep key written null removes that entry alone")
    func nullRemovesOneEntry() throws {
        let session = try Self.session(
            author: ana, c2: ["type": "design", "woodcase": ["tint": "#FFF59D", "spans": Self.spans]]
        )

        try session.submit(set("c2", ["common.metadata.woodcase.spans": .null]))

        #expect(metadata("c2", in: session) == ["type": "design", "woodcase": ["tint": "#FFF59D"]])
    }

    @Test("a key below an entry merges into it")
    func keyInsideAnEntry() throws {
        let session = try Self.session(author: ana, c1: ["type": "design", "woodcase": ["props": ["title": "Body/Title"]]])

        try session.submit(set("c1", ["common.metadata.woodcase.props.label": "Body/Label"]))

        #expect(metadata("c1", in: session) == [
            "type": "design", "woodcase": ["props": ["title": "Body/Title", "label": "Body/Label"]],
        ])
    }

    @Test("a deep key on a node with no metadata creates it, typed")
    func deepKeyCreatesMetadata() throws {
        let session = try Self.session(author: ana)

        try session.submit(set("c2", ["common.metadata.woodcase.spans": Self.spans]))

        #expect(metadata("c2", in: session) == ["type": "woodcase", "woodcase": ["spans": Self.spans]])
    }

    @Test("a deep key under a property that takes none is still refused")
    func unknownDeepKeyIsRefused() throws {
        let session = try Self.session(author: ana)

        #expect(throws: EditingError.self) {
            try session.submit(set("c2", ["common.name.first": "x"]))
        }
    }

    // MARK: - Keys and inverse

    @Test("a metadata write is keyed per entry it changes, the keys a collaborator's entry write stamps")
    func keysArePerEntry() throws {
        let session = try Self.session(author: ana, c2: ["type": "design", "woodcase": ["tint": "#FFF59D"]])

        let change = try session.submit(set("c2", ["common.metadata.woodcase.spans": Self.spans]))

        let keys = Set(session.ledger.stamps.keys)
        #expect(keys == [.property(node: "c2", path: "common.metadata.woodcase.spans")])
        #expect(change.applied.first?.inverse.map(\.keys) == [[.property(node: "c2", path: "common.metadata.woodcase.spans")]])
    }

    @Test("a whole-object metadata write is keyed per entry too")
    func wholeObjectWriteKeysPerEntry() throws {
        let document = SessionTestDocuments.make()
        let operation = EditOperation.setProperties(EditOperation.SetProperties(
            nodeID: "c2", properties: ["common.metadata": ["type": "design", "owner": "ana"], "common.name": "Two"]
        ))

        let keys = try ChangeKey.keys(of: operation, in: document)

        #expect(keys == [
            .property(node: "c2", path: "common.metadata.owner"),
            .property(node: "c2", path: "common.metadata.type"),
            .property(node: "c2", path: "common.name"),
        ])
    }

    @Test("a whole-struct common write and a replace key their metadata per entry")
    func wholeStructWritesKeyPerEntry() throws {
        let document = SessionTestDocuments.make()
        var node = try #require(document.nodes["c2"])
        node.common.metadata = PenMetadata(object: ["type": "design", "owner": "ana"])
        let expected: [ChangeKey] = [
            .property(node: "c2", path: "common.metadata.owner"),
            .property(node: "c2", path: "common.metadata.type"),
        ]

        let update = EditOperation.updateCommon(EditOperation.UpdateCommon(nodeID: "c2", common: node.common))
        let replace = EditOperation.replaceSubtree(EditOperation.ReplaceSubtree(node: node))

        #expect(try ChangeKey.keys(of: update, in: document) == expected)
        #expect(try ChangeKey.keys(of: replace, in: document) == expected)
    }

    @Test("the granular inverse of a deep-key write restores each changed entry as its own step")
    func granularInverseIsPerEntry() throws {
        let document = SessionTestDocuments.make()
        let operation = EditOperation.setProperties(EditOperation.SetProperties(
            nodeID: "c2", properties: ["common.metadata.woodcase.spans": Self.spans]
        ))

        let steps = try document.granularInverse(of: operation)

        #expect(steps.map(\.keys) == [
            [.property(node: "c2", path: "common.metadata.type")],
            [.property(node: "c2", path: "common.metadata.woodcase.spans")],
        ])
    }

    // MARK: - Undo and redo

    @Test("undo of a deep-key write restores the metadata exactly, and redo puts it back")
    func undoRestoresExactly() throws {
        let original: [String: AnyCodable] = ["type": "design", "owner": "ana", "woodcase": ["tint": "#FFF59D"]]
        let session = try Self.session(author: ana, c2: original)
        try session.submit(set("c2", ["common.metadata.woodcase.spans": Self.spans]))
        let written = metadata("c2", in: session)

        try session.submit(.undo)
        #expect(metadata("c2", in: session) == original)

        try session.submit(.redo)
        #expect(metadata("c2", in: session) == written)
    }

    @Test("undo takes a node that had no metadata back to none")
    func undoRemovesCreatedMetadata() throws {
        let session = try Self.session(author: ana)
        try session.submit(set("c2", ["common.metadata.woodcase.spans": Self.spans]))

        try session.submit(.undo)

        #expect(session.document.nodes["c2"]?.common.metadata == nil)
    }

    @Test("undo restores metadata that had no type without typing it")
    func undoKeepsUntypedMetadataUntyped() throws {
        let session = try Self.session(author: ana, c2: ["owner": "ana"])
        try session.submit(set("c2", ["common.metadata.woodcase.spans": Self.spans]))
        #expect(metadata("c2", in: session)?["type"] == "woodcase")

        try session.submit(.undo)

        #expect(metadata("c2", in: session) == ["owner": "ana"])
    }

    @Test("undo of a write that moved an old spelling into the namespace puts the old spelling back")
    func undoRestoresOldSpelling() throws {
        let original: [String: AnyCodable] = ["type": "design", "_role": "button"]
        let session = try Self.session(author: ana, c1: original)
        try session.submit(set("c1", ["common.metadata.woodcase.role": "link"]))
        #expect(metadata("c1", in: session) == ["type": "design", "woodcase": ["role": "link"]])

        try session.submit(.undo)

        #expect(metadata("c1", in: session) == original)
    }
}
