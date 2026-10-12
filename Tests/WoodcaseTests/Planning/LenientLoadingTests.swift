//
//  LenientLoadingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Value constraints are a write rule: a file that breaks them still opens, and an edit
/// that did not come through the planner is applied as it is.
@MainActor
struct LenientLoadingTests {
    @Test("A file holding out-of-range values parses and round-trips them")
    func opensOutOfRange() throws {
        let document = try PlannerFixture.document()
        let free = try #require(document.node(id: "Fre01"))

        #expect(try NodePropertyCodec.value(at: "common.opacity", of: free) == 7)
        #expect(document.materialize().children.first?.kind.inlineChildrenIfPresent?.first?.common.opacity?.literalValue
            == 7)
    }

    @Test("An operation applied without planning — a merge's, an undo's — is never refused")
    func operationsAreNotChecked() throws {
        let document = try PlannerFixture.document()
        let session = DocumentSession(editing: document, author: .unattributed(peer: PeerID.generate()), file: nil)

        try session.submit(.local(LocalEdit(operations: [
            .setProperties(EditOperation.SetProperties(
                nodeID: "Flo01", properties: ["common.opacity": 7, "common.x": 40, "kind.fills": "$nope"]
            )),
        ])))

        #expect(try NodePropertyCodec.value(at: "common.opacity", of: #require(document.node(id: "Flo01"))) == 7)
    }

    @Test("A three-way merge carrying an out-of-range value applies")
    func mergeIsNotChecked() throws {
        let base = try PlannerFixture.document()
        let theirs = try PlannerFixture.document()
        try theirs.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Flo01", properties: ["common.opacity": 9]
        )))
        let ours = try PlannerFixture.document()
        let result = DocumentMerge.merge(base: base, ours: ours, theirs: theirs)

        for operation in result.operations {
            try ours.apply(operation)
        }
        #expect(try NodePropertyCodec.value(at: "common.opacity", of: #require(ours.node(id: "Flo01"))) == 9)
    }
}
