//
//  PenLayoutEngineAbsoluteRectsTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// ``PenLayoutEngine/absoluteRects(under:in:layoutRects:)`` — the one walk that turns
/// the engine's parent-relative rects into a single coordinate frame.
///
/// `layout-deep-nesting` is the fixture the duplicate walks were each built against:
/// five levels, every level offset from its parent, and a settled `.layout.json` beside
/// it that records the parent-relative truth. Feeding that JSON in directly keeps the
/// test on the walk rather than on text measurement.
@Suite("PenLayoutEngine.absoluteRects")
struct PenLayoutEngineAbsoluteRectsTests {
    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.module.url(
            forResource: base, withExtension: ext, subdirectory: "Fixtures"
        ) else {
            throw FixtureLoadError.notFound(name)
        }
        return url
    }

    /// The deep-nesting document and its settled, parent-relative rects.
    private func deepNesting() throws -> (document: PenDocument, rects: [String: PenRect]) {
        let document = try PenParser.parse(contentsOf: fixtureURL("layout-deep-nesting.pen"))
        let data = try Data(contentsOf: fixtureURL("layout-deep-nesting.layout.json"))
        return try (document, JSONDecoder().decode([String: PenRect].self, from: data))
    }

    @Test("Every descendant is composed down the chain, not left at its parent offset")
    func composesTheWholeSubtree() throws {
        let (document, rects) = try deepNesting()
        let frame = PenLayoutEngine.absoluteRects(
            under: "Ms0rE", in: document, layoutRects: rects
        )

        // Ms0rE(0,0) → S4auN(10,10) → o3V8H(193,8) → D48Fa(6,6) → YOoQM(34,0).
        #expect(frame["YOoQM"] == PenRect(x: 243, y: 24, width: 30, height: 20))
        #expect(frame["gaLFu"] == PenRect(x: 209, y: 24, width: 30, height: 20))
        #expect(frame["D48Fa"] == PenRect(x: 209, y: 24, width: 167, height: 20))
        #expect(frame["o3V8H"] == PenRect(x: 203, y: 18, width: 179, height: 32))
        // Ms0rE(0,0) → S4auN(10,10) → 7yODZ(8,8) → a0OCg(6,6).
        #expect(frame["a0OCg"] == PenRect(x: 24, y: 24, width: 40, height: 30))
        #expect(frame["gBIte"] == PenRect(x: 24, y: 58, width: 40, height: 30))
        #expect(frame.count == rects.count)
    }

    @Test("The root keeps its own settled rect, so the frame is the root's own")
    func rootKeepsItsRect() throws {
        let (document, rects) = try deepNesting()
        let frame = PenLayoutEngine.absoluteRects(
            under: "Ms0rE", in: document, layoutRects: rects
        )
        #expect(frame["Ms0rE"] == rects["Ms0rE"])
    }

    @Test("A mid-tree root frames its own subtree and nothing above or beside it")
    func framesOneSubtree() throws {
        let (document, rects) = try deepNesting()
        let frame = PenLayoutEngine.absoluteRects(
            under: "o3V8H", in: document, layoutRects: rects
        )

        // The root's rect is untouched, and its descendants are measured from it —
        // the same convention `shot --outline` and the viewer's overlay both want.
        #expect(frame["o3V8H"] == PenRect(x: 193, y: 8, width: 179, height: 32))
        #expect(frame["D48Fa"] == PenRect(x: 199, y: 14, width: 167, height: 20))
        #expect(frame["YOoQM"] == PenRect(x: 233, y: 14, width: 30, height: 20))
        // Outside the subtree: not in the picture, so not in the map.
        #expect(frame["7yODZ"] == nil)
        #expect(frame["a0OCg"] == nil)
        #expect(frame["Ms0rE"] == nil)
        #expect(frame.count == 4)
    }

    @Test("A leaf frames only itself")
    func framesALeaf() throws {
        let (document, rects) = try deepNesting()
        let frame = PenLayoutEngine.absoluteRects(
            under: "YOoQM", in: document, layoutRects: rects
        )
        #expect(frame == ["YOoQM": PenRect(x: 34, y: 0, width: 30, height: 20)])
    }

    @Test("A node the document does not have frames nothing")
    func unknownRootFramesNothing() throws {
        let (document, rects) = try deepNesting()
        #expect(PenLayoutEngine.absoluteRects(
            under: "nope!", in: document, layoutRects: rects
        ).isEmpty)
    }

    @Test("A node the layout engine settled no rect for frames nothing")
    func unsettledRootFramesNothing() throws {
        let (document, rects) = try deepNesting()
        var partial = rects
        partial.removeValue(forKey: "Ms0rE")
        #expect(PenLayoutEngine.absoluteRects(
            under: "Ms0rE", in: document, layoutRects: partial
        ).isEmpty)
    }

    @Test("A descendant with no settled rect drops out, and takes its subtree with it")
    func unsettledDescendantDropsItsSubtree() throws {
        let (document, rects) = try deepNesting()
        var partial = rects
        partial.removeValue(forKey: "o3V8H")
        let frame = PenLayoutEngine.absoluteRects(
            under: "Ms0rE", in: document, layoutRects: partial
        )
        #expect(frame["o3V8H"] == nil)
        #expect(frame["D48Fa"] == nil)
        #expect(frame["YOoQM"] == nil)
        // The sibling branch is untouched.
        #expect(frame["a0OCg"] == PenRect(x: 24, y: 24, width: 40, height: 30))
    }
}
