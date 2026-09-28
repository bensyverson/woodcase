//
//  PenLayoutFlexBufferReuseTests.swift
//  WoodcaseTests
//
//  Regression tests for Phase 2c: measurement buffer reuse in flex layout.
//  These verify that cross-flexible containers (fill_container on cross axis)
//  with descendants produce correct rects both before and after optimization.
//

import Foundation
import Testing
import Woodcase

struct PenLayoutFlexBufferReuseTests {
    private let noopMeasurer: TextMeasurer = { _, _, _, _, _, _, _, _ in (width: 100, height: 20) }

    // MARK: - Cross-flexible container child with descendants

    @Test("Cross-flexible container child descendants get correct rects")
    func crossFlexibleContainerChildDescendants() {
        // Horizontal parent (fitContent on both axes)
        // ├── rect-a: fixed 80×40 (sets cross content size to 40)
        // └── container-b: fixed 100 wide, fillContainer height (cross-flexible)
        //     └── leaf-b1: fixed 60×20 (should be positioned inside container-b)

        let leafB1 = PenNode(
            id: "leaf-b1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(60),
                height: .fixed(20)
            ))
        )

        let containerB = PenNode(
            id: "container-b",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                width: .fixed(100),
                height: .fillContainer(fallback: nil),
                layout: .vertical,
                children: [leafB1]
            ))
        )

        let rectA = PenNode(
            id: "rect-a",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(80),
                height: .fixed(40)
            ))
        )

        let root = PenNode(
            id: "root",
            common: PenNodeCommon(x: .literal(0), y: .literal(0)),
            kind: .frame(PenNode.FrameData(
                width: .fitContent(fallback: nil),
                height: .fitContent(fallback: nil),
                layout: .horizontal,
                children: [rectA, containerB]
            ))
        )

        let doc = PenDocument(children: [root])
        let rects = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)

        // root: fitContent → width = 80 + 100 = 180, height = max(40, 40) = 40
        #expect(rects["root"]?.width == 180, "root width")
        #expect(rects["root"]?.height == 40, "root height")

        // rect-a: at (0, 0), size 80×40
        #expect(rects["rect-a"]?.x == 0, "rect-a x")
        #expect(rects["rect-a"]?.y == 0, "rect-a y")
        #expect(rects["rect-a"]?.width == 80, "rect-a width")
        #expect(rects["rect-a"]?.height == 40, "rect-a height")

        // container-b: at (80, 0), width 100, height fills to cross content = 40
        #expect(rects["container-b"]?.x == 80, "container-b x")
        #expect(rects["container-b"]?.y == 0, "container-b y")
        #expect(rects["container-b"]?.width == 100, "container-b width")
        #expect(rects["container-b"]?.height == 40, "container-b height")

        // leaf-b1: positioned inside container-b at (0, 0), size 60×20
        #expect(rects["leaf-b1"]?.x == 0, "leaf-b1 x")
        #expect(rects["leaf-b1"]?.y == 0, "leaf-b1 y")
        #expect(rects["leaf-b1"]?.width == 60, "leaf-b1 width")
        #expect(rects["leaf-b1"]?.height == 20, "leaf-b1 height")
    }

    @Test("Non-cross-flexible container child descendants get correct rects")
    func nonCrossFlexibleContainerChildDescendants() {
        // Horizontal parent (fitContent on both axes)
        // ├── rect-a: fixed 80×40
        // └── container-b: fitContent on both axes (NOT cross-flexible)
        //     └── leaf-b1: fixed 60×20

        let leafB1 = PenNode(
            id: "leaf-b1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(60),
                height: .fixed(20)
            ))
        )

        let containerB = PenNode(
            id: "container-b",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                width: .fitContent(fallback: nil),
                height: .fitContent(fallback: nil),
                layout: .vertical,
                children: [leafB1]
            ))
        )

        let rectA = PenNode(
            id: "rect-a",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(80),
                height: .fixed(40)
            ))
        )

        let root = PenNode(
            id: "root",
            common: PenNodeCommon(x: .literal(0), y: .literal(0)),
            kind: .frame(PenNode.FrameData(
                width: .fitContent(fallback: nil),
                height: .fitContent(fallback: nil),
                layout: .horizontal,
                children: [rectA, containerB]
            ))
        )

        let doc = PenDocument(children: [root])
        let rects = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)

        // root: fitContent → width = 80 + 60 = 140, height = max(40, 20) = 40
        #expect(rects["root"]?.width == 140, "root width")
        #expect(rects["root"]?.height == 40, "root height")

        // container-b: at (80, 0), fitContent → 60×20
        #expect(rects["container-b"]?.x == 80, "container-b x")
        #expect(rects["container-b"]?.y == 0, "container-b y")
        #expect(rects["container-b"]?.width == 60, "container-b width")
        #expect(rects["container-b"]?.height == 20, "container-b height")

        // leaf-b1: inside container-b at (0, 0), 60×20
        #expect(rects["leaf-b1"]?.x == 0, "leaf-b1 x")
        #expect(rects["leaf-b1"]?.y == 0, "leaf-b1 y")
        #expect(rects["leaf-b1"]?.width == 60, "leaf-b1 width")
        #expect(rects["leaf-b1"]?.height == 20, "leaf-b1 height")
    }

    @Test("Main-flexible container child descendants get correct rects")
    func mainFlexibleContainerChildDescendants() {
        // Horizontal parent, fixed 400 wide
        // ├── rect-a: fixed 100×40
        // └── container-b: fillContainer width (main-flexible), fitContent height
        //     └── leaf-b1: fixed 60×20

        let leafB1 = PenNode(
            id: "leaf-b1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(60),
                height: .fixed(20)
            ))
        )

        let containerB = PenNode(
            id: "container-b",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                width: .fillContainer(fallback: nil),
                height: .fitContent(fallback: nil),
                layout: .vertical,
                children: [leafB1]
            ))
        )

        let rectA = PenNode(
            id: "rect-a",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(100),
                height: .fixed(40)
            ))
        )

        let root = PenNode(
            id: "root",
            common: PenNodeCommon(x: .literal(0), y: .literal(0)),
            kind: .frame(PenNode.FrameData(
                width: .fixed(400),
                height: .fitContent(fallback: nil),
                layout: .horizontal,
                children: [rectA, containerB]
            ))
        )

        let doc = PenDocument(children: [root])
        let rects = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)

        // root: fixed 400 wide, fitContent height = max(40, 20) = 40
        #expect(rects["root"]?.width == 400, "root width")
        #expect(rects["root"]?.height == 40, "root height")

        // container-b: fillContainer on main → 400 - 100 = 300 wide, fitContent → 20 tall
        #expect(rects["container-b"]?.x == 100, "container-b x")
        #expect(rects["container-b"]?.y == 0, "container-b y")
        #expect(rects["container-b"]?.width == 300, "container-b width")
        #expect(rects["container-b"]?.height == 20, "container-b height")

        // leaf-b1: inside container-b at (0, 0), 60×20
        #expect(rects["leaf-b1"]?.x == 0, "leaf-b1 x")
        #expect(rects["leaf-b1"]?.y == 0, "leaf-b1 y")
        #expect(rects["leaf-b1"]?.width == 60, "leaf-b1 width")
        #expect(rects["leaf-b1"]?.height == 20, "leaf-b1 height")
    }

    @Test("Deeply nested cross-flexible containers produce correct rects")
    func deeplyNestedCrossFlexible() {
        // Horizontal root (fitContent)
        // ├── rect-a: 80×60 (sets cross content to 60)
        // └── mid: fixed 200 wide, fillContainer height (cross-flex)
        //     └── inner: fitContent width, fitContent height
        //         └── deep-leaf: 50×30

        let deepLeaf = PenNode(
            id: "deep-leaf",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(50),
                height: .fixed(30)
            ))
        )

        let inner = PenNode(
            id: "inner",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                width: .fitContent(fallback: nil),
                height: .fitContent(fallback: nil),
                layout: .vertical,
                children: [deepLeaf]
            ))
        )

        let mid = PenNode(
            id: "mid",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                width: .fixed(200),
                height: .fillContainer(fallback: nil),
                layout: .vertical,
                children: [inner]
            ))
        )

        let rectA = PenNode(
            id: "rect-a",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(80),
                height: .fixed(60)
            ))
        )

        let root = PenNode(
            id: "root",
            common: PenNodeCommon(x: .literal(0), y: .literal(0)),
            kind: .frame(PenNode.FrameData(
                width: .fitContent(fallback: nil),
                height: .fitContent(fallback: nil),
                layout: .horizontal,
                children: [rectA, mid]
            ))
        )

        let doc = PenDocument(children: [root])
        let rects = PenLayoutEngine.layout(doc, textMeasurer: noopMeasurer)

        // root: 80 + 200 = 280 wide, max(60, ?) = 60 tall
        #expect(rects["root"]?.width == 280, "root width")
        #expect(rects["root"]?.height == 60, "root height")

        // mid: fillContainer height → 60, fixed 200 wide
        #expect(rects["mid"]?.x == 80, "mid x")
        #expect(rects["mid"]?.width == 200, "mid width")
        #expect(rects["mid"]?.height == 60, "mid height")

        // inner: fitContent → 50×30, inside mid
        #expect(rects["inner"]?.x == 0, "inner x")
        #expect(rects["inner"]?.y == 0, "inner y")
        #expect(rects["inner"]?.width == 50, "inner width")
        #expect(rects["inner"]?.height == 30, "inner height")

        // deep-leaf: inside inner at (0, 0)
        #expect(rects["deep-leaf"]?.x == 0, "deep-leaf x")
        #expect(rects["deep-leaf"]?.y == 0, "deep-leaf y")
        #expect(rects["deep-leaf"]?.width == 50, "deep-leaf width")
        #expect(rects["deep-leaf"]?.height == 30, "deep-leaf height")
    }
}
