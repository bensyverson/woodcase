//
//  ArtboardStepsTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// `‹ n of N ›` — the footer's way to the artboards either side, and what the keyboard's
/// ← and → click.
struct ArtboardStepsTests {
    private let artboards = [
        Artboard(id: "Cnv01", name: "Canvas", x: 0, y: 0, width: 400, height: 300),
        Artboard(id: "Brd01", name: "Board", x: 500, y: 40, width: 200, height: 100),
        Artboard(id: "Cmp01", name: "Component", x: 0, y: 400, width: 60, height: 24),
    ]

    private func steps(current: String, state: ViewState = ViewState()) -> ArtboardSteps {
        ArtboardSteps(file: "a1b2c3", artboards: artboards, current: current, state: state)
    }

    @Test("The middle of the file steps both ways and says where it is")
    func middleStepsBothWays() {
        let control = steps(current: "Brd01")
        #expect(control.index == 1)
        #expect(control.neighbor(.previous)?.id == "Cnv01")
        #expect(control.neighbor(.next)?.id == "Cmp01")

        let html = control.render()
        #expect(html.contains(">2 of 3<"))
        #expect(html.contains("href=\"/files/a1b2c3/artboards/Cnv01\""))
        #expect(html.contains("href=\"/files/a1b2c3/artboards/Cmp01\""))
    }

    @Test("Either end clamps rather than wrapping, and keeps its glyph")
    func endsClamp() {
        #expect(steps(current: "Cnv01").neighbor(.previous) == nil)
        #expect(steps(current: "Cmp01").neighbor(.next) == nil)

        let last = steps(current: "Cmp01").render()
        #expect(last.contains("<span class=\"v-step is-end\" title=\"No next artboard\">›</span>"))
        #expect(last.contains("a class=\"v-step v-step-previous\""))
        #expect(last.contains(">3 of 3<"))
    }

    @Test("A step carries the theme forward but drops the selection it is leaving")
    func stepsCarryTheStateButNotTheSelection() {
        let html = steps(
            current: "Cnv01", state: ViewState(node: "Ttl01", theme: ["Mode": "Dark"])
        ).render()
        #expect(html.contains("/files/a1b2c3/artboards/Brd01?theme=Mode%3ADark"))
        #expect(!html.contains("node=Ttl01"))
    }

    @Test("A step names the artboard it leads to, so an unread dot reaches it")
    func stepsNameTheirArtboard() {
        #expect(steps(current: "Cnv01").render().contains("data-artboard=\"Brd01\""))
    }

    @Test("A file with one artboard renders no steps at all")
    func oneArtboardHasNowhereToStep() {
        let control = ArtboardSteps(
            file: "a1b2c3", artboards: [artboards[0]], current: "Cnv01", state: ViewState()
        )
        #expect(!control.hasSteps)
        #expect(control.render().isEmpty)
    }

    @Test("An artboard the file does not have gets no steps rather than a wrong count")
    func anUnknownCurrentRendersNothing() {
        let control = steps(current: "Nope")
        #expect(control.index == nil)
        #expect(!control.hasSteps)
        #expect(control.render().isEmpty)
    }

    @Test("The keyboard's arrows click these very links, so the two cannot diverge")
    func theKeyboardClicksTheSteps() {
        let script = ViewerScript.javaScript
        #expect(script.contains("a.v-step-previous"))
        #expect(script.contains("a.v-step-next"))
    }
}
