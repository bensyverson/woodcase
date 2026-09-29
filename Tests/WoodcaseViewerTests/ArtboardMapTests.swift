//
//  ArtboardMapTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// Previews and behavior for the bird's-eye artboard map, now a page of its own.
struct ArtboardMapTests {
    /// `batch.pen`'s three roots, at the canvas positions the file gives them.
    private let artboards = [
        Artboard(id: "Cnv01", name: "Canvas", x: 0, y: 0, width: 400, height: 300),
        Artboard(id: "Brd01", name: "Board", x: 500, y: 40, width: 200, height: 100),
        Artboard(id: "Cmp01", name: "Component", x: 0, y: 400, width: 60, height: 24, isReusable: true),
    ]

    private func map(
        state: ViewState = ViewState(),
        editors: [String: [String]] = [:]
    ) -> ArtboardMap {
        ArtboardMap(file: "a1b2c3", artboards: artboards, state: state, editors: editors)
    }

    @Test("Every box is placed at its artboard's settled canvas x and y")
    func boxesSitAtTheirCanvasPositions() {
        let html = map().render()
        #expect(html.contains("--v-board-x: 0; --v-board-y: 0; --v-board-w: 400; --v-board-h: 300"))
        #expect(html.contains("--v-board-x: 500; --v-board-y: 40; --v-board-w: 200; --v-board-h: 100"))
        #expect(html.contains("--v-board-x: 0; --v-board-y: 400; --v-board-w: 60; --v-board-h: 24"))
    }

    @Test("The plane is the union of the artboards, measured from its own corner")
    func thePlaneIsTheUnionOfTheArtboards() {
        let shifted = ArtboardMap(
            file: "a1b2c3",
            artboards: [
                Artboard(id: "Brd01", name: "Board", x: 500, y: 40, width: 200, height: 100),
                Artboard(id: "Far01", name: "Far", x: 900, y: 40, width: 400, height: 300),
            ],
            state: ViewState()
        )
        let html = shifted.render()
        // 500…1300 wide, 40…340 tall — and the left-most artboard is at the corner.
        #expect(html.contains("--v-map-w: 800; --v-map-h: 300"))
        #expect(html.contains("--v-board-x: 0; --v-board-y: 0; --v-board-w: 200; --v-board-h: 100"))
        #expect(html.contains("--v-board-x: 400; --v-board-y: 0; --v-board-w: 400; --v-board-h: 300"))
    }

    @Test("A box names its artboard, carries its kind badge, and names it underneath")
    func boxesCarryTheirIdMarkAndName() {
        let html = map().render()
        #expect(html.contains("data-artboard=\"Cnv01\""))
        #expect(html.contains("title=\"Board\""))
        #expect(html.contains("v-kind-component"), "the reusable root keeps its badge")
        #expect(html.contains("<span class=\"v-map-name\">Component</span>"))
        // The label follows the frame, so the name reads under the render rather than
        // over it.
        #expect(html.contains("</span><span class=\"v-map-label\">"))
    }

