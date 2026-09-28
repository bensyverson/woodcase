//
//  FollowStateTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// Follow is view state, so it round-trips through the query exactly the way the
/// selection and the theme pins do.
struct FollowStateTests {
    @Test("Nobody is the default, and it writes nothing into the query")
    func nobodyIsTheDefault() {
        #expect(ViewState().follow == .nobody)
        #expect(ViewState().query == "")
        #expect(Follow.nobody.query == nil)
    }

    @Test("Following anyone and following one identity each have a spelling")
    func followSpellings() {
        #expect(Follow.following(.anyone).query == "anyone")
        #expect(Follow.following(.identity("ana")).query == "ana")
        #expect(Follow.paused(.anyone).query == "paused:anyone")
        #expect(Follow.paused(.identity("ana")).query == "paused:ana")
    }

    @Test("Every spelling reads back as the value that wrote it")
    func followRoundTrips() {
        for follow: Follow in [
            .nobody,
            .following(.anyone),
            .following(.identity("ana")),
            .paused(.anyone),
            .paused(.identity("ana")),
        ] {
            #expect(Follow.of(follow.query) == follow)
        }
    }

    @Test("An absent, empty or explicit-nobody parameter is nobody")
    func nobodySpellings() {
        #expect(Follow.of(nil) == .nobody)
        #expect(Follow.of("") == .nobody)
        #expect(Follow.of("nobody") == .nobody)
        #expect(Follow.of("paused:") == .nobody)
    }

    @Test("A followed change is one whose identity matches; an unattributed write never is")
    func matching() {
        #expect(Follow.following(.anyone).matches("ana"))
        #expect(Follow.following(.anyone).matches(nil) == false)
        #expect(Follow.following(.identity("ana")).matches("ana"))
        #expect(Follow.following(.identity("ana")).matches("bob") == false)
        #expect(Follow.paused(.identity("ana")).matches("ana") == false)
        #expect(Follow.nobody.matches("ana") == false)
    }

    @Test("Pausing keeps who you were following; resuming puts it back")
    func pauseAndResume() {
        let following = Follow.following(.identity("ana"))
        #expect(following.pausing() == .paused(.identity("ana")))
        #expect(following.pausing().resuming() == following)
        #expect(Follow.nobody.pausing() == .nobody)
        #expect(Follow.nobody.resuming() == .nobody)
    }

    @Test("Follow rides in the query after the selection, theme and depth")
    func followIsLastInTheQuery() {
        let state = ViewState(
            node: "Ttl01",
            theme: ["Mode": "Dark"],
            depth: 3,
            follow: .following(.identity("ana"))
        )
        #expect(state.query == "?node=Ttl01&theme=Mode%3ADark&depth=3&follow=ana&tab=details")
    }

    @Test("A paused follow is escaped into the query and survives a link")
    func pausedFollowInTheQuery() {
        #expect(ViewState(follow: .paused(.identity("ana"))).query == "?follow=paused%3Aana")
        #expect(
            ViewerLink.artboard(file: "a1", artboard: "Cnv01", state: ViewState(follow: .following(.anyone)))
                == "/files/a1/artboards/Cnv01?follow=anyone"
        )
    }

    @Test("A request's follow parameter becomes the state's")
    func readFromARequest() throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        func state(follow: String?) throws -> ViewState {
            try ViewState.of(ViewerRequest(
                http: HTTPRequest(
                    method: .get,
                    path: "/files/a1",
                    query: follow.map { ["follow": $0] } ?? [:],
                    headers: [:],
                    target: "/files/a1"
                ),
                parameters: ["file": "a1"],
                context: ViewerFixtures.context(files: [], home: scratch)
            ))
        }

        #expect(try state(follow: "ana").follow == .following(.identity("ana")))
        #expect(try state(follow: "paused:ana").follow == .paused(.identity("ana")))
        #expect(try state(follow: "anyone").follow == .following(.anyone))
        #expect(try state(follow: nil).follow == .nobody)
    }

    @Test("Changing the follow target keeps everything else you had set")
    func followingKeepsTheRest() {
        let state = ViewState(node: "Ttl01", theme: ["Mode": "Dark"])
        let followed = state.following(.following(.identity("ana")))
        #expect(followed.node == "Ttl01")
        #expect(followed.theme == ["Mode": "Dark"])
        #expect(followed.follow == .following(.identity("ana")))
    }
}
