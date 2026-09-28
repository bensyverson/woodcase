//
//  ActivityPreviewTests.swift
//  WoodcaseViewerTests
//

import Elementary
import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// How the activity feed and its edit markers behave. Its pictures are in the preview catalog.
struct ActivityPreviewTests {
    @Test("A row is one line: time, identity, verb, path")
    func rowIsColumnar() {
        let html = ActivityRow(event: PreviewFixtures.event(secondsAgo: 60), clock: PreviewFixtures.clock).render()
        #expect(html.contains(">06:12<"))
        #expect(html.contains(">set<"))
        #expect(html.contains(">Dashboard/Header/Title<"))
    }

    @Test("Extra touched nodes are counted, not wrapped onto a second line")
    func extraPathsAreCounted() {
        let row = ActivityRow(
            event: PreviewFixtures.event(
                secondsAgo: 5,
                nodes: ["a", "b", "c"],
                paths: ["Dashboard/One", "Dashboard/Two", "Dashboard/Three"]
            ),
            clock: PreviewFixtures.clock
        )
        #expect(row.summaryText == "Dashboard/One +2")
    }

    @Test("An event that touched no node says how many operations it carried")
    func nodelessEventCountsOperations() {
        let row = ActivityRow(
            event: PreviewFixtures.event(secondsAgo: 5, op: .var, nodes: [], paths: []),
            clock: PreviewFixtures.clock
        )
        #expect(row.summaryText == "0 ops")
    }

    @Test("The dashboard's rows name their file; a single file's rows do not")
    func fileNameIsScoped() {
        let event = PreviewFixtures.event(secondsAgo: 5)
        #expect(ActivityRow(event: event, clock: PreviewFixtures.clock, showsFile: true)
            .summaryText == "banking · Dashboard/Header/Title")
        #expect(ActivityRow(event: event, clock: PreviewFixtures.clock)
            .summaryText == "Dashboard/Header/Title")
    }

    @Test("The feed reads newest first and stops at its limit")
    func feedIsNewestFirstAndCapped() {
        let feed = ActivityFeed(
            events: (0 ..< 10).map { PreviewFixtures.event(secondsAgo: Double(10 - $0) * 60, nodes: ["n\($0)"], paths: ["P\($0)"]) },
            clock: PreviewFixtures.clock,
            scope: "this file",
            limit: 3
        )
        #expect(feed.visible.count == 3)
        #expect(feed.visible.first?.paths == ["P9"])
    }

    @Test("Two identities touching one node share one marker that names both")
    func markersMergeIdentities() {
        let markers = EditMarker.markers(
            in: [
                PreviewFixtures.event(secondsAgo: 9, identity: "claude-a", nodes: ["Ttl01"]),
                PreviewFixtures.event(secondsAgo: 4, identity: "ben", nodes: ["Ttl01"]),
            ],
            clock: PreviewFixtures.clock
        )
        #expect(markers.count == 1)
        #expect(markers[0].identities == ["claude-a", "ben"])
        #expect(markers[0].op == .set)
        #expect(markers[0].color.name == "claude-a")
    }

    @Test("An edit older than the recency window is not a marker")
    func staleEditsAreNotMarkers() {
        let markers = EditMarker.markers(
            in: [PreviewFixtures.event(secondsAgo: 120, nodes: ["Ttl01"])],
            clock: PreviewFixtures.clock
        )
        #expect(markers.isEmpty)
    }

    @Test("An unattributed write fills the identity column with the word, not a hole (JFazoq)")
    func unattributedRowSaysSo() {
        let html = ActivityRow(
            event: PreviewFixtures.event(secondsAgo: 4, identity: ActivityEvent.unattributed),
            clock: PreviewFixtures.clock
        ).render()
        #expect(html.contains(#"<span class="v-activity-identity is-unattributed">unattributed</span>"#))
    }

    @Test("The path column is an isolate the stylesheet truncates from the front (eJcZJU)")
    func pathColumnIsAnIsolate() {
        let html = ActivityRow(event: PreviewFixtures.event(secondsAgo: 4), clock: PreviewFixtures.clock).render()
        #expect(html.contains(#"<span class="v-activity-path"><bdi>Dashboard/Header/Title</bdi></span>"#))
    }
}
