//
//  CRDTRootOverrideNaturalKeyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A raw ``EditOperation/OverrideRoot`` naming a Woodcase-owned key is stored on the ref
/// node's own `metadata.woodcase` (rule 6), so the operations it replicates must carry that
/// metadata write, not only `kind.rootOverrides` (leaf QqB9Zj).
@MainActor
struct CRDTRootOverrideNaturalKeyTests {
    private typealias Fixture = NaturalPathFixture

    /// Two replicas of the natural-paths fixture.
    private func replicas() throws -> (EditableDocument, EditableDocument) {
        let document = try Fixture.document().materialize()
        return (
            EditableDocument(from: document, peerID: PeerID(rawValue: "peerA")),
            EditableDocument(from: document, peerID: PeerID(rawValue: "peerB"))
        )
    }

    /// Applies a raw root override to one replica and sends its operations to the other.
    @discardableResult
    private func overrideRoot(
        _ properties: [String: AnyCodable], unset: [String] = [],
        on peerA: EditableDocument, to peerB: EditableDocument
    ) throws -> [CRDTOperation] {
        let ops = try peerA.applyLocal(.overrideRoot(EditOperation.OverrideRoot(
            refNodeID: "Ins01", properties: properties, unset: unset
        )))
        peerB.applyRemote(ops)
        return ops
    }

    @Test("A raw root override of kind.strokeDash on one replica shows on the other")
    func strokeDashReplicates() throws {
        let (peerA, peerB) = try replicas()
        try overrideRoot(["kind.strokeDash": [6, 3]], on: peerA, to: peerB)

        let ref = try #require(peerB.node(id: "Ins01"))
        #expect(ref.common.metadata?[woodcase: .strokeDash] == [6, 3])
        #expect(Fixture.expanded("Ins01/Bdg01", in: peerB)?.strokeDash?.lengths == [6, 3])
        #expect(peerB.node(id: "Ins01") == peerA.node(id: "Ins01"))
    }

    @Test("A raw root override of common.locked replicates as the ref's own metadata")
    func lockedReplicates() throws {
        let (peerA, peerB) = try replicas()
        try overrideRoot(["common.locked": true], on: peerA, to: peerB)

        #expect(peerB.node(id: "Ins01")?.common.metadata?[woodcase: .locked] == true)
        #expect(peerB.node(id: "Ins01") == peerA.node(id: "Ins01"))
    }

    @Test("A raw root override mixing a natural key and a plain one replicates both")
    func mixedReplicates() throws {
        let (peerA, peerB) = try replicas()
        try overrideRoot(["strokeDash": [4, 4], "width": 120], on: peerA, to: peerB)

        let ref = try #require(peerB.node(id: "Ins01"))
        #expect(ref.common.metadata?[woodcase: .strokeDash] == [4, 4])
        guard case let .ref(data) = ref.kind else { Issue.record("not a ref"); return }
        #expect(data.rootOverrides?["width"] == 120)
        #expect(data.rootOverrides?["strokeDash"] == nil)
        #expect(peerB.node(id: "Ins01") == peerA.node(id: "Ins01"))
    }

    @Test("No replicated operation stores a natural key in kind.rootOverrides")
    func noNaturalKeyInRootOverrides() throws {
        let (peerA, peerB) = try replicas()
        let ops = try overrideRoot(["kind.strokeDash": [6, 3], "width": 120], on: peerA, to: peerB)

        for op in ops {
            guard case let .setProperty(write) = op.payload, write.property == "kind.rootOverrides",
                  case let .dictionary(overrides) = write.value
            else { continue }
            #expect(overrides.keys.allSatisfy { NodePropertyCodec.naturalOverrideKey($0) == nil })
        }
    }
}
