//
//  KindMark+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension KindMark {
    /// Every kind, and the node that is none of them.
    ///
    /// All four cases rather than a representative one: the set is closed and small, and
    /// the mark's job is that the three are told apart at a glance.
    static let previews = PreviewComponent(
        slug: "kind-mark",
        title: "Kind mark",
        blurb: "The component-vocabulary pill: glyph plus word, tinted per kind, on a definition, an instance or a slot.",
        source: "Sources/WoodcaseViewer/Components/KindMark.swift",
        states: [
            PreviewState(
                slug: "component",
                name: "A reusable definition",
                note: "`◈ component`. The pill is its mark color at 12% fill and 45% border — never a flat swatch — and the glyph and the word are both there, because color is never the only carrier.",
                frame: .strip
            ) { KindMark(isReusable: true, isInstance: false, isSlot: false) },
            PreviewState(
                slug: "instance",
                name: "A placed instance",
                note: "`◇ instance`. The hollow diamond against the definition's filled one is the distinction a reader makes most often — is this the real thing or a copy? — so the two glyphs must not read the same at 11 px.",
                frame: .strip
            ) { KindMark(isReusable: false, isInstance: true, isSlot: false) },
            PreviewState(
                slug: "slot",
                name: "A slot frame",
                note: "`▥ slot`. The rarest of the three and the one nobody recognizes cold, which is why it keeps a word even where space is tight.",
                frame: .strip
            ) { KindMark(isReusable: false, isInstance: false, isSlot: true) },
        ]
    )
}
