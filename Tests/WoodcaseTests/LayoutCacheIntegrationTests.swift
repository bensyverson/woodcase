//
//  LayoutCacheIntegrationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct LayoutCacheIntegrationTests {
    // MARK: - Helpers

    /// Creates an EditableDocument with a layout cache pre-initialized.
    private func makeDocument() -> EditableDocument {
        let doc = PenDocument(
            version: "1",
            children: [
                PenNode(
                    id: "root1",
                    common: PenNodeCommon(),
                    kind: .frame(PenNode.FrameData(
                        width: .fixed(400), height: .fixed(300),
                        fills: .single(.shorthand("red")),
                        children: [
                            PenNode(
                                id: "child1",
                                common: PenNodeCommon(),
                                kind: .rectangle(PenNode.RectangleData(
                                    width: .fixed(100), height: .fixed(50),
                                    fills: .single(.shorthand("blue"))
                                ))
                            ),
                            PenNode(
                                id: "child2",
                                common: PenNodeCommon(),
                                kind: .text(PenNode.TextData(
                                    width: .fixed(200),
                                    content: .literal("Hello")
                                ))
                            ),
                        ]
                    ))
                ),
            ]
        )
        let editable = EditableDocument(from: doc)
        // Initialize the layout cache
        editable._layoutCache = LayoutCache()
        editable._layoutCache?.store(rects: [:])
        return editable
    }

    // MARK: - Color Change → Render Only

    @Test("Color-only change produces render-only dirty node")
    func colorChangeIsRenderOnly() throws {
        let editable = makeDocument()
        guard var node = editable.nodes["child1"] else {
            Issue.record("child1 not found")
            return
        }
        node.kind = .rectangle(PenNode.RectangleData(
            width: .fixed(100), height: .fixed(50),
            fills: .single(.shorthand("green"))
        ))
        try editable.apply(.updateKind(EditOperation.UpdateKind(
            nodeID: "child1", kind: node.kind
        )))

        let cache = try #require(editable._layoutCache)
        #expect(cache.dirtyRenderNodes.contains("child1"))
        #expect(!cache.dirtyLayoutNodes.contains("child1"))
        #expect(!cache.isFullyInvalidated)
    }

    // MARK: - Width Change → Layout Dirty with Ancestors

    @Test("Width change produces layout-dirty node with ancestors")
    func widthChangeIsLayoutDirty() throws {
        let editable = makeDocument()
        try editable.apply(.updateKind(EditOperation.UpdateKind(
            nodeID: "child1",
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(200), height: .fixed(50),
                fills: .single(.shorthand("blue"))
            ))
        )))

        let cache = try #require(editable._layoutCache)
        #expect(cache.dirtyLayoutNodes.contains("child1"))
        #expect(cache.dirtyLayoutNodes.contains("root1")) // ancestor
        #expect(!cache.isFullyInvalidated)
    }

    // MARK: - Delete Node → Full Invalidation

    @Test("Delete node fully invalidates cache")
    func deleteNodeFullyInvalidates() throws {
        let editable = makeDocument()
        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "child2")))

        let cache = try #require(editable._layoutCache)
        #expect(cache.isFullyInvalidated)
    }

    // MARK: - Insert Node → Full Invalidation

    @Test("Insert node fully invalidates cache")
    func insertNodeFullyInvalidates() throws {
        let editable = makeDocument()
        let newNode = PenNode(
            id: "child3",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(50), height: .fixed(50)))
        )
        try editable.apply(.insertNode(EditOperation.InsertNode(
            node: newNode, parentID: "root1"
        )))

        let cache = try #require(editable._layoutCache)
        #expect(cache.isFullyInvalidated)
    }

    // MARK: - Move Node → Full Invalidation

    @Test("Move node fully invalidates cache")
    func moveNodeFullyInvalidates() throws {
        // Need a second root to move into
        let doc = PenDocument(
            version: "1",
            children: [
                PenNode(
                    id: "root1", common: PenNodeCommon(),
                    kind: .frame(PenNode.FrameData(children: [
                        PenNode(id: "child1", common: PenNodeCommon(),
                                kind: .rectangle(PenNode.RectangleData())),
                    ]))
                ),
                PenNode(
                    id: "root2", common: PenNodeCommon(),
                    kind: .frame(PenNode.FrameData(children: []))
                ),
            ]
        )
        let editable = EditableDocument(from: doc)
        editable._layoutCache = LayoutCache()
        editable._layoutCache?.store(rects: [:])

        try editable.apply(.moveNode(EditOperation.MoveNode(
            nodeID: "child1", newParentID: "root2"
        )))

        #expect(try #require(editable._layoutCache?.isFullyInvalidated))
    }

    // MARK: - Variable Change → Full Invalidation

    @Test("Variable change fully invalidates cache")
    func variableChangeFullyInvalidates() throws {
        let editable = makeDocument()
        try editable.apply(.addVariable(EditOperation.AddVariable(
            name: "spacing",
            variable: PenVariable(type: .number, value: .simple(.double(8.0)))
        )))

        #expect(try #require(editable._layoutCache?.isFullyInvalidated))
    }

    // MARK: - Theme Change → Full Invalidation

    @Test("Theme axis change fully invalidates cache")
    func themeChangeFullyInvalidates() throws {
        let editable = makeDocument()
        try editable.apply(.addThemeAxis(EditOperation.AddThemeAxis(
            name: "mode", options: ["light", "dark"]
        )))

        #expect(try #require(editable._layoutCache?.isFullyInvalidated))
    }

    // MARK: - Import Change → Full Invalidation

    @Test("Import change fully invalidates cache")
    func importChangeFullyInvalidates() throws {
        let editable = makeDocument()
        try editable.apply(.addImport(EditOperation.AddImport(
            alias: "lib", path: "./library.pen"
        )))

        #expect(try #require(editable._layoutCache?.isFullyInvalidated))
    }

    // MARK: - Common Property Changes

    @Test("Opacity change on common produces render-only dirty node")
    func opacityChangeIsRenderOnly() throws {
        let editable = makeDocument()
        var newCommon = try #require(editable.nodes["child1"]?.common)
        newCommon.opacity = .literal(0.5)
        try editable.apply(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "child1", common: newCommon
        )))

        let cache = try #require(editable._layoutCache)
        #expect(cache.dirtyRenderNodes.contains("child1"))
        #expect(!cache.dirtyLayoutNodes.contains("child1"))
    }

    @Test("Position change on common produces layout-dirty node")
    func positionChangeIsLayoutDirty() throws {
        let editable = makeDocument()
        var newCommon = try #require(editable.nodes["child1"]?.common)
        newCommon.x = .literal(50)
        try editable.apply(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "child1", common: newCommon
        )))

        let cache = try #require(editable._layoutCache)
        #expect(cache.dirtyLayoutNodes.contains("child1"))
        #expect(cache.dirtyLayoutNodes.contains("root1"))
    }

    // MARK: - CRDT Remote SetNode

    @Test("Remote CRDT setNode categorizes correctly")
    func remoteCRDTSetNodeCategorizes() throws {
        let doc = PenDocument(
            version: "1",
            children: [
                PenNode(
                    id: "root1", common: PenNodeCommon(),
                    kind: .frame(PenNode.FrameData(children: [
                        PenNode(
                            id: "rect1", common: PenNodeCommon(),
                            kind: .rectangle(PenNode.RectangleData(
                                width: .fixed(100), height: .fixed(50),
                                fills: .single(.shorthand("red"))
                            ))
                        ),
                    ]))
                ),
            ]
        )
        let editable = EditableDocument(from: doc)
        editable._layoutCache = LayoutCache()
        editable._layoutCache?.store(rects: [:])

        // Simulate remote setNode with only fill change
        let updatedNode = PenNode(
            id: "rect1", common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(100), height: .fixed(50),
                fills: .single(.shorthand("blue"))
            ))
        )
        editable.applyMutation(.setNode(updatedNode))

        let cache = try #require(editable._layoutCache)
        #expect(cache.dirtyRenderNodes.contains("rect1"))
        #expect(!cache.dirtyLayoutNodes.contains("rect1"))
    }
}
