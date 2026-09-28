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

    @Test("Group blendMode applies through the property codec")
    func groupBlendModeApplies() {
        let crdt = makeCRDT()
        let kind = crdt.applyKindProperty(
            property: "kind.blendMode", value: .string("multiply"), to: .group(PenNode.GroupData())
        )
        guard case let .group(data) = kind else {
            Issue.record("Expected group kind")
            return
        }
        #expect(data.blendMode == .multiply)
    }

    @Test("Group blendMode reads back through the property codec")
    func groupBlendModeReadsBack() {
        let crdt = makeCRDT()
        let value = crdt.extractKindValue(
            property: "kind.blendMode", from: .group(PenNode.GroupData(blendMode: .multiply))
        )
        #expect(value == .string("multiply"))
    }

    // MARK: - Removed properties are no-ops

    @Test("A legacy layout key is ignored when applied to a group")
    func legacyLayoutKeyIsIgnored() {
        let crdt = makeCRDT()
        let original = PenNode.GroupData(blendMode: .multiply)
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
