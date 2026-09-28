//
//  ArtboardOutlineTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// The map page's outline: the same columns a node row has, one level up.
struct ArtboardOutlineTests {
    private let artboards = [
        Artboard(id: "Cnv01", name: "Canvas", x: 0, y: 0, width: 400, height: 300),
        Artboard(id: "nSNTs", name: "banking-home", x: 500, y: 40, width: 402, height: 874, isReusable: true),
        Artboard(id: "YGJ0d/nSNTs", name: nil, x: 1000, y: 0, width: 402, height: 874, isInstance: true),
    ]

    private func outline(state: ViewState = ViewState(), editors: [String: [String]] = [:]) -> ArtboardOutline {
        ArtboardOutline(
            artboards: artboards,
            revision: "3f2a91c0d4e5b678",
            file: "a1b2c3",
            state: state,
            editors: editors
        )
    }

    @Test("It takes the outline's own slot, so one swap target serves both modes")
    func itTakesTheOutlineSlot() {
        let html = outline().render()
        #expect(html.contains("id=\"v-outline\""))
        #expect(html.contains("<h2 class=\"v-panel-title\">Artboards</h2>"))
        #expect(html.contains("rev 3f2a…b678"))
    }

    @Test("A row carries the kind mark, the settled rect and a click-to-copy id")
    func rowsReadLikeNodeRows() {
        let html = outline().render()
        #expect(html.contains("v-kind-component"))
        #expect(html.contains("v-kind-instance"))
        #expect(html.contains("500,40 402×874"), "the rect is where it sits on the canvas")
        #expect(html.contains("data-copy-id=\"Cnv01\""))
        // A plain artboard keeps the frame glyph a node row would give it.
        #expect(html.contains("<span class=\"v-glyph\">⊟</span>"))
    }

    @Test("A row drills in with exactly the link its box on the map carries")
    func rowsDrillIn() {
        let state = ViewState(node: "Ttl01", theme: ["Mode": "Dark"])
        let row = ArtboardRow(artboard: artboards[0], file: "a1b2c3", state: state).render()
        let box = ArtboardMap(file: "a1b2c3", artboards: artboards, state: state).render()
        #expect(row.contains("href=\"/files/a1b2c3/artboards/Cnv01?theme=Mode%3ADark\""))
        #expect(box.contains("href=\"/files/a1b2c3/artboards/Cnv01?theme=Mode%3ADark\""))
        #expect(!row.contains("node=Ttl01"), "the selection belonged to the artboard being left")
    }

    @Test("An unnamed artboard reads as its id marker, id-path and all")
    func unnamedArtboardUsesItsIDMarker() {
        let row = ArtboardRow(artboard: artboards[2], file: "a1b2c3", state: ViewState())
        #expect(row.label == "#YGJ0d/nSNTs")
        #expect(row.render().contains("is-unnamed"))
        #expect(row.render().contains("/artboards/YGJ0d%2FnSNTs"))
    }

    @Test("A recently written artboard carries its first editor's colour and lists them all")
    func touchedRowsCarryColour() {
        let html = outline(editors: ["nSNTs": ["claude-a", "ben"]]).render()
        #expect(html.contains("is-touched"))
        #expect(html.contains("--v-actor: \(ActorColor(name: "claude-a").css)"))
        #expect(html.contains("data-editors=\"claude-a ben\""))
    }

    @Test("A file with nothing to draw says so rather than listing nothing")
    func emptyFileSaysSo() {
        let html = ArtboardOutline(
            artboards: [], revision: "3f2a91c0d4e5b678", file: "a1b2c3", state: ViewState()
        ).render()
        #expect(html.contains("no top-level frames"))
    }
}
