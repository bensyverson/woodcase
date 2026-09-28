//
//  EditableDocumentLayoutTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct EditableDocumentLayoutTests {
    // MARK: - Helpers

    private func makeDocument() -> EditableDocument {
        let doc = PenDocument(
            version: "1",
            children: [
                PenNode(
                    id: "frame1",
                    common: PenNodeCommon(x: .literal(0), y: .literal(0)),
                    kind: .frame(PenNode.FrameData(
                        width: .fixed(400), height: .fixed(300),
                        fills: .single(.shorthand("red")),
                        children: [
                            PenNode(
                                id: "rect1",
                                common: PenNodeCommon(),
                                kind: .rectangle(PenNode.RectangleData(
                                    width: .fixed(100), height: .fixed(50),
                                    fills: .single(.shorthand("blue"))
                                ))
                            ),
                        ]
                    ))
                ),
                PenNode(
                    id: "frame2",
                    common: PenNodeCommon(x: .literal(500), y: .literal(0)),
                    kind: .frame(PenNode.FrameData(
                        width: .fixed(200), height: .fixed(200),
                        children: [
                            PenNode(
                                id: "rect2",
                                common: PenNodeCommon(),
                                kind: .rectangle(PenNode.RectangleData(
                                    width: .fixed(80), height: .fixed(80)
                                ))
                            ),
                        ]
                    ))
                ),
            ]
        )
        return EditableDocument(from: doc)
    }

    // MARK: - First Layout (Full)

    @Test("First computeLayout does full layout")
    func firstComputeLayoutIsFull() {
        let editable = makeDocument()
        let rects = editable.computeLayout()

        #expect(rects["frame1"] != nil)
        #expect(rects["rect1"] != nil)
        #expect(rects["frame2"] != nil)
        #expect(rects["rect2"] != nil)
        #expect(rects["frame1"]?.width == 400)
        #expect(rects["frame2"]?.width == 200)
    }

    // MARK: - Color Change → Render-Only Dirty

    @Test("Color change produces render-only dirty, same rects")
    func colorChangeRenderOnlyDirty() throws {
        let editable = makeDocument()
        let firstRects = editable.computeLayout()
        editable.clearDirtyNodes()

        // Change fill color only
        try editable.apply(.updateKind(EditOperation.UpdateKind(
            nodeID: "rect1",
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(100), height: .fixed(50),
                fills: .single(.shorthand("green"))
            ))
        )))

        #expect(editable.dirtyRenderNodeIDs.contains("rect1"))
        #expect(!editable.dirtyLayoutNodeIDs.contains("rect1"))

        let secondRects = editable.computeLayout()
        // Rects should be identical (no layout change)
        #expect(secondRects["frame1"] == firstRects["frame1"])
        #expect(secondRects["rect1"] == firstRects["rect1"])
        #expect(secondRects["frame2"] == firstRects["frame2"])
    }

    // MARK: - Width Change → Layout Dirty

    @Test("Width change produces layout-dirty with updated rects")
    func widthChangeLayoutDirty() throws {
        let editable = makeDocument()
        _ = editable.computeLayout()
        editable.clearDirtyNodes()

        // Change width
        try editable.apply(.updateKind(EditOperation.UpdateKind(
            nodeID: "rect1",
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(200), height: .fixed(50),
                fills: .single(.shorthand("blue"))
            ))
        )))

        #expect(editable.dirtyLayoutNodeIDs.contains("rect1"))
        #expect(editable.dirtyLayoutNodeIDs.contains("frame1")) // ancestor

        let updatedRects = editable.computeLayout()
        #expect(updatedRects["rect1"]?.width == 200)
    }

    // MARK: - dirtyNodeIDs Union

    @Test("dirtyNodeIDs is union of layout and render")
    func dirtyNodeIDsIsUnion() throws {
        let editable = makeDocument()
        _ = editable.computeLayout()
        editable.clearDirtyNodes()

        // Render-only change on rect1
        try editable.apply(.updateKind(EditOperation.UpdateKind(
            nodeID: "rect1",
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(100), height: .fixed(50),
                fills: .single(.shorthand("green"))
            ))
        )))

        // Layout change on rect2
        try editable.apply(.updateKind(EditOperation.UpdateKind(
            nodeID: "rect2",
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(160), height: .fixed(80)
            ))
        )))

        let allDirty = editable.dirtyNodeIDs
        #expect(allDirty.contains("rect1"))
        #expect(allDirty.contains("rect2"))
        #expect(allDirty.contains("frame2")) // ancestor of rect2
    }

    // MARK: - clearDirtyNodes

    @Test("clearDirtyNodes empties all dirty sets")
    func clearDirtyNodesWorks() throws {
        let editable = makeDocument()
        _ = editable.computeLayout()
        editable.clearDirtyNodes()

        try editable.apply(.updateKind(EditOperation.UpdateKind(
            nodeID: "rect1",
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(200), height: .fixed(50)
            ))
        )))

        #expect(!editable.dirtyNodeIDs.isEmpty)
        editable.clearDirtyNodes()
        #expect(editable.dirtyNodeIDs.isEmpty)
        #expect(editable.dirtyLayoutNodeIDs.isEmpty)
        #expect(editable.dirtyRenderNodeIDs.isEmpty)
    }

    // MARK: - Variables with Inherited Theme

    @Test("computeLayout resolves variables with inherited per-node theming")
    func computeLayoutResolvesInheritedThemes() {
        let doc = PenDocument(
            version: "1",
            themes: ["mode": ["light", "dark"]],
            variables: [
                "frameWidth": PenVariable(
                    type: .number,
                    value: .themed([
                        PenThemedValue(value: .double(200), theme: ["mode": "light"]),
                        PenThemedValue(value: .double(400), theme: ["mode": "dark"]),
                    ])
                ),
            ],
            children: [
                PenNode(
                    id: "frame1",
                    common: PenNodeCommon(
                        x: .literal(0), y: .literal(0),
                        theme: ["mode": "dark"]
                    ),
                    kind: .frame(PenNode.FrameData(
                        width: .variable("frameWidth"),
                        height: .fixed(100),
                        children: []
                    ))
                ),
            ]
        )
        let editable = EditableDocument(from: doc)
        let rects = editable.computeLayout()

        // With inherited dark theme, frameWidth should resolve to 400
        #expect(rects["frame1"]?.width == 400)
    }
}
