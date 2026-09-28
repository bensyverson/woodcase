//
//  ContentHashTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct ContentHashTests {
    // MARK: - Helpers

    private func makeDocument() -> EditableDocument {
        let doc = PenDocument(
            version: "1",
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
                        ]
                    ))
                ),
            ]
        )
        return EditableDocument(from: doc)
    }

    @Test("Hash is stable when nothing changes")
    func hashStable() {
        let editable = makeDocument()
        _ = editable.computeLayout()

        let hash1 = editable.contentHash(for: "rect1")
        let hash2 = editable.contentHash(for: "rect1")
        #expect(hash1 == hash2)
    }

    @Test("Hash changes when node property changes")
    func hashChangesOnPropertyChange() throws {
        let editable = makeDocument()
        _ = editable.computeLayout()

        let hashBefore = editable.contentHash(for: "rect1")

        try editable.apply(.updateKind(EditOperation.UpdateKind(
            nodeID: "rect1",
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(50), height: .fixed(50),
                fills: .single(.shorthand("green"))
            ))
        )))
        _ = editable.computeLayout()

        let hashAfter = editable.contentHash(for: "rect1")
        #expect(hashBefore != hashAfter)
    }

    @Test("Child change propagates to parent hash")
    func childChangePropagatesToParent() throws {
        let editable = makeDocument()
        _ = editable.computeLayout()

        let parentHashBefore = editable.contentHash(for: "frame1")

        try editable.apply(.updateKind(EditOperation.UpdateKind(
            nodeID: "rect1",
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(80), height: .fixed(50),
                fills: .single(.shorthand("blue"))
            ))
        )))
        _ = editable.computeLayout()

        let parentHashAfter = editable.contentHash(for: "frame1")
        #expect(parentHashBefore != parentHashAfter)
    }

    @Test("Hash for non-existent node returns nil")
    func hashForMissingNodeReturnsNil() {
        let editable = makeDocument()
        _ = editable.computeLayout()
        #expect(editable.contentHash(for: "nonexistent") == nil)
    }
}
