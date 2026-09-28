//
//  ArtboardRow+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension ArtboardRow {
    /// One artboard's row on the map page, including the state only the browser knows.
    static let previews = PreviewComponent(
        slug: "artboard-row",
        title: "Artboard row",
        blurb: "One artboard in the map page's outline — an outline row's columns, one level up, drilling in rather than selecting.",
        source: "Sources/WoodcaseViewer/Components/ArtboardRow.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "A plain frame",
                note: "Read this against an outline row: same columns in the same order, and the only difference is where the link goes — into the artboard, with the selection dropped, because you are leaving the artboard the selection belonged to. Unlike a node row this one carries a rect column — a map is where position matters — but it is the first thing the row sheds: below 420 px, the default pane included, the rect goes before a letter of the name does, since the name is what a person navigates by and the rect is on the map beside it.",
                frame: .leftPane
            ) {
                ArtboardRow(
                    artboard: Artboard(id: "Cnv01", name: "Canvas", x: 0, y: 0, width: 400, height: 300),
                    file: "a1b2c3d4e5f6",
                    state: ViewState()
                )
            },
            PreviewState(
                slug: "unread",
                name: "Changed since this browser last looked",
                note: "The 6 px warn dot, declared by setting the attribute the script sets — `data-unread=\"1\"` beside the row's own `data-artboard`. An attribute and not a class on purpose: every view of an artboard (a map box, this row, the breadcrumb's map crumb, a step arrow) inherits the dot by carrying the same pair, and none of them knows the others exist.",
                frame: .leftPane
            ) {
                ArtboardRow(
                    artboard: Artboard(id: "Brd01", name: "Settings", x: 500, y: 40, width: 402, height: 874),
                    file: "a1b2c3d4e5f6",
                    state: ViewState(),
                    unread: true
                )
            },
            PreviewState(
                slug: "touched",
                name: "A definition, being written to",
                note: "The kind mark takes the glyph column and the row wears its first editor's colour as a left bar. Both at once is the crowded case: the mark's own tint and the actor bar must stay distinguishable, since one is a fact about the file and the other a fact about right now.",
                frame: .leftPane
            ) {
                ArtboardRow(
                    artboard: Artboard(
                        id: "nSNTs", name: "banking-home", x: 1000, y: 0,
                        width: 402, height: 874, isReusable: true
                    ),
                    file: "a1b2c3d4e5f6",
                    state: ViewState(),
                    editors: ["claude-a"]
                )
            },
            PreviewState(
                slug: "unnamed-instance",
                name: "An unnamed instance, with a slash in its id",
                note: "A top-level `ref` expands to an id-path, and the row has to survive it twice: percent-encoded in the `href`, and verbatim in the chip so what you paste into a command is what the command wants. The label falls back to `#id` and is drawn faint.",
                frame: .leftPane
            ) {
                ArtboardRow(
                    artboard: Artboard(
                        id: "YGJ0d/nSNTs", name: nil, x: 1500, y: 0,
                        width: 402, height: 874, isInstance: true
                    ),
                    file: "a1b2c3d4e5f6",
                    state: ViewState()
                )
            },
        ]
    )
}
