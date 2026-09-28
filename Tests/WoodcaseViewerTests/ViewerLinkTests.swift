//
//  ViewerLinkTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
@testable import WoodcaseViewer

/// Every URL the page writes. The artboard cases are the ones that bite: a top-level
/// component instance expands to an id containing a slash, and a link that does not
/// encode it 404s.
struct ViewerLinkTests {
    @Test("An artboard id containing a slash is percent-encoded into one segment")
    func slashInArtboardIsEncoded() {
        let link = ViewerLink.artboard(file: "a1b2c3", artboard: "YGJ0d/nSNTs", state: ViewState())
        #expect(link == "/files/a1b2c3/artboards/YGJ0d%2FnSNTs")

        let image = ViewerLink.png(file: "a1b2c3", artboard: "YGJ0d/nSNTs", state: ViewState())
        #expect(image == "/files/a1b2c3/artboards/YGJ0d%2FnSNTs.png")
    }

    @Test("View state becomes a query in a fixed order, so a URL is comparable")
    func stateBecomesQuery() {
        var state = ViewState().selecting("Vr7Kd")
        state.theme = ["Mode": "Dark", "Base": "Slate"]
        state.depth = 3
        #expect(
            state.query
                == "?node=Vr7Kd&theme=Base%3ASlate%2CMode%3ADark&depth=3&tab=details"
        )
    }

    @Test("An empty state adds no query at all")
    func emptyStateIsBare() {
        #expect(ViewState().query.isEmpty)
        #expect(ViewerLink.file("a1b2c3", state: ViewState()) == "/files/a1b2c3")
    }

    @Test("Selecting a node keeps everything else in the URL")
    func selectingKeepsTheRest() {
        var state = ViewState()
        state.theme = ["Mode": "Dark"]
        let selected = state.selecting("Ttl01")
        #expect(selected.node == "Ttl01")
        #expect(selected.theme == ["Mode": "Dark"])
        #expect(state.node == nil)
    }

    @Test("Fragment URLs carry the same state as the page they refresh")
    func fragmentsCarryState() {
        let state = ViewState().selecting("Ttl01")
        #expect(
            ViewerLink.fragment(.outline, file: "a1", state: state)
                == "/files/a1/outline?node=Ttl01&tab=details"
        )
        #expect(ViewerLink.fragment(.presence, file: "a1", state: ViewState()) == "/files/a1/presence")
    }

    @Test("The PNG link carries the theme but never the selection")
    func imageIgnoresSelection() {
        var state = ViewState().selecting("Ttl01")
        state.theme = ["Mode": "Dark"]
        #expect(
            ViewerLink.png(file: "a1", artboard: "Cnv01", state: state)
                == "/files/a1/artboards/Cnv01.png?theme=Mode%3ADark"
        )
    }
}
