import CoreGraphics
import Testing
@testable import Woodcase

/// Regression tests for deeply nested documents that would stack-overflow
/// with the old recursive `renderNode` implementation.
///
/// Tests run on `@MainActor` because rendering is a synchronous operation that
/// runs on the caller's thread — in real usage that's the main thread (CLI) or
/// a standard background thread (app), both of which have adequate stack space.
struct PenRendererDeepNestingTests {
    /// Creates a chain of nested frames, `depth` levels deep, with a colored
    /// rectangle at the innermost level.
    private func makeDeepDocument(depth: Int) -> (PenDocument, [String: PenRect]) {
        let leafID = "leaf"
        let leaf = PenNode(
            id: leafID,
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(10),
                height: .fixed(10),
                fills: .single(.shorthand("#FF0000"))
            ))
        )

        var current: PenNode = leaf
        var layoutRects: [String: PenRect] = [
            leafID: PenRect(x: 0, y: 0, width: 10, height: 10),
        ]

        for i in 0 ..< depth {
            let frameID = "frame-\(i)"
            let frame = PenNode(
                id: frameID,
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    width: .fixed(10),
                    height: .fixed(10),
                    children: [current]
                ))
            )
            layoutRects[frameID] = PenRect(x: 0, y: 0, width: 10, height: 10)
            current = frame
        }

        let doc = PenDocument(version: "2.9", children: [current])
        return (doc, layoutRects)
    }

    @Test("Deeply nested frames (500 levels) render without stack overflow")
    @MainActor func deepNestingRendersSuccessfully() {
        let (doc, rects) = makeDeepDocument(depth: 500)
        let image = PenRenderer.render(
            doc, layoutRects: rects,
            size: CGSize(width: 10, height: 10)
        )
        #expect(image != nil, "Rendering 500-deep nested frames should produce an image")
    }

    @Test("Deeply nested frames with clipping render correctly")
    @MainActor func deepNestingWithClipping() {
        let leafID = "leaf"
        let leaf = PenNode(
            id: leafID,
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(10),
                height: .fixed(10),
                fills: .single(.shorthand("#00FF00"))
            ))
        )

        var current: PenNode = leaf
        var layoutRects: [String: PenRect] = [
            leafID: PenRect(x: 0, y: 0, width: 10, height: 10),
        ]

        for i in 0 ..< 500 {
            let frameID = "clip-frame-\(i)"
            let frame = PenNode(
                id: frameID,
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    width: .fixed(10),
                    height: .fixed(10),
                    clip: .literal(true),
                    children: [current]
                ))
            )
            layoutRects[frameID] = PenRect(x: 0, y: 0, width: 10, height: 10)
            current = frame
        }

        let doc = PenDocument(version: "2.9", children: [current])
        let image = PenRenderer.render(
            doc, layoutRects: layoutRects,
            size: CGSize(width: 10, height: 10)
        )
        #expect(image != nil, "Deeply nested clipped frames should render without crashing")
    }
}
