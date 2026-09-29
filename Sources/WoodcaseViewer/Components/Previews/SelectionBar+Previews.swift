//
//  SelectionBar+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension SelectionBar {
    /// The agent handoff line: empty, ordinary, clipped, far too long, and in a narrow pane.
    static let previews = PreviewComponent(
        slug: "selection-bar",
        title: "Selection bar",
        blurb: "The footer under the render: the selected node spelled the way a command line wants it, plus the artboard steppers.",
        source: "Sources/WoodcaseViewer/Components/SelectionBar.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "One node selected",
                note: "This line is the page's actual product — the string you paste into `woodcase set`. Path, id chip, rect, shortened revision, copy button, steppers, in that order; everything but the path is a fixed fact.",
                frame: .canvas
            ) {
                SelectionBar(
                    file: "a1b2c3d4e5f6",
                    artboard: Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                    artboards: [
                        Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                        Artboard(id: "Brd01", name: "Settings", x: 500, y: 40, width: 400, height: 300),
                    ],
                    scale: 2,
                    revision: "3f2a91c0d4e5b678",
                    selection: ArtboardLayout.Node(
                        id: "Ttl01", path: "Dashboard/Header/Title",
                        x: 24, y: 20, width: 118, height: 24
                    ),
                    state: ViewState(node: "Ttl01")
                )
            },
            PreviewState(
                slug: "nothing-selected",
                name: "Nothing selected",
                note: "The bar falls back to what is true with no selection: the artboard's name, its size in points, and the density the PNG was rendered at — which is the fact that tells you whether a blurry render is the render or the display. It must not render an empty row and wait.",
                frame: .canvas
            ) {
                SelectionBar(
                    file: "a1b2c3d4e5f6",
                    artboard: Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                    artboards: [
                        Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                        Artboard(id: "Brd01", name: "Settings", x: 500, y: 40, width: 400, height: 300),
                    ],
                    scale: 2,
                    revision: "3f2a91c0d4e5b678",
                    selection: nil
                )
            },
            PreviewState(
                slug: "clipped",
                name: "A selection hanging outside its parent",
                note: "The warn `⚠ partially outside its parent` slots in between the rect and the revision. Color is never the only carrier here — the sentence says it in words — and the extra column is the one most likely to push the revision off a narrow pane.",
                frame: .canvas
            ) {
                SelectionBar(
                    file: "a1b2c3d4e5f6",
                    artboard: Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                    artboards: [
                        Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                        Artboard(id: "Brd01", name: "Settings", x: 500, y: 40, width: 400, height: 300),
                    ],
                    scale: 2,
                    revision: "3f2a91c0d4e5b678",
                    selection: ArtboardLayout.Node(
                        id: "Vr7Kd", path: "Dashboard/Cards/Customers",
                        x: 328, y: 24, width: 120, height: 172, clip: .partial
                    ),
                    state: ViewState(node: "Vr7Kd")
                )
            },
            PreviewState(
                slug: "long-path",
                name: "A path far longer than the bar",
                note: "The truncation case. The path is cut from its *front* — `…/Fav Card 2/Cover Image`, never `Home — Colle…` — because the end of a path is the part that names the node. The `<bdi>` is what keeps an em dash, a slash and a parenthesis in written order inside a box laid out right-to-left; without it they reorder and mirror. Only the path shrinks.",
                frame: .canvas
            ) {
                SelectionBar(
                    file: "a1b2c3d4e5f6",
                    artboard: Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                    artboards: [
                        Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                        Artboard(id: "Brd01", name: "Settings", x: 500, y: 40, width: 400, height: 300),
                    ],
                    scale: 2,
                    revision: "3f2a91c0d4e5b678",
                    selection: ArtboardLayout.Node(
                        id: "Cvr01",
                        path: "Home — Collection (Light)/Content/Favorites/Fav Card 2/Cover Image",
                        x: 24, y: 460, width: 168, height: 112
                    ),
                    state: ViewState(node: "Cvr01")
                )
            },
            PreviewState(
                slug: "narrow-pane",
                name: "A pane narrower than 560 px",
                note: "The same long path in a render column held at 520 px — what the 1280 px window leaves once a pane is dragged wider. Below 560 px the rect and the revision are shed first (both are in the Details pane), and what is left of the path is still cut from its *front*. The id, the copy button and the steppers stay whole.",
                frame: .canvas,
                pinnedWidth: 520
            ) {
                SelectionBar(
                    file: "a1b2c3d4e5f6",
                    artboard: Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                    artboards: [
                        Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                        Artboard(id: "Brd01", name: "Settings", x: 500, y: 40, width: 400, height: 300),
                    ],
                    scale: 2,
                    revision: "3f2a91c0d4e5b678",
                    selection: ArtboardLayout.Node(
                        id: "Cvr01",
                        path: "Home — Collection (Light)/Content/Favorites/Fav Card 2/Cover Image",
                        x: 24, y: 460, width: 168, height: 112
                    ),
                    state: ViewState(node: "Cvr01")
                )
            },
        ]
    )
}
