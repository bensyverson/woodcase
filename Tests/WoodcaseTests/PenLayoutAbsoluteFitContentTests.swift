//
//  PenLayoutAbsoluteFitContentTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-08-29.
//

import Foundation
import Testing
import Woodcase

/// Covers the content size of an absolute container — a `frame` with
/// `layout: "none"` and every `group` — when its width or height is
/// `fit_content`. See `PenEngine.md`, "Absolute containers and `fit_content`".
struct PenLayoutAbsoluteFitContentTests {
    // MARK: - Helpers

    private static let tolerance = 0.001

    private func rect(
        _ rects: [String: PenRect],
        _ id: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> PenRect {
        try #require(rects[id], "no rect for \(id)", sourceLocation: sourceLocation)
    }

    private func expectSize(
        _ rect: PenRect,
        width: Double,
        height: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            abs(rect.width - width) < Self.tolerance,
            "width: got \(rect.width), expected \(width)",
            sourceLocation: sourceLocation
        )
        #expect(
            abs(rect.height - height) < Self.tolerance,
            "height: got \(rect.height), expected \(height)",
            sourceLocation: sourceLocation
        )
    }

    private func fixedRect(
        id: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        rotation: Double? = nil,
        enabled: Bool? = nil
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(
                x: .literal(x),
                y: .literal(y),
                rotation: rotation.map { PenValue<Double>.literal($0) },
                enabled: enabled.map { PenValue<Bool>.literal($0) }
            ),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(width), height: .fixed(height)))
        )
    }

    // MARK: - Frame with layout none

    // Pen settles a `layout: "none"` frame's `fit_content` axis at its fallback — 0 by
    // default — never at its children's union, and re-saves a missing width or height as
    // `fit_content(0)` (the Pen probe on leaf Jg0BOv, `render-sizeless-frames.pen`). These
    // tests used to pin the union measured from the frame's origin, an inferred rule.

    @Test("A frame with layout none and no size settles at 0×0, its children at their own x/y")
    func sizelessAbsoluteFrameSettlesAtZero() throws {
        let doc = PenDocument(version: "2.17", children: [
            PenNode(
                id: "frame1",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    layout: PenLayoutDirection.none,
                    children: [
                        fixedRect(id: "a", x: 10, y: 20, width: 30, height: 40),
                        fixedRect(id: "b", x: -10, y: 5, width: 20, height: 20),
                    ]
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc)

        try expectSize(rect(rects, "frame1"), width: 0, height: 0)
        #expect(try rect(rects, "a") == PenRect(x: 10, y: 20, width: 30, height: 40))
        #expect(try rect(rects, "b") == PenRect(x: -10, y: 5, width: 20, height: 20))
    }

    @Test("fit_content on a layout-none frame is its fallback, however far its children reach")
    func absoluteFrameFitContentIsItsFallback() throws {
        let doc = PenDocument(version: "2.17", children: [
            PenNode(
                id: "bare",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    width: .fitContent(fallback: nil),
                    height: .fitContent(fallback: nil),
                    layout: PenLayoutDirection.none,
                    children: [fixedRect(id: "a", x: 10, y: 10, width: 80, height: 40)]
                ))
            ),
            PenNode(
                id: "fallback",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    width: .fitContent(fallback: 30),
                    height: .fitContent(fallback: 20),
                    layout: PenLayoutDirection.none,
                    children: [fixedRect(id: "b", x: 10, y: 10, width: 80, height: 40)]
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc)

        try expectSize(rect(rects, "bare"), width: 0, height: 0)
        try expectSize(rect(rects, "fallback"), width: 30, height: 20)
    }

    @Test("A frame with layout none and padding still settles at 0×0")
    func absoluteFramePaddingIsNotReserved() throws {
        // An absolute container does not offset its children by padding, so padding adds
        // nothing to its size either.
        let doc = PenDocument(version: "2.17", children: [
            PenNode(
                id: "frame1",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    layout: PenLayoutDirection.none,
                    padding: .uniform(.literal(16)),
                    children: [fixedRect(id: "a", x: 10, y: 20, width: 30, height: 40)]
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc)

        try expectSize(rect(rects, "frame1"), width: 0, height: 0)
    }

    @Test("A sizeless layout-none frame takes no space in a flex flow, and a fit_content parent fits only its padding")
    func sizelessAbsoluteFrameTakesNoFlowSpace() throws {
        // Pen: in a horizontal frame with gap 10 the sibling after it lands at x = 10, and a
        // fit_content parent with padding 5 settles at 10×10 (`render-sizeless-frames.pen`).
        let sizeless = PenNode(
            id: "sizeless",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                layout: PenLayoutDirection.none,
                children: [fixedRect(id: "a", x: 0, y: 0, width: 50, height: 50)]
            ))
        )
        let doc = PenDocument(version: "2.17", children: [
            PenNode(
                id: "row",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    layout: .horizontal,
                    gap: .literal(10),
                    padding: .uniform(.literal(5)),
                    children: [sizeless, fixedRect(id: "sibling", x: 0, y: 0, width: 30, height: 30)]
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc)

        #expect(try rect(rects, "sibling").x == 15)
        try expectSize(rect(rects, "row"), width: 50, height: 40)
    }

    // MARK: - Groups

    @Test("A group sizes to the union of its children, which need not include its anchor")
    func groupFitsChildren() throws {
        // Pen settles a group at its children's true union, not the union from its anchor:
        // a group at (50, 50) with children at (20, 30) and (80, 60) settles at (70, 80)
        // (`render-free-groups.pen`, leaf cqBw2i). This test used to pin the origin at the
        // anchor, (5, 7), 120×60 — an inferred rule Pen's layout contradicts.
        let doc = PenDocument(version: "2.17", children: [
            PenNode(
                id: "group1",
                common: PenNodeCommon(x: .literal(5), y: .literal(7)),
                kind: .group(PenNode.GroupData(children: [
                    fixedRect(id: "a", x: 10, y: 20, width: 30, height: 40),
                    fixedRect(id: "b", x: 100, y: 5, width: 20, height: 20),
                ]))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc)

        let group = try rect(rects, "group1")
        #expect(group.x == 15)
        #expect(group.y == 12)
        expectSize(group, width: 110, height: 55)
    }

    @Test("A turned group's rect is its union turned about its anchor")
    func rotatedGroupIsTurnedAboutItsAnchor() throws {
        // A group's x/y anchors its children's coordinate system, and Pen turns the group
        // about that anchor and settles the bounds of its children's union turned
        // (`render-free-groups.pen`'s `rot`, leaf cqBw2i). This test used to pin the
        // un-turned union, 100×100 at the anchor — the rect the renderer then turned about
        // its origin; Pen's layout reports the turned bounds.
        let doc = PenDocument(version: "2.17", children: [
            PenNode(
                id: "group1",
                common: PenNodeCommon(x: .literal(0), y: .literal(0), rotation: .literal(45)),
                kind: .group(PenNode.GroupData(children: [
                    fixedRect(id: "a", x: 0, y: 0, width: 100, height: 100),
                ]))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc)

        let group = try rect(rects, "group1")
        let diagonal = 100 * 2.0.squareRoot()
        #expect(abs(group.x) < Self.tolerance)
        #expect(abs(group.y + diagonal / 2) < Self.tolerance)
        expectSize(group, width: diagonal, height: diagonal)
    }

    // MARK: - Union definition

    @Test("A disabled child is excluded from a group's union")
    func disabledChildIsExcluded() throws {
        // This test used to ask a sizeless layout-none frame, which now settles at 0×0
        // whatever it holds; a group is the absolute container that still takes a union.
        let doc = PenDocument(version: "2.17", children: [
            PenNode(
                id: "group1",
                common: PenNodeCommon(),
                kind: .group(PenNode.GroupData(children: [
                    fixedRect(id: "a", x: 0, y: 0, width: 30, height: 40),
                    fixedRect(id: "b", x: 100, y: 100, width: 10, height: 10, enabled: false),
                ]))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc)

        try expectSize(rect(rects, "group1"), width: 30, height: 40)
    }

    @Test("An empty absolute container falls back to its fit_content fallback")
    func emptyContainerUsesFallback() throws {
        let doc = PenDocument(version: "2.17", children: [
            PenNode(
                id: "frame1",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    width: .fitContent(fallback: 111),
                    height: .fitContent(fallback: 222),
                    layout: PenLayoutDirection.none,
                    children: []
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc)

        try expectSize(rect(rects, "frame1"), width: 111, height: 222)
    }

    // MARK: - Fixture

    @Test("The layout-absolute-fit-content fixture settles its group at its union and its frame at 0×0")
    func fixtureUnionSizes() throws {
        let url = try #require(
            Bundle.module.url(forResource: "layout-absolute-fit-content", withExtension: "pen", subdirectory: "Fixtures")
        )
        let document = try PenParser.parse(contentsOf: url)
        let rects = PenLayoutEngine.layout(document)

        // g1r is a 20×20 rotated 45°, so its bounding box is 20 * sqrt(2).
        let rotatedBox = 20 * 2.0.squareRoot()

        // Group extents from its anchor: (0, 0)–(40, 40), (30, 50)–(55, 75), and g1r turned
        // 45° about its own anchor (100, 0), reaching half its bounding box above it. The
        // group's rect is their true union, so it starts that far above the group's anchor;
        // until leaf cqBw2i it was pinned at the anchor, 75 tall.
        let group = try rect(rects, "g1")
        expectSize(group, width: 100 + rotatedBox, height: 75 + rotatedBox / 2)
        #expect(abs(group.y - (10 - rotatedBox / 2)) < Self.tolerance)

        // The layout-none frame declares no size, so it settles at 0×0 as Pen's does; it
        // used to take its children's union from its origin, 160 + 20√2 × 85.
        try expectSize(rect(rects, "frame1"), width: 0, height: 0)
    }
}
