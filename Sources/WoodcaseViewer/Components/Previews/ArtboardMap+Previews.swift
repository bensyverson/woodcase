//
//  ArtboardMap+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension ArtboardMap {
    /// The bird's-eye view of a file's artboards.
    static let previews = PreviewComponent(
        slug: "artboard-map",
        title: "Artboard map",
        blurb: "Every top-level frame as a real low-res render, placed at its canvas position under one zoom.",
        source: "Sources/WoodcaseViewer/Components/ArtboardMap.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "Three artboards, one just written to",
                note: "Names sit under the boxes and never scale with the map; the reusable root keeps its collapsed kind mark, and the touched frame is border-tinted in its editor's color.",
                frame: .canvas
            ) {
                ArtboardMap(
                    file: "a1b2c3",
                    artboards: [
                        Artboard(id: "Cnv01", name: "Canvas", x: 0, y: 0, width: 400, height: 300),
                        Artboard(id: "Brd01", name: "Board", x: 500, y: 40, width: 200, height: 100),
                        Artboard(id: "Cmp01", name: "Component", x: 0, y: 400, width: 240, height: 120, isReusable: true),
                    ],
                    state: ViewState(),
                    editors: ["Brd01": ["claude-a"]]
                )
            },
        ]
    )
}
