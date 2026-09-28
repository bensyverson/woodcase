//
//  PreviewStatePageTests.swift
//  WoodcaseViewerTests
//

import Elementary
import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// The pages the catalog is served on: what their chrome carries, and how a caption is
/// written onto them.
struct PreviewStatePageTests {
    /// Every framed state in the catalog, as the page that serves it alone.
    static var framedStates: [String] {
        PreviewCatalog.all.flatMap { component in
            component.states.filter { $0.frame != .page }.map { "\(component.slug)/\($0.slug)" }
        }
    }

    /// The page for a `component/state` path.
    static func page(_ path: String) throws -> String {
        let parts = path.split(separator: "/").map(String.init)
        let component = try #require(PreviewCatalog.component(slug: parts[0]))
        let state = try #require(component.state(slug: parts[1]))
        return PreviewStatePage(component: component, state: state, clock: PreviewFixtures.clock).render()
    }

    @Test("A state's own page carries every id once, so the script drives the state and not the chrome (teQIgm)",
          arguments: framedStates)
    func everyIDOnce(path: String) throws {
        let html = try Self.page(path)
        var seen: [String: Int] = [:]
        for match in html.matches(of: /\sid="([^"]+)"/) {
            seen[String(match.output.1), default: 0] += 1
        }
        let doubled = seen.filter { $0.value > 1 }.keys.sorted()
        #expect(doubled.isEmpty, "\(path) repeats \(doubled)")
    }

    @Test("The catalog's own chrome is a trail and nothing else: no badge, presence or keys")
    func chromeCarriesNoLiveControls() throws {
        let pages = try [
            PreviewIndex(components: PreviewCatalog.all, clock: PreviewFixtures.clock).render(),
            PreviewCanvas(component: #require(PreviewCatalog.component(slug: "avatar")), clock: PreviewFixtures.clock).render(),
            Self.page("avatar/small"),
        ]
        for html in pages {
            #expect(!html.contains("id=\"v-live\""))
            #expect(!html.contains("id=\"v-presence\""))
            #expect(!html.contains("popovertarget"))
        }
    }

    @Test("A state page's caption is its note rendered as prose, not its source")
    func captionIsRenderedProse() throws {
        let component = try #require(PreviewCatalog.component(slug: "avatar"))
        let state = try #require(component.state(slug: "unattributed"))
        let html = PreviewStatePage(component: component, state: state, clock: PreviewFixtures.clock).render()
        #expect(html.contains(PreviewProse(state.note).render()))
        #expect(!html.contains("``"))

        let canvas = PreviewCanvas(component: component, clock: PreviewFixtures.clock).render()
        #expect(canvas.contains(PreviewProse(state.note).render()))
        #expect(!canvas.contains("``"))
    }
}
