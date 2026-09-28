//
//  EmptyPage+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension EmptyPage {
    /// `woodcase serve` with nothing to serve yet.
    static let previews = PreviewComponent(
        slug: "empty-page",
        title: "Empty page",
        blurb: "What the viewer shows when it is watching a log but no file has appeared.",
        source: "Sources/WoodcaseViewer/Pages/EmptyPage.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "Watching, nothing yet",
                note: "The first thing a new user sees. It has to name the log it is watching and say the count is zero, or an empty viewer reads as a broken one.",
                frame: .page
            ) {
                EmptyPage(logPath: ".woodcase/activity.jsonl", eventCount: 0, clock: PreviewFixtures.clock)
            },
        ]
    )
}
