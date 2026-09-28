//
//  PenLayoutEngineIncrementalTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct PenLayoutEngineIncrementalTests {
    // MARK: - Helpers

    /// Creates a document with 3 independent root frames.
    private func makeThreeRootDocument() -> PenDocument {
        PenDocument(
            version: "1",
            children: [
                PenNode(
                    id: "frame1",
                    common: PenNodeCommon(x: .literal(0), y: .literal(0)),
                    kind: .frame(PenNode.FrameData(
                        width: .fixed(100), height: .fixed(100),
                        fills: .single(.shorthand("red")),
                        children: [
                            PenNode(
                                id: "rect1",
                                common: PenNodeCommon(),
                                kind: .rectangle(PenNode.RectangleData(
                                    width: .fixed(50), height: .fixed(50)
                                ))
                            ),
                        ]
                    ))
                ),
                PenNode(
                    id: "frame2",
                    common: PenNodeCommon(x: .literal(200), y: .literal(0)),
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
                PenNode(
                    id: "frame3",
                    common: PenNodeCommon(x: .literal(500), y: .literal(0)),
                    kind: .frame(PenNode.FrameData(
                        width: .fixed(150), height: .fixed(150),
                        children: [
                            PenNode(
                                id: "rect3",
                                common: PenNodeCommon(),
                                kind: .rectangle(PenNode.RectangleData(
                                    width: .fixed(60), height: .fixed(60)
                                ))
                            ),
                        ]
                    ))
                ),
            ]
        )
    }

    // MARK: - Incremental Layout

    @Test("Clean roots are copied from previous rects")
    func cleanRootsCopied() {
        let doc = makeThreeRootDocument()
        let fullRects = PenLayoutEngine.layout(doc)

        // Only frame2 is dirty — frame1 and frame3 should be copied
        let dirtyNodes: Set = ["rect2", "frame2"]
        let incremental = PenLayoutEngine.layoutIncremental(
            doc,
            previousRects: fullRects,
            dirtyNodeIDs: dirtyNodes
        )

        // Frame1 rects should be identical
        #expect(incremental["frame1"] == fullRects["frame1"])
        #expect(incremental["rect1"] == fullRects["rect1"])

        // Frame3 rects should be identical
        #expect(incremental["frame3"] == fullRects["frame3"])
        #expect(incremental["rect3"] == fullRects["rect3"])

        // Frame2 should also be equal (same doc, just re-computed)
        #expect(incremental["frame2"] == fullRects["frame2"])
        #expect(incremental["rect2"] == fullRects["rect2"])
    }

    @Test("Full invalidation produces same result as full layout")
    func fullInvalidationMatchesFullLayout() {
        let doc = makeThreeRootDocument()
        let fullRects = PenLayoutEngine.layout(doc)

        // All nodes dirty
        let allNodes: Set = ["frame1", "rect1", "frame2", "rect2", "frame3", "rect3"]
        let incremental = PenLayoutEngine.layoutIncremental(
            doc,
            previousRects: fullRects,
            dirtyNodeIDs: allNodes
        )

        #expect(incremental == fullRects)
    }

    @Test("Empty dirty set copies all previous rects")
    func emptyDirtySetCopiesAll() {
        let doc = makeThreeRootDocument()
        let fullRects = PenLayoutEngine.layout(doc)

        let incremental = PenLayoutEngine.layoutIncremental(
            doc,
            previousRects: fullRects,
            dirtyNodeIDs: []
        )

        #expect(incremental == fullRects)
    }

    @Test("Dirty node in one root re-lays out only that root")
    func dirtyNodeInOneRoot() {
        let doc = makeThreeRootDocument()
        let fullRects = PenLayoutEngine.layout(doc)

        // Dirty only rect1 (in frame1) — frame2, frame3 should be unchanged
        let incremental = PenLayoutEngine.layoutIncremental(
            doc,
            previousRects: fullRects,
            dirtyNodeIDs: ["rect1"]
        )

        // All rects should be equal (we didn't change the document)
        for (key, value) in fullRects {
            #expect(incremental[key] == value, "Mismatch for \(key)")
        }
    }
}
