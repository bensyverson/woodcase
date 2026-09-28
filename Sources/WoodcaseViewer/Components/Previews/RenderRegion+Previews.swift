//
//  RenderRegion+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension RenderRegion {
    /// The render column, with a selection and two live edits on it.
    static let previews = PreviewComponent(
        slug: "render-region",
        title: "Render region",
        blurb: "The rendered artboard with its selection outline, edit markers and the footer that steps between artboards.",
        source: "Sources/WoodcaseViewer/Components/RenderRegion.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "A selection and two edit markers",
                note: "Title is selected and two identities are mid-write. The boxes are placed in layout points — the stylesheet applies the scale — and the footer says the size, the density and where in the file this artboard is.",
                frame: .canvas
            ) {
                RenderRegion(
                    file: "a1b2c3d4e5f6",
                    artboard: Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                    artboards: [
                        Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                        Artboard(id: "Brd01", name: "Settings", x: 500, y: 40, width: 400, height: 300),
                    ],
                    layout: PreviewFixtures.layout(),
                    layoutJSON: ArtboardPageBuilder.json(PreviewFixtures.layout()),
                    state: ViewState(node: "Ttl01"),
                    markers: [
                        EditMarker(
                            node: "Ttl01", identities: ["claude-a", "ben"],
                            op: .set, time: PreviewFixtures.now.addingTimeInterval(-4)
                        ),
                        EditMarker(
                            node: "Vr7Kd", identities: ["claude-b"],
                            op: .mv, time: PreviewFixtures.now.addingTimeInterval(-12)
                        ),
                    ],
                    clock: PreviewFixtures.clock
                )
            },
        ]
    )
}
