//
//  EditableDocumentIncrementalPipelineTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Tests for the external-pipeline incremental layout API.
///
/// These methods are designed for hosts (like Penumbra) that run their own
/// pipeline and need to prime the layout cache, check dirty state, and call
/// incremental layout with a pre-resolved document.
@MainActor
struct EditableDocumentIncrementalPipelineTests {
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

    /// Runs the external pipeline steps: expand, resolve, layout, prime cache.
    private func runFullPipeline(_ editable: EditableDocument) -> [String: PenRect] {
        let (expanded, _) = editable.expandedDocument()
        let resolved = PenVariableResolver.resolve(expanded)
        let rects = PenLayoutEngine.layout(resolved)
        editable.primeLayoutCache(with: rects)
        return rects
    }

    // MARK: - primeLayoutCache enables dirty tracking

    @Test("primeLayoutCache enables dirty tracking for subsequent edits")
    func primeEnablesDirtyTracking() throws {
        let editable = makeDocument()

        // Prime the cache with full layout rects
        let rects = runFullPipeline(editable)
        #expect(!rects.isEmpty)

        // Apply a color edit
        try editable.apply(.updateKind(EditOperation.UpdateKind(
            nodeID: "rect1",
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(100), height: .fixed(50),
                fills: .single(.shorthand("green"))
            ))
        )))

        // Dirty tracking should work — rect1 marked as render-dirty
        #expect(editable.dirtyRenderNodeIDs.contains("rect1"))
    }

    // MARK: - primeLayoutCache enables incremental layout

    @Test("layoutIncremental produces same result as full layout after dimension edit")
    func incrementalMatchesFullAfterDimensionEdit() throws {
        let editable = makeDocument()
        _ = runFullPipeline(editable)
        editable.clearDirtyNodes()

        // Apply a dimension edit
        try editable.apply(.updateKind(EditOperation.UpdateKind(
            nodeID: "rect1",
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(200), height: .fixed(50),
                fills: .single(.shorthand("blue"))
            ))
        )))

        // Run incremental layout via the external-pipeline API
        let (expanded, _) = editable.expandedDocument()
        let resolved = PenVariableResolver.resolve(expanded)
        let incrementalRects = editable.layoutIncremental(document: resolved)

        // Compare against a fresh full layout
        let fullRects = PenLayoutEngine.layout(resolved)

        #expect(incrementalRects["rect1"]?.width == 200)
        #expect(incrementalRects["rect1"] == fullRects["rect1"])
        #expect(incrementalRects["frame1"] == fullRects["frame1"])
        #expect(incrementalRects["frame2"] == fullRects["frame2"])
    }

    // MARK: - isLayoutFullyInvalidated reflects cache state

    @Test("isLayoutFullyInvalidated is true before priming, false after, true after structural edit")
    func isFullyInvalidatedReflectsCacheState() throws {
        let editable = makeDocument()

        // Before any layout — no cache, should report fully invalidated
        #expect(editable.isLayoutFullyInvalidated == true)

        // After priming — should be false
        _ = runFullPipeline(editable)
        #expect(editable.isLayoutFullyInvalidated == false)

        // After structural edit (insert) — should be true again
        try editable.apply(.insertNode(EditOperation.InsertNode(
            node: PenNode(
                id: "newRect",
                common: PenNodeCommon(),
                kind: .rectangle(PenNode.RectangleData(
                    width: .fixed(50), height: .fixed(50)
                ))
            ),
            parentID: "frame1"
        )))
        #expect(editable.isLayoutFullyInvalidated == true)
    }

    // MARK: - Color edit produces render-only dirty state

    @Test("Color edit after priming produces render-only dirty, not layout dirty")
    func colorEditIsRenderOnly() throws {
        let editable = makeDocument()
        _ = runFullPipeline(editable)
        editable.clearDirtyNodes()

        // Apply color-only edit
        try editable.apply(.updateKind(EditOperation.UpdateKind(
            nodeID: "rect1",
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(100), height: .fixed(50),
                fills: .single(.shorthand("green"))
            ))
        )))

        #expect(editable.dirtyLayoutNodeIDs.isEmpty)
        #expect(editable.dirtyRenderNodeIDs.contains("rect1"))
        #expect(editable.dirtyRenderNodeIDs.count == 1)
    }

    // MARK: - Structural edit sets full invalidation

    @Test("Insert after priming sets isLayoutFullyInvalidated to true")
    func structuralEditSetsFullInvalidation() throws {
        let editable = makeDocument()
        _ = runFullPipeline(editable)
        editable.clearDirtyNodes()

        #expect(editable.isLayoutFullyInvalidated == false)

        // Structural change — insert a new node
        try editable.apply(.insertNode(EditOperation.InsertNode(
            node: PenNode(
                id: "newEllipse",
                common: PenNodeCommon(),
                kind: .ellipse(PenNode.EllipseData(
                    width: .fixed(40), height: .fixed(40)
                ))
            ),
            parentID: "frame2"
        )))

        #expect(editable.isLayoutFullyInvalidated == true)
    }
}
