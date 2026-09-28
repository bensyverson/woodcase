//
//  PagePreviewTests.swift
//  WoodcaseViewerTests
//

import Elementary
import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// How the three pages and the render region behave. Their pictures are in the preview catalog.
struct PagePreviewTests {
    private let file = "a1b2c3d4e5f6"

    private var artboard: Artboard {
        Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300)
    }

    /// The file's other artboard, so the footer has somewhere to step to.
    private var neighbour: Artboard {
        Artboard(id: "Brd01", name: "Settings", x: 500, y: 40, width: 400, height: 300)
    }

    private func region(state: ViewState, markers: [EditMarker] = []) -> RenderRegion {
        let layout = PreviewFixtures.layout()
        return RenderRegion(
            file: file,
            artboard: artboard,
            artboards: [artboard, neighbour],
            layout: layout,
            layoutJSON: ArtboardPageBuilder.json(layout),
            state: state,
            markers: markers,
            clock: PreviewFixtures.clock
        )
    }

    @Test("Boxes are placed in layout points; the stylesheet applies the scale")
    func boxesArePlacedInPoints() {
        let html = region(state: ViewState(node: "Ttl01")).render()
        #expect(html.contains("--v-x: 24; --v-y: 20; --v-w: 118; --v-h: 24"))
        #expect(html.contains("--v-art-w: 400; --v-art-h: 300"))
    }

    @Test("The artboard ships at full size; only the script knows the pane")
    func stageShipsAtFullSize() {
        let html = region(state: ViewState()).render()
        #expect(html.contains("--v-scale: 1"))
        #expect(html.contains("data-density=\"0.7\""))
    }

    @Test("The image is laid out in points, so a 2× render is downsampled, not doubled")
    func imageIsLaidOutInPoints() {
        let html = region(state: ViewState()).render()
        #expect(html.contains("width=\"400\""))
        #expect(html.contains("height=\"300\""))
    }

    @Test("A selection is outlined by the server, so it is right with the script off")
    func selectionIsServerRendered() {
        let html = region(state: ViewState(node: "Vr7Kd")).render()
        #expect(html.contains("v-box is-selected"))
        #expect(html.contains(">Dashboard/Cards/Customers<"))
        #expect(html.contains("data-copy=\"Dashboard/Cards/Customers\""))
        #expect(html.contains("partially outside its parent"))
    }

    @Test("With nothing selected the footer says the size and the density, and no more")
    func emptyFooterStatesTheFacts() {
        let html = region(state: ViewState()).render()
        #expect(html.contains("400×300 pt"))
        #expect(html.contains("rendered 0.7×"))
        // The caption that told you to click a node is gone: the outline, the render and
        // the footer all already say it, and it was the only line here that was advice
        // rather than fact.
        #expect(!html.contains("click a node to outline it"))
        #expect(!html.contains("v-selection-hint"))
    }

    @Test("A selected path is isolated so it can be truncated from its front")
    func selectionPathIsIsolatedForTruncation() {
        let html = region(state: ViewState(node: "Vr7Kd")).render()
        #expect(html.contains("<bdi>Dashboard/Cards/Customers</bdi>"))
        #expect(ViewerStylesheet.css.contains(".v-selection-path"))
    }

    @Test("The footer says where in the file this artboard is, and steps either way")
    func footerStepsBetweenArtboards() {
        let html = region(state: ViewState(theme: ["Mode": "Dark"])).render()
        #expect(html.contains(">1 of 2<"))
        #expect(html.contains(
            "class=\"v-step v-step-next\" data-artboard=\"Brd01\" title=\"Next artboard: Settings\""
        ))
        #expect(html.contains("/files/a1b2c3d4e5f6/artboards/Brd01?theme=Mode%3ADark"))
        // The first artboard has nowhere back: the glyph stays so the counter does not
        // shift, but it is not a link.
        #expect(html.contains("<span class=\"v-step is-end\" title=\"No previous artboard\">‹</span>"))
    }

    @Test("An edit marker names the ink its own hue needs, and the tag reads it")
    func editMarkerCarriesItsInk() {
        let marker = EditMarker(
            node: "Ttl01", identities: ["claude-a"], op: .set,
            time: PreviewFixtures.now.addingTimeInterval(-4)
        )
        let html = region(state: ViewState(), markers: [marker]).render()
        // The box writes both properties; the tag's text and its avatars are drawn on
        // that same hue, so all of it pivots together.
        #expect(html.contains("--v-actor: hsl(152 85% 48%); --v-actor-ink: #000000"))
        #expect(ViewerStylesheet.css.contains(".v-edit-tag { background: var(--v-actor, var(--v-accent)); color: var(--v-actor-ink, #FFFFFF); }"))
    }

    @Test("The command block wears a right-edge fade, because it scrolls and never wraps")
    func commandBlockHasAScrollFade() {
        let empty = EmptyPage(logPath: "/Users/ana/.woodcase/activity.jsonl", eventCount: 0, clock: PreviewFixtures.clock).render()
        #expect(empty.contains("v-empty-fade"))
        #expect(empty.contains("v-empty-block"))

        let file = FileEmptyPage(
            file: ViewerFile(url: URL(fileURLWithPath: "/Users/ana/Designs/banking.pen")),
            variables: [], axes: [:], presence: [], state: ViewState(),
            clock: PreviewFixtures.clock
        ).render()
        #expect(file.contains("v-empty-fade"))
        #expect(file.contains("v-empty-block"))

        #expect(ViewerStylesheet.css.contains(".v-empty-fade"))
        // The rule the fade is an affordance for, still standing.
        #expect(ViewerStylesheet.css.contains("overflow-x: auto"))
    }

    @Test("A name path in ?node= selects the same box the id does")
    func selectionAcceptsAPath() {
        let html = region(state: ViewState(node: "Dashboard/Header/Title")).render()
        #expect(html.contains("v-box is-selected"))
    }

    @Test("The layout JSON never carries a raw < that could end its script element")
    func layoutJSONIsScriptSafe() {
        let layout = ArtboardLayout(
            artboard: "Cnv01", width: 10, height: 10, scale: 1, revision: "r",
            nodes: [ArtboardLayout.Node(id: "a", path: "</script>", x: 0, y: 0, width: 1, height: 1)]
        )
        let json = ArtboardPageBuilder.json(layout)
        #expect(!json.contains("<"))
        #expect(json.contains("\\u003C/script>"))
    }

    @Test("The empty file page says which file it is waiting on, so the stream can replace it")
    func fileEmptyPageNamesItsFile() {
        let file = ViewerFile(url: URL(fileURLWithPath: "/Users/ana/Designs/banking.pen"))
        let html = FileEmptyPage(
            file: file,
            variables: [],
            axes: [:],
            presence: [],
            state: ViewState(),
            clock: PreviewFixtures.clock
        ).render()
        #expect(html.contains("data-empty-file=\"\(file.id)\""))
        #expect(html.contains("No artboards yet"))
        // The script turns it into the map the moment a frame lands.
        #expect(ViewerScript.javaScript.contains("data-empty-file"))
    }

    /// The three artboards a real file's map has to draw: a plain frame, a definition,
    /// and an instance under the id-path expansion gives it.
    private var mixedArtboards: [Artboard] {
        [
            artboard,
            Artboard(id: "nSNTs", name: "banking-home", x: 500, y: 0, width: 402, height: 874, isReusable: true),
            Artboard(
                id: "YGJ0d/nSNTs", name: "banking-home / Dark",
                x: 1000, y: 0, width: 402, height: 874, isInstance: true
            ),
        ]
    }

    private func mapPage(state: ViewState = ViewState()) -> MapPage {
        MapPage(
            file: ViewerFile(url: URL(fileURLWithPath: "/Users/ana/Designs/banking.pen")),
            artboards: mixedArtboards,
            revision: "3f2a91c0d4e5b678",
            variables: [
                ViewerVariable(
                    name: "accent", type: .color, value: "#2FBF6F", swatch: "#2FBF6F",
                    lastEditor: "claude-a", lastChange: PreviewFixtures.now.addingTimeInterval(-4)
                ),
            ],
            axes: ["Mode": ["Light", "Dark"]],
            events: [
                PreviewFixtures.event(secondsAgo: 300, identity: "ben", op: .mv, nodes: ["Hdr01"], paths: ["Dashboard/Header"]),
                PreviewFixtures.event(secondsAgo: 4, identity: "claude-a"),
            ],
            presence: [
                PreviewFixtures.identity("claude-a", secondsAgo: 4, events: 12),
                PreviewFixtures.identity("ben", secondsAgo: 300, events: 3),
            ],
            editors: ["nSNTs": ["claude-a"]],
            state: state,
            clock: PreviewFixtures.clock
        )
    }

    @Test("The map marks a definition or instance artboard, not a plain one")
    func theMapCarriesKindMarks() {
        let html = mapPage().render()

        #expect(html.contains("v-kind-component"))
        #expect(html.contains("v-kind-instance"))
        // The first box (`Dashboard`, plain) carries no mark of its own — its label
        // goes straight from the opening tag to the name, with nothing between.
        #expect(html.contains(
            "<span class=\"v-map-label\"><span class=\"v-map-name\">Dashboard</span></span>"
        ))
        #expect(html.contains("href=\"/files/24294ca51a33/artboards/Cnv01\""))
        // An instance's id-path is percent-encoded into one segment, in the box and in
        // the listing row beside it.
        #expect(html.contains("/artboards/YGJ0d%2FnSNTs"))
    }

    @Test("The map page lists the same artboards in the outline, and shows only Activity")
    func theMapPageListsAndWatches() {
        let html = mapPage().render()
        #expect(html.contains("id=\"v-outline\""))
        #expect(html.contains("<h2 class=\"v-panel-title\">Artboards</h2>"))
        #expect(html.contains("class=\"v-row v-artboard-row\""))
        // Details describes a selection and Export writes one artboard; the map has
        // neither, so neither tab is offered — and neither is the code toggle.
        #expect(html.contains(">Activity</a>"))
        #expect(!html.contains(">Details</a>"))
        #expect(!html.contains(">Export</a>"))
        #expect(!html.contains("v-code-toggle"))
        // Following from the map submits back to the map, and drills in on a write.
        #expect(html.contains("action=\"/files/24294ca51a33\""))
    }

    @Test("The trail starts at the file, because the brand is the way back to the root")
    func theTrailStartsAtTheFile() {
        let html = mapPage().render()
        #expect(html.contains("<a class=\"v-brand\" href=\"/\""))
        #expect(!html.contains(">Files</a>"))
        #expect(!html.contains("title=\"Files\""))
    }

    @Test("The artboard page preview's Details tab names the node the rest of the page selects (nqnnV9)")
    func artboardPagePreviewAgreesOnTheSelection() throws {
        let component = try #require(PreviewCatalog.component(slug: "artboard-page"))
        let html = try #require(component.state(slug: "default")).render()
        let details = try #require(html.firstRange(of: #"id="v-details""#))
        let panel = String(html[details.lowerBound...].prefix(4000))
        #expect(!panel.contains("Select a node"))
        #expect(panel.contains("Vr7Kd"))
    }
}
