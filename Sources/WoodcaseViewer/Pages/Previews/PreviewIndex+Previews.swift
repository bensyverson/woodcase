//
//  PreviewIndex+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension PreviewIndex {
    /// The catalog's own front door, previewing itself.
    ///
    /// Rendered over ``PreviewPageSamples`` rather than the live catalog, so this
    /// golden answers "did the index change?" and not "did anybody add a state?".
    static let previews = PreviewComponent(
        slug: "preview-index",
        title: "Preview index",
        blurb: "The catalog's table of contents: every component with previews, its blurb, its state count and its source file.",
        source: "Sources/WoodcaseViewer/Pages/PreviewIndex.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "Two components",
                note: "The row is the thing to look at: title, then the state count right-aligned, then the blurb and the source path in faint mono under both. The count and the source are what a reader scans; the blurb is what they read once.",
                frame: .page
            ) {
                PreviewIndex(components: PreviewPageSamples.all, clock: PreviewFixtures.clock)
            },
        ]
    )
}
