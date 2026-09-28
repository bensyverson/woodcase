//
//  PaneGrip+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension PaneGrip {
    /// The seam, at natural size.
    ///
    /// Framed as a `strip` rather than in a pane. The grip has no content of its own —
    /// it is a six-pixel band with a hairline down the middle — so what a reviewer needs
    /// to check is the band's own width, its cursor and its `role`, and a strip shows
    /// those at natural size. Dropped into `leftPane` it would render as an empty column
    /// and say less, not more.
    ///
    /// There was a second state, `rows`, for the horizontal seam. It was dropped on
    /// Ben's ruling of 2026-09-02: it drew the same band as this one, and the only thing
    /// it varied — `data-axis`, `data-edge`, `aria-orientation` — is a markup fact that
    /// a picture cannot grade. The horizontal seam is still rendered, and still golden,
    /// inside the two pages that have one: `artboard-page` and `map-page`.
    static let previews = PreviewComponent(
        slug: "pane-grip",
        title: "Pane grip",
        blurb: "The draggable seam between two panes: one custom property written on the parent, and the grid does the rest.",
        source: "Sources/WoodcaseViewer/Components/PaneGrip.swift",
        states: [
            PreviewState(
                slug: "columns",
                name: "A vertical seam sizing the column before it",
                note: "The outline's edge. `data-axis=\"x\"` and `data-edge=\"before\"` are what decide which way a drag runs — widening the left column means dragging right — and `aria-orientation` is `vertical`. A grip that reads `before` while sizing the track after it drags backwards, which is the bug this pair of attributes exists to prevent.",
                frame: .strip
            ) {
                PaneGrip(
                    name: "left", property: "--v-col-left", axis: .columns, edge: .before
                )
            },
        ]
    )
}
