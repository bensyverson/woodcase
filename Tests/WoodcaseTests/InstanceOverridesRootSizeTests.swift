//
//  InstanceOverridesRootSizeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How ``InstanceOverrides`` sorts an instance's own `width` and `height`: a size that
/// sizes the component's root differently is the root's new sizing, for the target to
/// place or refuse, not an unmapped override; one that sizes it as before is nothing.
struct InstanceOverridesRootSizeTests {
    @Test("A width that resizes the root is its new sizing, not unmapped")
    func resizedWidth() throws {
        let overrides = try Self.overrides(##""width": "fill_container""##)
        #expect(overrides.unmapped.isEmpty)
        #expect(overrides.rootWidth == .fillContainer(fallback: nil))
        #expect(overrides.rootHeight == nil)
    }

    @Test("A height that resizes the root is its new sizing")
    func resizedHeight() throws {
        let overrides = try Self.overrides(##""height": 90"##)
        #expect(overrides.unmapped.isEmpty)
        #expect(overrides.rootHeight == .fixed(90))
        #expect(overrides.rootWidth == nil)
    }

    @Test("A size equal to the root's own resizes nothing, beside one that resizes")
    func sameSize() throws {
        let overrides = try Self.overrides(##""width": 100, "height": "fill_container""##)
        #expect(overrides.rootWidth == nil)
        #expect(overrides.rootHeight == .fillContainer(fallback: nil))
        #expect(overrides.unmapped.isEmpty)
    }

    @Test("A root override beside the size that changes the drawing is still unmapped")
    func sizeBesidePaint() throws {
        let overrides = try Self.overrides(##""width": 200, "fill": "#FF0000""##)
        #expect(overrides.rootWidth == .fixed(200))
        #expect(overrides.unmapped == ["fill"])
    }

    /// The overrides of a `ref` to a 100 × 60 component whose own properties add `root`.
    private static func overrides(_ root: String) throws -> InstanceOverrides {
        let json = ##"""
        {"version": "2.17", "children": [
          {"type": "frame", "id": "B", "name": "Box", "reusable": true, "width": 100, "height": 60, "layout": "vertical",
           "children": [{"type": "text", "id": "t", "content": "Hi"}]},
          {"type": "ref", "id": "i", "ref": "B", \##(root)}]}
        """##
        let document = try PenParser.parse(Data(json.utf8))
        let component = try #require(ComponentAnalyzer.analyze(document).first)
        let ref: PenNode.RefData? = if case let .ref(data) = document.children[1].kind { data } else { nil }
        return try InstanceOverrides(of: #require(ref), against: component)
    }
}
