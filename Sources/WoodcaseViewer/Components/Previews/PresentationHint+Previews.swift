//
//  PresentationHint+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension PresentationHint {
    /// The way out of presentation mode, said once on the way in.
    static let previews = PreviewComponent(
        slug: "presentation-hint",
        title: "Presentation hint",
        blurb: "The mono pill that flashes once on entering presentation and fades, because presentation hides the control that would have told you how to leave.",
        source: "Sources/WoodcaseViewer/Components/PresentationHint.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "The pill, as it flashes",
                note: "One state: the fade is a CSS transition on the same markup, so there is nothing else to declare. Framed on the canvas because that is what it overlays; the pill is only shown in presentation, which a frame cannot enter, so the frame draws it in place at full opacity — in production it sits fixed near the bottom of the screen. Check that it names *both* keys — `f` and Escape — since a screen with nothing on it makes neither guessable, and that the text is server-rendered: the script only adds and removes the mode, it never writes this sentence.",
                frame: .canvas
            ) { PresentationHint() },
        ]
    )
}
