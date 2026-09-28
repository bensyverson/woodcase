//
//  PresenceStack+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension PresenceStack {
    /// Who is here: nobody, a pair, and more than the stack can draw.
    static let previews = PreviewComponent(
        slug: "presence-stack",
        title: "Presence stack",
        blurb: "The identities the activity log has seen, as overlapping discs with a summary line.",
        source: "Sources/WoodcaseViewer/Components/PresenceStack.swift",
        states: [
            PreviewState(
                slug: "empty",
                name: "Nobody",
                note: "No identities at all. It must take no space and make no claim — an empty stack that still said '0 active' read as a broken counter.",
                frame: .strip
            ) { PresenceStack(identities: [], clock: PreviewFixtures.clock) },
            PreviewState(
                slug: "pair",
                name: "Two identities, one editing",
                note: "claude-a wrote four seconds ago and ben fifteen minutes ago: the summary names the recent one as editing, and only the recent one.",
                frame: .strip
            ) {
                PresenceStack(
                    identities: [
                        PreviewFixtures.identity("claude-a", secondsAgo: 4, events: 12),
                        PreviewFixtures.identity("ben", secondsAgo: 900, events: 3),
                    ],
                    clock: PreviewFixtures.clock
                )
            },
            PreviewState(
                slug: "overflow",
                name: "Five identities, capped at three",
                note: "The stack draws three discs and a +2. Watch the 7 px overlap and the 2 px chrome ring: the counter must sit on the same baseline as the discs.",
                frame: .strip
            ) {
                PresenceStack(
                    identities: ["claude-a", "ben", "claude-b", "ana", "pager"].map {
                        PreviewFixtures.identity($0, secondsAgo: 20)
                    },
                    clock: PreviewFixtures.clock
                )
            },
            PreviewState(
                slug: "unattributed",
                name: "One of them is nobody",
                note: "A write made with no `--as` and no `$WOODCASE_AS` is logged like any other and names ``ActivityEvent/unattributed`` — the empty string. Its disc must read `?`, titled \"unattributed\", and take its place in the stack: a real state, not a rendering bug, and the summary line must not say a blank name is editing.",
                frame: .strip
            ) {
                PresenceStack(
                    identities: [
                        PreviewFixtures.identity(ActivityEvent.unattributed, secondsAgo: 6, events: 1),
                        PreviewFixtures.identity("claude-a", secondsAgo: 900, events: 12),
                    ],
                    clock: PreviewFixtures.clock
                )
            },
        ]
    )
}
