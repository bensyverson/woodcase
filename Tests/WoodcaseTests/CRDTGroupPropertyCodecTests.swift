//
//  CRDTGroupPropertyCodecTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-08-29.
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct CRDTGroupPropertyCodecTests {
    private let peer = PeerID(rawValue: "aaa")

    private func makeCRDT() -> CRDTDocument {
        let group = PenNode(id: "g1", common: PenNodeCommon(), kind: .group(PenNode.GroupData()))
        let doc = EditableDocument(from: PenDocument(children: [group]))
        return CRDTDocument(peerID: peer, document: doc)
    }

    // MARK: - Remaining properties round-trip

    /// A group's blend mode is stored in its metadata (leaf TesTbK): a remote write of
    /// `kind.blendMode` applies to the node, and the group's kind no longer holds it.
    @Test("Group blendMode applies to the node, in its metadata")
    func groupBlendModeApplies() {
        let group = PenNode(id: "g1", common: PenNodeCommon(), kind: .group(PenNode.GroupData()))
        let document = EditableDocument(from: PenDocument(children: [group]))
        let crdt = CRDTDocument(peerID: peer, document: document)
        let node = crdt.applyPropertyToNode(
            nodeID: "g1", property: "kind.blendMode", value: .string("multiply"), document: document
        )
        #expect(node.blendMode == .multiply)
        #expect(node.common.metadata?[woodcase: .blendMode] == .string("multiply"))
    }

    @Test("Group blendMode is not a property of the group's kind")
    func groupBlendModeIsNotAKindProperty() {
        let crdt = makeCRDT()
        let kind = crdt.applyKindProperty(property: "kind.blendMode", value: .string("multiply"), to: .group(PenNode.GroupData()))
        #expect(kind == .group(PenNode.GroupData()))
        #expect(crdt.extractKindValue(property: "kind.blendMode", from: .group(PenNode.GroupData())) == .null)
    }

    // MARK: - Removed properties are no-ops

    @Test("A legacy layout key is ignored when applied to a group")
    func legacyLayoutKeyIsIgnored() {
        let crdt = makeCRDT()
        let original = PenNode.GroupData(effects: .single(.blur(PenEffect.PenBlurEffect(radius: .literal(4)))))
        let kind = crdt.applyKindProperty(property: "kind.layout", value: .string("vertical"), to: .group(original))
        guard case let .group(data) = kind else {
            Issue.record("Expected group kind")
            return
        }
        #expect(data == original)
    }

    @Test("Reading a legacy gap key from a group returns null")
    func legacyGapKeyReadsNull() {
        let crdt = makeCRDT()
        let value = crdt.extractKindValue(property: "kind.gap", from: .group(PenNode.GroupData()))
        #expect(value == .null)
    }
}
