//
//  FileList+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension FileList {
    /// The dashboard's grid of file cards.
    static let previews = PreviewComponent(
        slug: "file-list",
        title: "File list",
        blurb: "The dashboard's cards: one per watched document, with its cover, its artboard count and its last write.",
        source: "Sources/WoodcaseViewer/Components/FileList.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "Two healthy files and one that will not parse",
                note: "The broken card is the one to look at: no cover, no revision, and the reason said plainly. The footer counts the whole log. Framed as the dashboard's body, which is the surface it sits on in production — not the canvas, which is the render column between the two panes.",
                frame: .body
            ) {
                FileList(
                    files: [
                        PreviewFixtures.summary(
                            id: "a1b2c3d4e5f6", name: "banking", artboards: 4,
                            lastChange: FileListReport.LastChange(
                                time: PreviewFixtures.now.addingTimeInterval(-120),
                                identity: "claude-a", op: .set, nodes: ["Ttl01"], paths: ["Dashboard/Header/Title"]
                            )
                        ),
                        PreviewFixtures.summary(
                            id: "b2c3d4e5f6a1", name: "onboarding", artboards: 7,
                            lastChange: FileListReport.LastChange(
                                time: PreviewFixtures.now.addingTimeInterval(-1080),
                                identity: "claude-b", op: .cp, nodes: [], paths: []
                            )
                        ),
                        PreviewFixtures.summary(id: "c3d4e5f6a1b2", name: "tirekick", artboards: 0, error: "not a .pen document"),
                    ],
                    clock: PreviewFixtures.clock,
                    logPath: ".woodcase/activity.jsonl",
                    eventCount: 1204
                )
            },
        ]
    )
}
