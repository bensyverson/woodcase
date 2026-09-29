//
//  ArtboardOutline+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension ArtboardOutline {
    /// The map page's outline: the same columns a node row has, one level up.
    static let previews = PreviewComponent(
        slug: "artboard-outline",
        title: "Artboard outline",
        blurb: "A file's top-level frames listed in the outline's own slot, with kind marks, settled rects and click-to-copy ids.",
        source: "Sources/WoodcaseViewer/Components/ArtboardOutline.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "Three artboards, one of them touched",
                note: "A plain frame, a definition and an unnamed instance. banking-home was just written to, so its row takes the editor's color; the instance reads as its id-path, percent-encoded in the link.",
                frame: .leftPane
            ) {
                ArtboardOutline(
                    artboards: [
                        Artboard(id: "Cnv01", name: "Canvas", x: 0, y: 0, width: 400, height: 300),
                        Artboard(id: "nSNTs", name: "banking-home", x: 500, y: 40, width: 402, height: 874, isReusable: true),
                        Artboard(id: "YGJ0d/nSNTs", name: nil, x: 1000, y: 0, width: 402, height: 874, isInstance: true),
                    ],
                    revision: "3f2a91c0d4e5b678",
                    file: "a1b2c3",
                    state: ViewState(),
                    editors: ["nSNTs": ["claude-a"]]
                )
            },
        ]
    )
}
