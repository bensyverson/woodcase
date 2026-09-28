//
//  PreviewFrameBoxTests.swift
//  WoodcaseViewerTests
//

import Elementary
import Foundation
import Testing
@testable import WoodcaseViewer

/// The frame a preview state is drawn in: its surface, and — for a state that exists to
/// show what a component does in a narrower pane — the width it is pinned at.
struct PreviewFrameBoxTests {
    @Test("A state with no pinned width is drawn at its surface's own width")
    func unpinnedStateCarriesNoWidth() {
        let state = PreviewState(slug: "plain", name: "Plain", note: "A note.", frame: .canvas) {
            span { "x" }
        }
        #expect(state.pinnedWidth == nil)
        #expect(PreviewFrameBox(state: state).render()
            == #"<div class="v-preview-frame" data-frame="canvas"><span>x</span></div>"#)
    }

    @Test("A pinned state keeps its surface and is held at the width it names")
    func pinnedStateCarriesItsWidth() {
        let state = PreviewState(
            slug: "narrow", name: "Narrow", note: "A note.", frame: .canvas, pinnedWidth: 520
        ) { span { "x" } }
        #expect(state.pinnedWidth == 520)
        #expect(state.metadata.pinnedWidth == 520)
        #expect(PreviewFrameBox(state: state).render()
            == #"<div class="v-preview-frame" data-frame="canvas" style="width: 520px"><span>x</span></div>"#)
    }

    @Test("The selection bar has a state pinned below its 560 px shed, on the render column (4GVELx)")
    func selectionBarHasANarrowState() throws {
        let state = try #require(SelectionBar.previews.states.first { $0.slug == "narrow-pane" })
        #expect(state.frame == .canvas)
        let width = try #require(state.pinnedWidth)
        #expect(width < 560)
        // A path long enough that it truncates even once the rect and revision are gone.
        #expect(state.render().contains("Home — Collection (Light)"))
    }
}
