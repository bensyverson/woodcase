//
//  PenClipOffsetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``PenClip/offsets`` records where each copied node sat inside the parent it was
/// copied out of, so a paste into another free container can put it at the same offset.
struct PenClipOffsetTests {
    @Test("A node copied out of a free container records its offset in it")
    func freeChildRecordsOffset() throws {
        let clip = try PenClip.extract(nodeIDs: ["Free"], from: PenClipFixture.document())

        #expect(clip.offsets == ["Free": PenPoint(x: 5, y: 6)])
    }

    @Test("A node a stack placed records the offset the stack gave it")
    func stackChildRecordsOffset() throws {
        let clip = try PenClip.extract(nodeIDs: ["Fill"], from: PenClipFixture.document())

        #expect(clip.offsets?["Fill"] == PenPoint(x: 0, y: 19))
    }

    @Test("A node drawn inside an instance records its offset in the instance's drawing")
    func drawnNodeRecordsOffset() throws {
        let clip = try PenClip.extract(nodeIDs: ["BtnI/IcoRef/Icon"], from: PenClipFixture.document())

        let id = try #require(clip.contentIDs.first)
        #expect(clip.offsets?[id] == PenPoint(x: 28, y: 0))
    }

    @Test("A root has no parent, so it records no offset")
    func rootRecordsNone() throws {
        let clip = try PenClip.extract(nodeIDs: ["Page"], from: PenClipFixture.document())

        #expect(clip.offsets == nil)
    }

    @Test("A clip written before offsets existed still reads, with none")
    func oldClipDecodes() throws {
        let clip = try PenClip.extract(nodeIDs: ["Free"], from: PenClipFixture.document())
        let written = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(clip)) as? [String: Any])
        #expect(written["offsets"] != nil)
        let old = try JSONSerialization.data(withJSONObject: [
            "contentIDs": clip.contentIDs,
            "document": JSONSerialization.jsonObject(with: JSONEncoder().encode(clip.document)),
        ])

        let decoded = try JSONDecoder().decode(PenClip.self, from: old)

        #expect(decoded.offsets == nil)
        #expect(decoded.contentIDs == ["Free"])
    }
}