    @Test("Every box is a real render, capped small and shared through the render cache")
    func boxesAreThumbnails() {
        let html = map(state: ViewState(theme: ["Mode": "Dark"])).render()
        #expect(html.contains(
            "src=\"/files/a1b2c3/artboards/Cnv01.png?max=\(ArtboardMap.thumbnailEdge)&amp;theme=Mode%3ADark\""
        ))
        // Laid out at the artboard's own point size, so the box and the image are the
        // same rectangle and nothing is letterboxed.
        #expect(html.contains("width=\"200\" height=\"100\""))
        #expect(html.contains("loading=\"lazy\""))
        // Decorative: the name is beside it in the label.
        #expect(html.contains("alt=\"\""))
    }

    @Test("A box carries the view state forward, minus the selection it is leaving")
    func boxesCarryTheStateButNotTheSelection() {
        let html = map(state: ViewState(node: "Ttl01", theme: ["Mode": "Dark"])).render()
        #expect(html.contains("href=\"/files/a1b2c3/artboards/Brd01?theme=Mode%3ADark\""))
        #expect(!html.contains("node=Ttl01"))
    }

    @Test("An artboard written to recently is marked in its editor's color")
    func recentlyEditedArtboardsAreMarked() {
        let html = map(editors: ["Brd01": ["claude-a", "ben"]]).render()
        #expect(html.contains("--v-actor: \(ActorColor(name: "claude-a").css)"))
        #expect(html.contains("data-editors=\"claude-a ben\""))
        // The placement is not lost when the color is added on top of it.
        #expect(html.contains("--v-board-x: 500; --v-board-y: 40; --v-board-w: 200; --v-board-h: 100;"))
    }

    @Test("The map is the page's canvas, and names the file the script needs")
    func theMapIsTheCanvas() {
        let html = map().render()
        #expect(html.contains("id=\"v-map\""))
        #expect(html.contains("data-file=\"a1b2c3\""))
        #expect(!html.contains("is-current"), "nothing is current on the map — it is all of them")
    }

    @Test("A 40 000-point spread holds the minimum zoom rather than shrinking past it")
    func aWideSpreadHoldsTheMinimumZoom() {
        let wide = ArtboardMap.scale(mapWidth: 40300, mapHeight: 424, paneWidth: 760, paneHeight: 560)
        #expect(wide == ArtboardMap.minimumScale)
        // At that zoom a 400-point artboard is still 24 CSS pixels — the smallest box
        // this design draws at all.
        #expect(abs(400 * wide - 24) < 1e-9)

        let close = ArtboardMap.scale(mapWidth: 2000, mapHeight: 1200, paneWidth: 760, paneHeight: 560)
        #expect(close > ArtboardMap.minimumScale)
        #expect(close <= ArtboardMap.maximumScale)

        let tiny = ArtboardMap.scale(mapWidth: 60, mapHeight: 24, paneWidth: 760, paneHeight: 560)
        #expect(tiny == ArtboardMap.maximumScale, "one small artboard is not blown up to fill the pane")
    }

    @Test("The label is dropped, and the name left to the box's title, below 24 points")
    func aTinyBoxKeepsOnlyItsTitle() {
        #expect(ViewerStylesheet.css.contains("@container (max-width: 24px)"))
        #expect(ViewerStylesheet.css.contains(".v-map-label { display: none; }"))
    }

    @Test("The canvas pane is sized by the pane, never by the map's plane")
    func theCanvasNeverGrowsToItsContent() {
        // An implicit `auto` track would size to a 40 000-point plane and stretch the
        // page; both tracks are explicit for that reason, and the map scrolls instead.
        #expect(ViewerStylesheet.css.contains("grid-template-columns: minmax(0, 1fr);"))
        #expect(ViewerStylesheet.css.contains("grid-template-rows: minmax(0, 1fr);"))
    }

    @Test("A hovered box's frame borrows the selected state's color, not one a light artboard swallows")
    func hoverBorrowsTheSelectionColor() {
        // `--v-muted` is a low-contrast gray that disappears against a light thumbnail;
        // `--v-accent` is what the focused (selected) box's own outline uses two lines
        // below, so hover and selection now read as the same color family.
        #expect(!ViewerStylesheet.css.contains(".v-map-board:hover .v-map-frame { border-color: var(--v-muted); }"))
        #expect(ViewerStylesheet.css.contains(".v-map-board:hover .v-map-frame { border-color: var(--v-accent); }"))
        #expect(ViewerStylesheet.css.contains("outline: 2px solid var(--v-accent);"), "the selected state's own color")
    }

    @Test("The map's kind badge is a fixed round bubble around the glyph, not the label pill's padding")
    func mapBadgeIsAFixedRoundBubble() {
        #expect(ViewerStylesheet.css.contains(
            ".v-map-label .v-kind-mark { width: 15px; height: 15px; padding: 0; justify-content: center; }"
        ))
    }

    @Test("The map's kind glyph reads larger than the general pill's 8px, and centers on its own line-height")
    func mapGlyphIsLargerAndCentered() {
        // The nudge is measured, not decorative: with the em box flex-centered the glyph's
        // ink still sat ~1px low and ~0.25px left of the bubble's center (the mono font's
        // baseline placement and asymmetric side bearings), verified against a crosshair
        // overlay at 16x zoom on 2026-08-30.
        #expect(ViewerStylesheet.css.contains(
            ".v-map-label .v-kind-glyph { font-size: 11px; line-height: 1; letter-spacing: 0; transform: translate(0.25px, -1px); }"
        ))
        // The general glyph (outline rows) stays at 8px — unchanged by this override.
        #expect(ViewerStylesheet.css.contains(".v-kind-glyph { font-size: 8px; }"))
    }

    @Test("A box whose thumbnail has not landed reads as loading, not as empty")
    func boxesShimmerUntilTheirThumbnailLands() {
        let html = map().render()
        // The class is on the frame, not the box: `is-touched` already lives on the box
        // and the two say different things.
        #expect(html.contains("<span class=\"v-map-frame is-loading\">"))
        #expect(ViewerStylesheet.css.contains("@keyframes v-shimmer"))
        // A shimmer nobody asked for is motion: it stops for a reader who turned motion off.
        #expect(ViewerStylesheet.css.contains("@media (prefers-reduced-motion: reduce)"))
    }
}
