//
//  FollowPicker+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension FollowPicker {
    /// Following nobody, following someone, and paused.
    static let previews = PreviewComponent(
        slug: "follow-picker",
        title: "Follow picker",
        blurb: "Whose edits this page should follow, server-rendered from the log as a plain `GET` form.",
        source: "Sources/WoodcaseViewer/Components/FollowPicker.swift",
        states: [
            PreviewState(
                slug: "nobody",
                name: "Nobody — the default",
                note: "Every identity the log has seen is an option, alongside nobody and anyone. Following nobody offers no resume link at all.",
                frame: .topBar
            ) {
                FollowPicker(
                    identities: [
                        PreviewFixtures.identity("ana", secondsAgo: 4, events: 12),
                        PreviewFixtures.identity("bob", secondsAgo: 900, events: 3),
                    ],
                    state: ViewState(),
                    action: "/files/a1b2c3d4e5f6/artboards/Cnv01"
                )
            },
            PreviewState(
                slug: "ana",
                name: "Following one identity",
                note: "ana is the selected option and the theme pin rides in a hidden field, so following never re-pins the render to the document's default.",
                frame: .topBar
            ) {
                FollowPicker(
                    identities: [
                        PreviewFixtures.identity("ana", secondsAgo: 4, events: 12),
                        PreviewFixtures.identity("bob", secondsAgo: 900, events: 3),
                    ],
                    state: ViewState(theme: ["Mode": "Dark"], follow: .following(.identity("ana"))),
                    action: "/files/a1b2c3d4e5f6/artboards/Cnv01"
                )
            },
            PreviewState(
                slug: "paused",
                name: "Paused, offering to resume",
                note: "Paused by navigating away by hand. The one-click resume names who it resumes — a resume that did not say the name was the state people misread.",
                frame: .topBar
            ) {
                FollowPicker(
                    identities: [
                        PreviewFixtures.identity("ana", secondsAgo: 4, events: 12),
                        PreviewFixtures.identity("bob", secondsAgo: 900, events: 3),
                    ],
                    state: ViewState(follow: .paused(.identity("ana"))),
                    action: "/files/a1b2c3d4e5f6/artboards/Cnv01"
                )
            },
        ]
    )
}
