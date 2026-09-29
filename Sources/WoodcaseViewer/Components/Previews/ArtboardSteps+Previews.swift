//
//  ArtboardSteps+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension ArtboardSteps {
    /// `‹ 2 of 5 ›`, in the middle of a file, at its end, and in a file with nowhere to go.
    static let previews = PreviewComponent(
        slug: "artboard-steps",
        title: "Artboard steps",
        blurb: "Where in the file this artboard is, and the two links to the ones either side of it.",
        source: "Sources/WoodcaseViewer/Components/ArtboardSteps.swift",
        states: [
            PreviewState(
                slug: "middle",
                name: "Two of five",
                note: "Both arrows are real links carrying the whole view state, which is what makes stepping work with the script off and what lets the keyboard implement ← and → by clicking them rather than re-deriving the order. Each carries `data-artboard`, so an unread neighbor shows its dot on the arrow that leads to it.",
                frame: .canvas
            ) {
                ArtboardSteps(
                    file: "a1b2c3d4e5f6",
                    artboards: (1 ... 5).map {
                        Artboard(id: "Cnv0\($0)", name: "Screen \($0)", x: Double($0) * 500, y: 0, width: 402, height: 874)
                    },
                    current: "Cnv02",
                    state: ViewState(theme: ["Mode": "Dark"])
                )
            },
            PreviewState(
                slug: "last",
                name: "Five of five — the end of the list",
                note: "The ends clamp, they do not wrap: ten presses of `›` never quietly return you to the first artboard. The dead arrow keeps its glyph as a dimmed `<span>` rather than disappearing, so the counter between the two does not shift sideways as you step through the file.",
                frame: .canvas
            ) {
                ArtboardSteps(
                    file: "a1b2c3d4e5f6",
                    artboards: (1 ... 5).map {
                        Artboard(id: "Cnv0\($0)", name: "Screen \($0)", x: Double($0) * 500, y: 0, width: 402, height: 874)
                    },
                    current: "Cnv05",
                    state: ViewState()
                )
            },
        ]
    )
}
