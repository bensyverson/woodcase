//
//  RevisionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct RevisionTests {
    // MARK: - Helpers

    /// A frame with two rectangle children, for sibling-independence and reorder tests.
    private func makeDocument() -> EditableDocument {
        let doc = PenDocument(
            version: "2.17",
            children: [
                PenNode(
                    id: "frame1",
                    common: PenNodeCommon(),
                    kind: .frame(PenNode.FrameData(
                        width: .fixed(200), height: .fixed(100),
                        fills: .single(.shorthand("red")),
                        children: [
                            PenNode(
                                id: "rect1",
                                common: PenNodeCommon(),
                                kind: .rectangle(PenNode.RectangleData(
                                    width: .fixed(50), height: .fixed(50),
                                    fills: .single(.shorthand("blue"))
                                ))
                            ),
                            PenNode(
                                id: "rect2",
                                common: PenNodeCommon(),
                                kind: .rectangle(PenNode.RectangleData(
                                    width: .fixed(30), height: .fixed(30),
                                    fills: .single(.shorthand("green"))
                                ))
                            ),
                        ]
                    ))
                ),
            ]
        )
        return EditableDocument(from: doc)
    }

    // MARK: - FNV-1a vectors

    @Test("FNV-1a 64 of the empty string is the offset basis")
    func fnv1aEmptyString() {
        var hasher = FNV1aHasher()
        hasher.combine([UInt8]())
        #expect(hasher.finalize() == 0xCBF2_9CE4_8422_2325)
        #expect(hasher.hexString == "cbf29ce484222325")
    }

    @Test("FNV-1a 64 of 'a' matches the published test vector")
    func fnv1aSingleByte() {
        var hasher = FNV1aHasher()
        hasher.combine("a")
        #expect(hasher.finalize() == 0xAF63_DC4C_8601_EC8C)
        #expect(hasher.hexString == "af63dc4c8601ec8c")
    }

    // MARK: - Format

    @Test("Node revision is 16 lowercase hex characters")
    func revisionIsHexFormatted() throws {
        let editable = makeDocument()
        let revision = try #require(editable.revision(of: "rect1"))
        #expect(revision.count == 16)
        #expect(revision.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("Revision for a non-existent node is nil")
    func revisionForMissingNodeIsNil() {
        let editable = makeDocument()
        #expect(editable.revision(of: "nonexistent") == nil)
    }

    // MARK: - Propagation

    @Test("Editing a child changes ancestor revisions and not the sibling's")
    func editingChildChangesAncestorsNotSiblings() throws {
        let editable = makeDocument()
        let frameBefore = try #require(editable.revision(of: "frame1"))
        let rect1Before = try #require(editable.revision(of: "rect1"))
        let rect2Before = try #require(editable.revision(of: "rect2"))

        try editable.apply(.updateKind(EditOperation.UpdateKind(
            nodeID: "rect1",
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(999), height: .fixed(50),
                fills: .single(.shorthand("blue"))
            ))
        )))

        let frameAfter = try #require(editable.revision(of: "frame1"))
        let rect1After = try #require(editable.revision(of: "rect1"))
        let rect2After = try #require(editable.revision(of: "rect2"))

        #expect(rect1After != rect1Before)
        #expect(frameAfter != frameBefore)
        #expect(rect2After == rect2Before)
    }

    @Test("Reordering children changes the parent's revision")
    func reorderingChildrenChangesParentRevision() throws {
        let editable = makeDocument()
        let frameBefore = try #require(editable.revision(of: "frame1"))
        let rect1Before = try #require(editable.revision(of: "rect1"))
        let rect2Before = try #require(editable.revision(of: "rect2"))

        try editable.apply(.moveNode(EditOperation.MoveNode(
            nodeID: "rect2", newParentID: "frame1", index: 0
        )))

        let frameAfter = try #require(editable.revision(of: "frame1"))
        #expect(frameAfter != frameBefore)
        // The children's own content didn't change, only their order.
        #expect(editable.revision(of: "rect1") == rect1Before)
        #expect(editable.revision(of: "rect2") == rect2Before)
    }

    // MARK: - Document revision

    @Test("Document revision changes when a variable changes")
    func documentRevisionChangesOnVariableChange() throws {
        let editable = makeDocument()
        let before = editable.documentRevision

        try editable.apply(.addVariable(EditOperation.AddVariable(
            name: "spacing",
            variable: PenVariable(type: .number, value: .simple(.int(16)))
        )))

        #expect(editable.documentRevision != before)
    }

    @Test("Document revision is stable when nothing changes")
    func documentRevisionStableWhenUnchanged() {
        let editable = makeDocument()
        #expect(editable.documentRevision == editable.documentRevision)
    }

    // MARK: - apply(_:expecting:)

    @Test("A matching expected revision applies normally")
    func applyWithMatchingRevisionSucceeds() throws {
        let editable = makeDocument()
        let expected = try #require(editable.revision(of: "rect1"))

        try editable.apply(
            .updateKind(EditOperation.UpdateKind(
                nodeID: "rect1",
                kind: .rectangle(PenNode.RectangleData(
                    width: .fixed(75), height: .fixed(50),
                    fills: .single(.shorthand("blue"))
                ))
            )),
            expecting: ["rect1": expected]
        )

        if case let .rectangle(data) = editable.node(id: "rect1")?.kind {
            #expect(data.width == .fixed(75))
        } else {
            Issue.record("Expected rectangle kind")
        }
    }

    @Test("A stale expected revision fails with a conflict naming the node, leaving the document unchanged")
    func applyWithStaleRevisionThrowsConflict() throws {
        let editable = makeDocument()
        let actual = try #require(editable.revision(of: "rect1"))
        let stale = "0000000000000000"

        #expect(throws: EditingError.revisionConflict(nodeID: "rect1", expected: stale, actual: actual)) {
            try editable.apply(
                .updateKind(EditOperation.UpdateKind(
                    nodeID: "rect1",
                    kind: .rectangle(PenNode.RectangleData(width: .fixed(999)))
                )),
                expecting: ["rect1": stale]
            )
        }

        // Unchanged: same revision, and the width edit did not apply.
        #expect(editable.revision(of: "rect1") == actual)
        if case let .rectangle(data) = editable.node(id: "rect1")?.kind {
            #expect(data.width == .fixed(50))
        } else {
            Issue.record("Expected rectangle kind")
        }
    }

    @Test("Expecting a revision for a node absent from the document throws nodeNotFound")
    func applyWithMissingNodeThrowsNodeNotFound() throws {
        let editable = makeDocument()

        #expect(throws: EditingError.nodeNotFound(id: "missing")) {
            try editable.apply(
                .updateKind(EditOperation.UpdateKind(
                    nodeID: "rect1",
                    kind: .rectangle(PenNode.RectangleData(width: .fixed(999)))
                )),
                expecting: ["missing": "0000000000000000"]
            )
        }

        if case let .rectangle(data) = editable.node(id: "rect1")?.kind {
            #expect(data.width == .fixed(50))
        } else {
            Issue.record("Expected rectangle kind")
        }
    }

    // MARK: - applyLocal(_:expecting:)

    @Test("applyLocal with a matching expected revision applies normally")
    func applyLocalWithMatchingRevisionSucceeds() throws {
        let editable = makeDocument()
        let expected = try #require(editable.revision(of: "rect1"))

        let ops = try editable.applyLocal(
            .updateKind(EditOperation.UpdateKind(
                nodeID: "rect1",
                kind: .rectangle(PenNode.RectangleData(width: .fixed(88)))
            )),
            expecting: ["rect1": expected]
        )
        #expect(ops.isEmpty) // Not in CRDT mode.

        if case let .rectangle(data) = editable.node(id: "rect1")?.kind {
            #expect(data.width == .fixed(88))
        } else {
            Issue.record("Expected rectangle kind")
        }
    }

    @Test("applyLocal with a stale expected revision fails with a conflict, leaving the document unchanged")
    func applyLocalWithStaleRevisionThrowsConflict() throws {
        let editable = makeDocument()
        let actual = try #require(editable.revision(of: "rect1"))
        let stale = "1111111111111111"

        #expect(throws: EditingError.revisionConflict(nodeID: "rect1", expected: stale, actual: actual)) {
            try editable.applyLocal(
                .updateKind(EditOperation.UpdateKind(
                    nodeID: "rect1",
                    kind: .rectangle(PenNode.RectangleData(width: .fixed(999)))
                )),
                expecting: ["rect1": stale]
            )
        }

        #expect(editable.revision(of: "rect1") == actual)
    }

    // MARK: - Stability across encode/decode

    @Test("Revisions are stable across encode and decode of the same file")
    func revisionsStableAcrossEncodeDecode() throws {
        let url = try #require(
            Bundle.module.url(forResource: "parser-variables", withExtension: "pen", subdirectory: "Fixtures")
        )
        let data = try Data(contentsOf: url)
        let original = try PenParser.parse(data)
        let editable1 = EditableDocument(from: original)

        let materialized = editable1.materialize()
        let reencoded = try JSONEncoder().encode(materialized)
        let reparsed = try PenParser.parse(reencoded)
        let editable2 = EditableDocument(from: reparsed)

        #expect(editable1.documentRevision == editable2.documentRevision)
        #expect(editable1.revision(of: "text1") == editable2.revision(of: "text1"))
    }
}
