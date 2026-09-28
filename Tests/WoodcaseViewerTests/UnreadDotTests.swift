//
//  UnreadDotTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// The unread dot is drawn by the client and hung on one attribute, so the markup that
/// carries that attribute and the rule that draws the dot are a contract worth pinning.
///
/// It has to be an attribute rather than a class because the map and the artboard listing
/// are fragments: every change replaces them with freshly server-rendered markup that
/// knows nothing about what this browser has read, and the script re-applies the marks
/// after the swap.
struct UnreadDotTests {
    static let artboards: [Artboard] = [
        Artboard(id: "Cnv01", name: "Canvas", width: 400, height: 300),
        Artboard(id: "Brd01", name: "Board", x: 500, width: 200, height: 100),
    ]

    @Test("Every view of an artboard names it, which is what the dot hangs on")
    func everyViewCarriesTheArtboardID() {
        let map = ArtboardMap(
            file: "a1b2c3d4e5f6",
            artboards: Self.artboards,
            state: ViewState()
        ).render()
        #expect(map.contains("data-artboard=\"Cnv01\""))
        #expect(map.contains("data-artboard=\"Brd01\""))

        let listing = ArtboardOutline(
            artboards: Self.artboards,
            revision: "3f2a91c0d4e5b678",
            file: "a1b2c3d4e5f6",
            state: ViewState()
        ).render()
        #expect(listing.contains("data-artboard=\"Cnv01\""))
        #expect(listing.contains("data-artboard=\"Brd01\""))

        let steps = ArtboardSteps(
            file: "a1b2c3d4e5f6", artboards: Self.artboards, current: "Cnv01", state: ViewState()
        ).render()
        #expect(steps.contains("data-artboard=\"Brd01\""), "the step to the next one is a view of it")
    }

    @Test("The stylesheet draws the dot from the attribute, not from a class")
    func stylesheetDrawsFromTheAttribute() {
        #expect(ViewerStylesheet.css.contains("[data-artboard][data-unread=\"1\"]::after"))
    }

    @Test("The way back up carries the dot for the rest of the file")
    func theMapCrumbCarriesTheFileWideDot() {
        // The artboard page has no boxes to mark, so "something changed elsewhere" hangs
        // on the crumb that leads to where it changed.
        #expect(ViewerStylesheet.css.contains(".v-crumb-map[data-unread=\"1\"]::after"))
        #expect(ViewerScript.javaScript.contains("document.querySelector(\".v-crumb-map\")"))
    }

    @Test("The script keys unread state per file and per artboard, and never throws")
    func scriptKeysPerFileAndArtboard() {
        let script = ViewerScript.javaScript
        #expect(script.contains("woodcase.unread:"))
        // Every localStorage touch in the block is guarded: a private window leaves the
        // page dotless rather than broken.
        #expect(script.contains("// ==== BEGIN follow + unread (MehU9)"))
        #expect(script.contains("// ==== END follow + unread (MehU9)"))
    }
}
