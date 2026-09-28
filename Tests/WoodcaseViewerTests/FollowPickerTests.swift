//
//  FollowPickerTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// The Follow control: server-rendered from the log, like presence, and a plain `GET`
/// form so it works with the script switched off.
struct FollowPickerTests {
    /// The identities the log has seen, in its order of first appearance.
    static let identities: [ViewerPresence.Identity] = [
        PreviewFixtures.identity("ana", secondsAgo: 4, events: 12),
        PreviewFixtures.identity("bob", secondsAgo: 900, events: 3),
    ]

    @Test("Every identity the log has seen is an option, alongside nobody and anyone")
    func optionPerIdentity() {
        let html = FollowPicker(
            identities: Self.identities,
            state: ViewState(),
            action: "/files/a1/artboards/Cnv01"
        ).render()
        #expect(html.contains(">nobody</option>"))
        #expect(html.contains(">anyone</option>"))
        #expect(html.contains("value=\"ana\""))
        #expect(html.contains("value=\"bob\""))
    }

    @Test("The current target is the selected option")
    func currentTargetIsSelected() {
        let html = FollowPicker(
            identities: Self.identities,
            state: ViewState(follow: .following(.identity("bob"))),
            action: "/files/a1/artboards/Cnv01"
        ).render()
        #expect(html.contains("<option value=\"bob\" selected>bob</option>"))
    }

    @Test("A paused control offers a one-click resume that names who it resumes")
    func pausedOffersResume() {
        let html = FollowPicker(
            identities: Self.identities,
            state: ViewState(theme: ["Mode": "Dark"], follow: .paused(.identity("ana"))),
            action: "/files/a1/artboards/Cnv01"
        ).render()
        #expect(html.contains("resume following ana"))
        // The resume link carries the theme forward: resuming must never re-pin the
        // render to the document's default.
        #expect(html.contains("href=\"/files/a1/artboards/Cnv01?theme=Mode%3ADark&amp;follow=ana\""))
    }

    @Test("Following nobody offers no resume at all")
    func nobodyOffersNoResume() {
        let html = FollowPicker(
            identities: Self.identities,
            state: ViewState(),
            action: "/files/a1/artboards/Cnv01"
        ).render()
        #expect(html.contains("v-follow-resume") == false)
    }

    @Test("The form carries the rest of the view state as hidden fields")
    func formCarriesTheViewState() {
        let html = FollowPicker(
            identities: Self.identities,
            state: ViewState(node: "Ttl01", theme: ["Mode": "Dark"], depth: 3),
            action: "/files/a1/artboards/Cnv01"
        ).render()
        #expect(html.contains("<input type=\"hidden\" name=\"node\" value=\"Ttl01\">"))
        #expect(html.contains("<input type=\"hidden\" name=\"theme\" value=\"Mode:Dark\">"))
        #expect(html.contains("<input type=\"hidden\" name=\"depth\" value=\"3\">"))
    }

    @Test("The control is the element the follow fragment replaces")
    func isTheFragmentTarget() {
        let html = FollowPicker(
            identities: [],
            state: ViewState(),
            action: "/files/a1/artboards/Cnv01"
        ).render()
        #expect(html.contains("id=\"v-follow\""))
        #expect(ViewerLink.Fragment.follow.target == "v-follow")
        #expect(
            ViewerLink.follow(file: "a1", artboard: "YGJ0d/nSNTs", state: ViewState())
                == "/files/a1/artboards/YGJ0d%2FnSNTs/follow"
        )
    }

    @Test("An identity the log has not seen yet is still an option, and still selected")
    func offersAnUnseenIdentity() {
        // A page opened before that agent's first write, or a link pasted from another
        // session: the control must not quietly read as nobody while the page follows.
        let html = FollowPicker(
            identities: [],
            state: ViewState(follow: .following(.identity("ana"))),
            action: "/files/a1/artboards/Cnv01"
        ).render()
        #expect(html.contains("<option value=\"ana\" selected>ana</option>"))
    }

    @Test("The follow control is served as a fragment of its own")
    func fragmentIsRouted() {
        let patterns = ViewerPages.routes().routes.map(\.pattern)
        #expect(patterns.contains("/files/{file}/artboards/{artboard}/follow"))
    }

    @Test("A theme change keeps the follow you had set")
    func themePickerCarriesFollow() {
        let html = ThemePicker(
            axes: ["Mode": ["Light", "Dark"]],
            state: ViewState(follow: .following(.identity("ana"))),
            action: "/files/a1/artboards/Cnv01"
        ).render()
        #expect(html.contains("<input type=\"hidden\" name=\"follow\" value=\"ana\">"))
    }

    @Test("The top bar shows the control on a file's page and not on the dashboard")
    func topBarShowsItOnlyWithAFile() {
        let dashboard = TopBar(
            crumbs: [],
            presence: Self.identities,
            clock: PreviewFixtures.clock,
            subject: .files
        ).render()
        #expect(dashboard.contains("v-follow") == false)

        let artboard = TopBar(
            crumbs: [TopBar.Crumb(label: "banking")],
            presence: Self.identities,
            clock: PreviewFixtures.clock,
            state: ViewState(),
            action: "/files/a1/artboards/Cnv01",
            subject: .artboard
        ).render()
        #expect(artboard.contains("id=\"v-follow\""))
    }
}
