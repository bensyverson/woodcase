//
//  SlotPropertyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct SlotPropertyTests {
    // MARK: - FrameData slot property

    @Test("FrameData with nil slot")
    func nilSlot() {
        let frame = PenNode.FrameData()
        #expect(frame.slot == nil)
    }

    @Test("FrameData with slot values")
    func slotValues() {
        let frame = PenNode.FrameData(slot: ["frame", "text"])
        #expect(frame.slot == ["frame", "text"])
    }

    // MARK: - Codable round-trip

    @Test("Slot round-trips through JSON encoding")
    func slotCodableRoundTrip() throws {
        let node = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(slot: ["frame", "rectangle"]))
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(node)
        let decoded = try JSONDecoder().decode(PenNode.self, from: data)

        if case let .frame(frameData) = decoded.kind {
            #expect(frameData.slot == ["frame", "rectangle"])
        } else {
            Issue.record("Expected frame kind")
        }
    }

    @Test("Missing slot decodes as nil")
    func missingSlotDecodesNil() throws {
        let node = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData())
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(node)
        let decoded = try JSONDecoder().decode(PenNode.self, from: data)

        if case let .frame(frameData) = decoded.kind {
            #expect(frameData.slot == nil)
        } else {
            Issue.record("Expected frame kind")
        }
    }

    // MARK: - PropertyDiff

    @Test("PropertyDiff detects slot change")
    func propertyDiffSlot() {
        let old = PenNode.FrameData()
        let new = PenNode.FrameData(slot: ["frame"])
        let diff = PropertyDiff.diffKind(
            old: .frame(old),
            new: .frame(new)
        )
        #expect(diff.contains("kind.slot"))
    }

    @Test("PropertyDiff does not report unchanged slot")
    func propertyDiffSlotUnchanged() {
        let old = PenNode.FrameData(slot: ["frame"])
        let new = PenNode.FrameData(slot: ["frame"])
        let diff = PropertyDiff.diffKind(
            old: .frame(old),
            new: .frame(new)
        )
        #expect(!diff.contains("kind.slot"))
    }

    // MARK: - CRDT Codec

    @Test("Slot CRDT property round-trips through codec")
    func slotCRDTCodec() throws {
        let doc = PenDocument(children: [
            PenNode(id: "f1", common: PenNodeCommon(), kind: .frame(PenNode.FrameData())),
        ])
        let editable = EditableDocument(from: doc, peerID: PeerID(rawValue: "test-peer"))
        let crdt = try #require(editable.crdtDocument)

        // Extract slot value
        let kind = PenNode.Kind.frame(PenNode.FrameData(slot: ["frame", "text"]))
        let extracted = crdt.extractKindValue(property: "kind.slot", from: kind)

        // Apply slot value
        let original = PenNode.Kind.frame(PenNode.FrameData())
        let applied = crdt.applyKindProperty(property: "kind.slot", value: extracted, to: original)

        if case let .frame(data) = applied {
            #expect(data.slot == ["frame", "text"])
        } else {
            Issue.record("Expected frame kind")
        }
    }
}
