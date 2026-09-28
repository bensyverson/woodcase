//
//  KeyboardHint+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension KeyboardHint {
    /// The `?` badge and the popover it opens.
    static let previews = PreviewComponent(
        slug: "keyboard-hint",
        title: "Keyboard hint",
        blurb: "The `?` badge in the top bar and the platform popover of shortcuts it opens.",
        source: "Sources/WoodcaseViewer/Components/KeyboardHint.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "The badge and its panel",
                note: "One state, because the open and closed forms are one piece of markup: the panel is always rendered and `popovertarget` opens it, so there is no script and no second state to declare. A picture cannot open a popover, so the frame draws the panel in place under the badge, at rest — in production it floats under the bar's right edge. Read the key table against ``ViewerScript``'s: this component only restates what the script dispatches, and the two drifting apart is the failure it exists to make visible.",
                frame: .topBar
            ) { KeyboardHint() },
        ]
    )
}
