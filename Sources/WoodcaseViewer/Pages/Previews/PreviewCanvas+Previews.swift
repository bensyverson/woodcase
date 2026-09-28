//
//  PreviewCanvas+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension PreviewCanvas {
    /// The page the previews exist for, previewing itself — in both of the shapes it
    /// has.
    static let previews = PreviewComponent(
        slug: "preview-canvas",
        title: "Preview canvas",
        blurb: "One component with every state it declares, stacked: each under its name, with its note, its anchor and its own link.",
        source: "Sources/WoodcaseViewer/Pages/PreviewCanvas.swift",
        states: [
            PreviewState(
                slug: "framed",
                name: "States drawn in their frames",
                note: "The ordinary canvas. Check the rhythm down the page: name, note, permalink, then the framed state — and that the frame's hairline stops where the production surface would, not where the markup happens to end.",
                frame: .page
            ) {
                PreviewCanvas(component: PreviewPageSamples.atom, clock: PreviewFixtures.clock)
            },
            PreviewState(
                slug: "whole-page",
                name: "A whole-page state, linked rather than nested",
                note: "A document cannot nest a document, so a `page` state is a link and a sentence saying why. Look for the sentence: without it the canvas shows a heading and a note with nothing under them, which reads as a component that renders nothing.",
                frame: .page
            ) {
                PreviewCanvas(component: PreviewPageSamples.wholePage, clock: PreviewFixtures.clock)
            },
        ]
    )
}
