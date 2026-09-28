//
//  IdChip+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension IdChip {
    /// The click-to-copy id: at rest, and mid-copy.
    ///
    /// There was a third, `outline`, showing the chip wearing a caller's extra class. It
    /// was dropped on Ben's ruling of 2026-09-02: what it asserts is that a class is
    /// merged rather than replaced, and beside the plain chip it drew an identical
    /// picture. A markup fact needs a markup test, not a picture — `OutlinePreviewTests`
    /// holds it.
    static let previews = PreviewComponent(
        slug: "id-chip",
        title: "Id chip",
        blurb: "A node's 5-character id as a mono chip that copies itself when clicked — the handoff point to an agent.",
        source: "Sources/WoodcaseViewer/Components/IdChip.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "At rest",
                note: "The ordinary chip. `data-copy-id` carries the id the script copies, so a chip whose text is later replaced still copies the right thing, and the hover says what a click will do.",
                frame: .strip
            ) { IdChip(id: "ALu8G") },
            PreviewState(
                slug: "copied",
                name: "Just copied",
                note: "The 1.2 s flash after a successful copy, declared by setting exactly what ``ViewerScript`` sets: the `is-copied` class, and nothing else — both words are server-rendered and the class decides which shows. Look at the accent fill and white ink — allowed because it is a flash, the one place white on the accent is — and at the chip keeping exactly its resting width: `copied` is laid over the id, never swapped in for it.",
                frame: .strip
            ) { IdChip(id: "ALu8G", copied: true) },
        ]
    )
}
