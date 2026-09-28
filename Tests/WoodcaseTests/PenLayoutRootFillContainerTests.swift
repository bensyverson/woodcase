import Foundation
import Testing
@testable import Woodcase

/// Regression tests for the root-level `fill_container(fallback)` bug.
///
/// When a container node is laid out as a root (no parent available width)
/// and declares `width: fill_container(N)`, the author's intent is "use N
/// as my standalone width." Previously the engine would pick
/// `contentSize` (e.g. just the horizontal padding) whenever that was
/// nonzero, producing a collapsed layout in which `fill_container`
/// descendants resolved to width 0.
@Suite("Root-level fill_container fallback")
struct PenLayoutRootFillContainerTests {
    @Test("Root container with fill_container(W) honors fallback width")
    func rootFillContainerUsesFallback() throws {
        // A frame with fill_container(402) width and fixed height, containing
        // a fill_container child. At root the frame should be 402 wide, and
        // the child should fill it (minus padding).
        let doc = PenDocument(children: [
            PenNode(
                id: "root",
                common: PenNodeCommon(x: .literal(0), y: .literal(0)),
                kind: .frame(PenNode.FrameData(
                    width: .fillContainer(fallback: 402),
                    height: .fixed(95),
                    layout: .horizontal,
                    padding: .uniform(.literal(10)),
                    children: [
                        PenNode(
                            id: "child",
                            common: PenNodeCommon(),
                            kind: .frame(PenNode.FrameData(
                                width: .fillContainer(fallback: nil),
                                height: .fixed(62),
                                children: []
                            ))
                        ),
                    ]
                ))
            ),
        ])

        let rects = PenLayoutEngine.layout(doc)
        let rootRect = try #require(rects["root"])
        #expect(rootRect.width == 402, "Root should be 402 wide, got \(rootRect.width)")
        #expect(rootRect.height == 95)

        let childRect = try #require(rects["child"])
        #expect(
            childRect.width == 382,
            "Child should fill parent minus 2×10 padding (=382), got \(childRect.width)"
        )
    }

    @Test("TabBar component in woodcase-app.pen lays out at 402×95 at root")
    func tabBarAtRootMatchesFallback() throws {
        // Loads the real woodcase-app.pen fixture and expands refs for
        // `.canvas` — this mirrors Penumbra's DocumentPipeline, which keeps
        // component definitions at root so the editor canvas can render
        // them. The TabBar definition (`W9Q7f`) then appears as a bare
        // root-level node whose width is `fill_container(402)`.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("woodcase-app.pen")
        let data = try Data(contentsOf: url)
        let parsed = try PenParser.parse(data)
        let expanded = PenRefExpander.expand(parsed, for: .canvas)
        let doc = PenVariableResolver.resolve(expanded, theme: [:])

        let rects = PenLayoutEngine.layout(doc)

        let tabBar = try #require(rects["W9Q7f"], "TabBar component should have a root rect")
        #expect(tabBar.width == 402, "TabBar width should be 402, got \(tabBar.width)")
        #expect(tabBar.height == 95, "TabBar height should be 95, got \(tabBar.height)")

        let pill = try #require(rects["idAHB"], "Pill should have a rect under TabBar root")
        #expect(pill.width == 360, "Pill width should be 360, got \(pill.width)")
        #expect(pill.height == 62, "Pill height should be 62, got \(pill.height)")

        // All four tabs should be 88×54, distributed with 4px padding inside Pill
        for (id, expectedX) in [
            ("2O5ky", 4.0), ("jRI6G", 92.0), ("MawuA", 180.0), ("o9W4T", 268.0),
        ] {
            let tab = try #require(rects[id], "Tab \(id) should have a rect")
            #expect(tab.width == 88, "Tab \(id) width should be 88, got \(tab.width)")
            #expect(tab.height == 54, "Tab \(id) height should be 54, got \(tab.height)")
            #expect(tab.x == expectedX, "Tab \(id) x should be \(expectedX), got \(tab.x)")
            #expect(tab.y == 4, "Tab \(id) y should be 4, got \(tab.y)")
        }
    }
}
