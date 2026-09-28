//
//  PreviewStatePage+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension PreviewStatePage {
    /// The page a review shot opens, previewing itself.
    static let previews = PreviewComponent(
        slug: "preview-state-page",
        title: "Preview state page",
        blurb: "One state alone, on the URL a review shot opens, with the note that says what to look at.",
        source: "Sources/WoodcaseViewer/Pages/PreviewStatePage.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "One atom, alone",
                note: "This is what a shot in local/viewer-shots/ will look like, chrome and all. The note rides along as the subtitle: a picture sent to a reviewer with no caption asks them to work out what they are looking at.",
                frame: .page
            ) {
                PreviewStatePage(
                    component: PreviewPageSamples.atom,
                    state: PreviewPageSamples.atom.states[0],
                    clock: PreviewFixtures.clock
                )
            },
        ]
    )
}
