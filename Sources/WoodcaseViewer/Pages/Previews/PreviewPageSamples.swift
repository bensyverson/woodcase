//
//  PreviewPageSamples.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// The catalog the preview *pages* preview themselves against.
///
/// A fixture, exactly like ``PreviewFixtures``: the prop type is the production one —
/// ``PreviewComponent``, the same value the real catalog holds — but the components are
/// a small fixed pair rather than ``PreviewCatalog/all``.
///
/// Previewing the pages against the live catalog would look more honest and be worse.
/// The index's golden would change every time anybody, anywhere, added a state to any
/// component, so the fixture that is supposed to prove *the index* has not changed
/// would be re-blessed constantly and stop being read. Two components is also the more
/// useful picture: what a reviewer checks on this page is the row — its title, blurb,
/// count and source — not that twenty of them exist.
///
/// The pair is chosen to cover the two branches the pages have: a component whose
/// states are framed (drawn inline on the canvas) and one whose state is a whole page
/// (linked, because a document cannot nest a document).
enum PreviewPageSamples {
    /// An atom with three framed states — the ordinary case.
    static let atom = PreviewComponent(
        slug: "avatar",
        title: "Avatar",
        blurb: "One identity as a coloured disc with its initial — the atom every other identity display is built from.",
        source: "Sources/WoodcaseViewer/Components/AvatarView.swift",
        states: [
            PreviewState(
                slug: "small",
                name: "Small — 15 px",
                note: "The size a table row uses. The initial should sit dead centre.",
                frame: .strip
            ) { AvatarView(identity: "claude-a", size: .small) },
            PreviewState(
                slug: "medium",
                name: "Medium — 20 px",
                note: "The top bar and the expanded presence list. Only the disc grows.",
                frame: .strip
            ) { AvatarView(identity: "claude-a", size: .medium) },
        ]
    )

    /// A whole page, so the canvas's "linked, not nested" branch is in the picture.
    static let wholePage = PreviewComponent(
        slug: "empty-page",
        title: "Empty page",
        blurb: "What the root serves before anything has been edited: the next command, on the page.",
        source: "Sources/WoodcaseViewer/Pages/EmptyPage.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "Nothing served yet",
                note: "A whole page, so it is linked from the canvas rather than drawn in it.",
                frame: .page
            ) {
                EmptyPage(logPath: ".woodcase/activity.jsonl", eventCount: 0, clock: PreviewFixtures.clock)
            },
        ]
    )

    /// The pair, in reading order.
    static let all: [PreviewComponent] = [atom, wholePage]
}
