//
//  ArtboardOverlay+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension ArtboardOverlay {
    /// The render and the boxes over it — including every shape an ``EditMarker`` takes.
    ///
    /// This is where edit markers are reviewed: `EditMarker` is a model derived from the
    /// activity log and has no markup of its own, and this component's `MarkerBox` is
    /// the only thing that draws one.
    static let previews = PreviewComponent(
        slug: "artboard-overlay",
        title: "Artboard overlay",
        blurb: "The artboard PNG with the selection box, the recent-edit markers and the layout JSON the script positions from.",
        source: "Sources/WoodcaseViewer/Components/ArtboardOverlay.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "A selection and one recent edit",
                note: "The boxes are HTML over the PNG, never painted into it: the image is cached per artboard, theme and size, and an agent asking for the same URL must get the same bytes whatever anyone has selected. Every box is placed in layout *points* through `--v-x`/`--v-y`, and `--v-scale` ships as 1 so the page is right at full size with the script off.",
                frame: .canvas
            ) {
                ArtboardOverlay(
                    file: "a1b2c3d4e5f6",
                    artboard: Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                    layout: PreviewFixtures.layout(),
                    layoutJSON: ArtboardPageBuilder.json(PreviewFixtures.layout()),
                    state: ViewState(node: "Ttl01"),
                    markers: [
                        EditMarker(
                            node: "Vr7Kd", identities: ["claude-b"],
                            op: .mv, time: PreviewFixtures.now.addingTimeInterval(-12)
                        ),
                    ],
                    clock: PreviewFixtures.clock
                )
            },
            PreviewState(
                slug: "shared-node",
                name: "Two identities on one node",
                note: "One marker, not two: two boxes on the same rect is a rendering bug, not information. The tag carries both avatars and both names, and `--v-actor` is the *first* editor's colour, so the box does not flicker as the second one writes. `data-editors` carries the whole list for the script.",
                frame: .canvas
            ) {
                ArtboardOverlay(
                    file: "a1b2c3d4e5f6",
                    artboard: Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                    layout: PreviewFixtures.layout(),
                    layoutJSON: ArtboardPageBuilder.json(PreviewFixtures.layout()),
                    state: ViewState(),
                    markers: [
                        EditMarker(
                            node: "Ttl01", identities: ["claude-a", "ben"],
                            op: .set, time: PreviewFixtures.now.addingTimeInterval(-4)
                        ),
                    ],
                    clock: PreviewFixtures.clock
                )
            },
            PreviewState(
                slug: "quiet",
                name: "Nothing selected, nobody writing",
                note: "The overlay must still be there — empty, with the layout JSON in it — because the script positions a box for any node out of that JSON without a second request. An overlay that rendered nothing when there was nothing to draw would take the layout with it.",
                frame: .canvas
            ) {
                ArtboardOverlay(
                    file: "a1b2c3d4e5f6",
                    artboard: Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                    layout: PreviewFixtures.layout(),
                    layoutJSON: ArtboardPageBuilder.json(PreviewFixtures.layout()),
                    state: ViewState(),
                    markers: [],
                    clock: PreviewFixtures.clock
                )
            },
        ]
    )
}
