//
//  MaterializeSnapshotOverlayTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `EditableDocument.materializeSnapshot(overlaying:)`: the tree with some stored nodes
/// swapped for others, as an editor draws a preview, without changing the document.
@MainActor
struct MaterializeSnapshotOverlayTests {
    /// A frame holding a text, and a rectangle beside it.
    private func makeDocument() -> EditableDocument {
        let text = PenNode(id: "text", common: PenNodeCommon(), kind: .text(PenNode.TextData()))
        let frame = PenNode(
            id: "frame",
            common: PenNodeCommon(opacity: .literal(1)),
            kind: .frame(PenNode.FrameData(children: [text]))
        )
        let box = PenNode(id: "box", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        return EditableDocument(from: PenDocument(children: [frame, box]))
    }

    @Test("Overlaying a preview's nodes materializes what committing it would")
    func overlayMatchesCommit() async throws {
        let operations: [EditOperation] = [
            .setProperties(EditOperation.SetProperties(nodeID: "frame", properties: ["common.opacity": .double(0.3)])),
            .setProperties(EditOperation.SetProperties(nodeID: "box", properties: ["kind.width": .double(64)])),
        ]
        let document = makeDocument()
        let overlay = try document.previewNodes(for: operations)
        let previewed = await document.materializeSnapshot(overlaying: overlay)

        let committed = makeDocument()
        for operation in operations {
            try committed.apply(operation)
        }
        #expect(previewed == committed.materialize())
    }

    @Test("An overlaid container keeps its children, even when the overlay carries none")
    func overlayKeepsChildren() async throws {
        let document = makeDocument()
        var frame = try #require(document.nodes["frame"])
        frame.common.opacity = .literal(0.5)
        frame.kind = frame.kind.withEmptyChildren()
        let previewed = await document.materializeSnapshot(overlaying: ["frame": frame])
        let drawn = try #require(previewed.children.first)
        #expect(drawn.common.opacity == .literal(0.5))
        #expect(drawn.kind.inlineChildren.map(\.id) == ["text"])
    }

    @Test("An overlay naming no stored node is ignored, and the document is unchanged")
    func overlayIgnoresUnknownAndMutatesNothing() async throws {
        let document = makeDocument()
        let before = document.materialize()
        let stray = PenNode(id: "stray", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        var box = try #require(document.nodes["box"])
        box.common.name = "Moved"
        let previewed = await document.materializeSnapshot(overlaying: ["stray": stray, "box": box])
        #expect(previewed.children.map(\.id) == ["frame", "box"])
        #expect(previewed.children.last?.common.name == "Moved")
        #expect(document.materialize() == before)
    }
}
