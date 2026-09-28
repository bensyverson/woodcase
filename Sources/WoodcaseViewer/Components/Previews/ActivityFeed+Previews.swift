//
//  ActivityFeed+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension ActivityFeed {
    /// What the log has seen: five writes, and nothing at all.
    static let previews = PreviewComponent(
        slug: "activity-feed",
        title: "Activity feed",
        blurb: "The activity log as one line per write — time, identity, verb, path — newest first.",
        source: "Sources/WoodcaseViewer/Components/ActivityFeed.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "Five writes by three identities",
                note: "One verb of each shape: an undo that touched no node, a copy, a remove, a move and a set. The columns must stay aligned and no row may wrap.",
                frame: .rightPane
            ) {
                ActivityFeed(
                    events: [
                        PreviewFixtures.event(secondsAgo: 3000, identity: "ben", op: .undo, nodes: [], paths: []),
                        PreviewFixtures.event(secondsAgo: 1400, identity: "claude-a", op: .cp, nodes: ["Crd01"], paths: ["Dashboard/Cards"]),
                        PreviewFixtures.event(secondsAgo: 660, identity: "claude-b", op: .rm, nodes: ["Ftr01"], paths: ["Dashboard/Footer"]),
                        PreviewFixtures.event(secondsAgo: 240, identity: "ben", op: .mv, nodes: ["Cht01"], paths: ["Dashboard/Chart"]),
                        PreviewFixtures.event(secondsAgo: 4, identity: "claude-a"),
                    ],
                    clock: PreviewFixtures.clock,
                    scope: "this file · all identities"
                )
            },
            PreviewState(
                slug: "empty",
                name: "Nothing in it",
                note: "A log with no events yet. The scope line still says what it is watching, so an empty feed reads as quiet rather than as unwired.",
                frame: .rightPane
            ) {
                ActivityFeed(events: [], clock: PreviewFixtures.clock, scope: "all files")
            },
        ]
    )
}
