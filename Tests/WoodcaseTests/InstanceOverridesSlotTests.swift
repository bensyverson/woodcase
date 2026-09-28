//
//  InstanceOverridesSlotTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How ``InstanceOverrides`` sorts an override that fills a slot: the children an instance
/// writes into a frame the emitter declares as a slot are a fill a call can carry; the same
/// write anywhere else, or beside a property no prop carries, is still unmapped.
struct InstanceOverridesSlotTests {
    @Test("Children written into a declared slot are its fill, not unmapped")
    func fillIsMapped() throws {
        let overrides = try Self.overrides(##"{"S": {"children": [{"type": "text", "id": "t", "content": "Hi"}]}}"##, slots: ["S"])
        #expect(overrides.unmapped.isEmpty)
        #expect(overrides.slotFills["S"]?.map(\.id) == ["t"])
    }

    @Test("Children written into a frame that is no declared slot are unmapped")
    func undeclaredSlot() throws {
        let overrides = try Self.overrides(##"{"S": {"children": [{"type": "text", "id": "t", "content": "Hi"}]}}"##, slots: [])
        #expect(overrides.unmapped == ["S"])
        #expect(overrides.slotFills.isEmpty)
    }

    @Test("A fill beside a property of the slot frame no prop carries is unmapped")
    func fillWithPaint() throws {
        let overrides = try Self.overrides(
            ##"{"S": {"fill": "#FF0000", "children": [{"type": "text", "id": "t", "content": "Hi"}]}}"##, slots: ["S"]
        )
        #expect(overrides.unmapped == ["S"])
    }

    @Test("A whole-node replacement of a slot frame is unmapped")
    func replacement() throws {
        let overrides = try Self.overrides(##"{"S": {"type": "frame", "id": "S", "children": []}}"##, slots: ["S"])
        #expect(overrides.unmapped == ["S"])
    }

    /// The overrides of a `ref` to a component holding the frame `S`, whose `descendants`
    /// are `descendants`, sorted against `slots`.
    private static func overrides(_ descendants: String, slots: Set<String>) throws -> InstanceOverrides {
        let json = ##"""
        {"version": "2.17", "children": [
          {"type": "frame", "id": "B", "name": "Box", "reusable": true, "width": 100, "height": 60, "layout": "vertical",
           "children": [{"type": "frame", "id": "S", "name": "Slot", "slot": [], "layout": "vertical"}]},
          {"type": "ref", "id": "i", "ref": "B", "descendants": \##(descendants)}]}
        """##
        let document = try PenParser.parse(Data(json.utf8))
        let component = try #require(ComponentAnalyzer.analyze(document).first)
        let ref: PenNode.RefData? = if case let .ref(data) = document.children[1].kind { data } else { nil }
        let data = try #require(ref)
        return InstanceOverrides(of: data, against: component, slots: slots)
    }
}
