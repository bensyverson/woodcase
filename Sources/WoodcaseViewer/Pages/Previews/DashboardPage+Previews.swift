//
//  DashboardPage+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension DashboardPage {
    /// The landing page, with two files and a live log.
    static let previews = PreviewComponent(
        slug: "dashboard-page",
        title: "Dashboard page",
        blurb: "The root: every watched file as a card, with the activity feed and presence beside them.",
        source: "Sources/WoodcaseViewer/Pages/DashboardPage.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "Two files, two writers",
                note: "A whole page, so the chrome, the stylesheet and the script are the real ones. The feed's rows name their file here; a single file's page does not.",
                frame: .page
            ) {
                DashboardPage(
                    files: [
                        PreviewFixtures.summary(
                            id: "a1b2c3d4e5f6", name: "banking", artboards: 4,
                            lastChange: FileListReport.LastChange(
                                time: PreviewFixtures.now.addingTimeInterval(-120),
                                identity: "claude-a", op: .set, nodes: ["Ttl01"], paths: ["Dashboard/Header/Title"]
                            )
                        ),
                        PreviewFixtures.summary(id: "b2c3d4e5f6a1", name: "onboarding", artboards: 7),
                    ],
                    events: [
                        PreviewFixtures.event(secondsAgo: 600, identity: "ben", op: .mv, nodes: ["Cht01"], paths: ["Dashboard/Chart"]),
                        PreviewFixtures.event(secondsAgo: 4, identity: "claude-a"),
                    ],
                    presence: [
                        PreviewFixtures.identity("claude-a", secondsAgo: 4, events: 12),
                        PreviewFixtures.identity("ben", secondsAgo: 600, events: 3),
                    ],
                    clock: PreviewFixtures.clock,
                    logPath: ".woodcase/activity.jsonl"
                )
            },
        ]
    )
}
