//
//  FileCard+Previews.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

public extension FileCard {
    /// One dashboard card: healthy, fresh, stale, unreadable and empty.
    ///
    /// The three ages here are also where ``RelativeAge``'s long spelling is reviewed —
    /// `just now`, `4 min ago`, `3 days ago` are its boundaries, and a card is the only
    /// production surface that renders them.
    static let previews = PreviewComponent(
        slug: "file-card",
        title: "File card",
        blurb: "One watched document as a card: a real render of its cover artboard, its name and path, its artboard count and its last write.",
        source: "Sources/WoodcaseViewer/Components/FileCard.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "A healthy file, written to four minutes ago",
                note: "The ordinary card. The whole card is the link, because the card *is* the file. The thumbnail is the same warm render pipeline the artboard view reads, capped and lazy, and it keeps its own aspect inside a fixed 144 px box — a grid of cards each sized to its artboard would be a staircase.",
                frame: .body
            ) {
                Self.inTheGrid(FileCard(
                    summary: PreviewFixtures.summary(
                        id: "a1b2c3d4e5f6", name: "banking", artboards: 4,
                        lastChange: FileListReport.LastChange(
                            time: PreviewFixtures.now.addingTimeInterval(-240),
                            identity: "claude-a", op: .set,
                            nodes: ["Ttl01"], paths: ["Dashboard/Header/Title"]
                        )
                    ),
                    clock: PreviewFixtures.clock
                ))
            },
            PreviewState(
                slug: "unattributed",
                name: "Written seconds ago, by nobody",
                note: "Two things at once. The age reads `just now` rather than `4 s ago` — the long spelling's first boundary — and the writer is ``ActivityEvent/unattributed``, a write made with no `--as`, which is a real state and not a missing one: the disc must render `?` titled \"unattributed\", never blank and never a crash.",
                frame: .body
            ) {
                Self.inTheGrid(FileCard(
                    summary: PreviewFixtures.summary(
                        id: "b2c3d4e5f6a1", name: "onboarding", artboards: 7,
                        lastChange: FileListReport.LastChange(
                            time: PreviewFixtures.now.addingTimeInterval(-4),
                            identity: ActivityEvent.unattributed, op: .cp,
                            nodes: [], paths: []
                        )
                    ),
                    clock: PreviewFixtures.clock
                ))
            },
            PreviewState(
                slug: "stale",
                name: "Untouched for three days",
                note: "The far end of the age scale, `3 days ago`. Nothing about the card should shout — a file nobody has touched sorts last on the dashboard rather than being hidden, and its footer is the same weight as everyone else's.",
                frame: .body
            ) {
                Self.inTheGrid(FileCard(
                    summary: PreviewFixtures.summary(
                        id: "c3d4e5f6a1b2", name: "marketing-site", artboards: 2,
                        lastChange: FileListReport.LastChange(
                            time: PreviewFixtures.now.addingTimeInterval(-3 * 86400),
                            identity: "ben", op: .mv,
                            nodes: ["Hero1"], paths: ["Landing/Hero"]
                        )
                    ),
                    clock: PreviewFixtures.clock
                ))
            },
            PreviewState(
                slug: "broken",
                name: "A file that will not parse",
                note: "The card stays and says why, in the space the thumbnail would have filled — a dashboard that silently dropped a broken file would report that everything is fine. No cover, no revision, the card tinted toward warn, and the reason in mono with the full text on hover.",
                frame: .body
            ) {
                Self.inTheGrid(FileCard(
                    summary: PreviewFixtures.summary(
                        id: "d4e5f6a1b2c3", name: "tirekick", artboards: 0,
                        error: "not a .pen document"
                    ),
                    clock: PreviewFixtures.clock
                ))
            },
            PreviewState(
                slug: "empty",
                name: "Parsed fine, but nothing in it yet",
                note: "The state every `woodcase new` passes through. It has a revision, so it is not broken; it has no artboards, so it gets `no artboards` rather than the warn treatment; and it has no log entry, so the footer reads `no changes` quietly instead of naming a time that never happened.",
                frame: .body
            ) {
                Self.inTheGrid(FileCard(
                    summary: PreviewFixtures.summary(
                        id: "e5f6a1b2c3d4", name: "sketch", artboards: 0
                    ),
                    clock: PreviewFixtures.clock
                ))
            },
        ]
    )

    /// One card in the dashboard's own grid, so it is drawn at the width a card has on
    /// the dashboard.
    ///
    /// A card alone is a block as wide as whatever holds it — about 600 px in the render
    /// column it used to be framed on, and wider still in the body — and the fixed 144 px
    /// thumbnail box DESIGN.md defends only reads right at a grid cell's width. The grid
    /// is production markup (`.v-file-cards`), not a preview-shaped stand-in for it.
    ///
    /// - Parameter card: The card.
    /// - Returns: The card in a one-card grid.
    internal static func inTheGrid(_ card: FileCard) -> some HTML & SendableMetatype {
        div(.class("v-file-cards")) { card }
    }
}
