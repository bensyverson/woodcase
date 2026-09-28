//
//  AvatarPreviewTests.swift
//  WoodcaseViewerTests
//

import Elementary
import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// How the identity primitives behave. Their pictures are in the preview catalog.
struct AvatarPreviewTests {
    @Test("An avatar carries the hashed colour as a custom property, never as a class")
    func avatarCarriesCustomProperty() {
        let html = AvatarView(identity: "claude-a").render()
        #expect(html.contains("--v-actor: hsl(152 85% 48%)"))
        #expect(html.contains("data-identity=\"claude-a\""))
        #expect(html.contains(">C<"))
    }

    @Test("An avatar carries the ink its own colour needs, beside the colour")
    func avatarCarriesItsInk() {
        // A bright disc and a dark one, so the pair proves the property pivots rather
        // than being written once and copied.
        #expect(AvatarView(identity: "claude-a").render().contains("--v-actor-ink: #000000"))
        #expect(AvatarView(identity: "claude-b").render().contains("--v-actor-ink: #FFFFFF"))
    }

    @Test("The stylesheet takes the initial's colour from that property, not from white")
    func avatarInkComesFromTheProperty() {
        #expect(ViewerStylesheet.css.contains("color: var(--v-actor-ink, #FFFFFF)"))
        // The `+N` disc is filled with `faint`, not a hashed hue, so it names its own.
        #expect(ViewerStylesheet.css.contains("--v-faint-ink"))
    }

    @Test("An unattributed write still draws a disc, titled so")
    func unattributedIsTitled() {
        let html = AvatarView(identity: "").render()
        #expect(html.contains("title=\"unattributed\""))
        #expect(html.contains(">?<"))
    }

    @Test("Four identities stack as three discs and a +1")
    func stackCapsAtThree() {
        let stack = PresenceStack(
            identities: ["claude-a", "ben", "claude-b", "ana"].map {
                PreviewFixtures.identity($0, secondsAgo: 10)
            },
            clock: PreviewFixtures.clock
        )
        #expect(stack.shown.count == 3)
        #expect(stack.hidden == 1)
        #expect(stack.render().contains(">+1<"))
    }

    @Test("The bar names whoever wrote most recently inside the recency window")
    func namesTheEditor() {
        let stack = PresenceStack(
            identities: [
                PreviewFixtures.identity("claude-a", secondsAgo: 400),
                PreviewFixtures.identity("ben", secondsAgo: 4),
            ],
            clock: PreviewFixtures.clock
        )
        #expect(stack.editing?.name == "ben")
        // The handle is an `--as` address, not a name, so it gets its own element and
        // the mono the activity row already gives it (DESIGN.md, Typography).
        #expect(stack.render().contains(#"2 active · <span class="v-presence-name">ben</span> editing"#))
    }

    @Test("The presence handle is set in mono, in the summary and in the list alike")
    func presenceHandleIsMono() {
        #expect(ViewerStylesheet.css.contains(".v-presence-name { font-family: var(--v-mono);"))
    }

    @Test("Nobody inside the window means no claim that anyone is editing")
    func quietStackMakesNoClaim() {
        let stack = PresenceStack(
            identities: [PreviewFixtures.identity("claude-a", secondsAgo: 4000)],
            clock: PreviewFixtures.clock
        )
        #expect(stack.editing == nil)
        #expect(stack.render().contains(">1 active<"))
    }

    @Test("Each avatar size's state names the size the stylesheet draws (kB57Fs)",
          arguments: ["small", "medium", "large"])
    func stateNameQuotesTheDrawnSize(size: String) throws {
        let pattern = try Regex(#"\.v-avatar-"# + size + #" \{ width: (\d+)px"#)
        let match = try #require(ViewerStylesheet.css.firstMatch(of: pattern))
        let drawn = try #require(match.output[1].substring)
        let component = try #require(PreviewCatalog.component(slug: "avatar"))
        let state = try #require(component.state(slug: size))
        #expect(state.name.contains("\(drawn) px"), "\(state.name) but the disc is \(drawn) px")
    }
}
