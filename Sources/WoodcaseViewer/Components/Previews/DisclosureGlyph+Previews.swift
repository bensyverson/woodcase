//
//  DisclosureGlyph+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension DisclosureGlyph {
    /// The one expand/collapse triangle, in the one orientation it is drawn in.
    static let previews = PreviewComponent(
        slug: "disclosure-glyph",
        title: "Disclosure glyph",
        blurb: "The single shared SVG triangle behind every expand/collapse control in the viewer.",
        source: "Sources/WoodcaseViewer/Components/DisclosureGlyph.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "Pointing down — the open orientation",
                note: "One state, because the component has one: it always ships pointing down and each caller rotates it in CSS from its own open state. Look at the box around it — the visible triangle is a few pixels, the click target is 18 px — and at `currentColor`, which is what lets it sit in a header and in a row without a color of its own. There is no second disclosure control anywhere; if this one looks wrong, everything that discloses is wrong.",
                frame: .strip
            ) { DisclosureGlyph() },
        ]
    )
}
