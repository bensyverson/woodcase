//
//  OutlineRow+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension OutlineRow {
    /// One node's row, in the four shapes it takes.
    ///
    /// Four rows, not one per depth: depth is a single custom property and a row at
    /// depth 7 says nothing a row at depth 2 does not. What differs between these is
    /// which columns appear at all.
    static let previews = PreviewComponent(
        slug: "outline-row",
        title: "Outline row",
        blurb: "One node in the outline: disclosure control, glyph or kind mark, name, clip flag and click-to-copy id — and a link, not a button.",
        source: "Sources/WoodcaseViewer/Components/OutlineRow.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "A named frame with children",
                note: "The ordinary row. It is an `<a href=\"?node=…\">` — selection is view state and view state lives in the query — and the disclosure box is filled, because the row has children of its own.",
                frame: .leftPane
            ) {
                OutlineRow(
                    row: PreviewFixtures.row(id: "kXFgb", depth: 1, name: "Header", childCount: 3),
                    file: "a1b2c3d4e5f6",
                    artboard: "Cnv01",
                    state: ViewState()
                )
            },
            PreviewState(
                slug: "selected",
                name: "Selected, clipped, and touched by two agents",
                note: "Everything a row can carry at once. The `⚠` says the node falls outside its parent; the 3 px left bar is the *first* editor's colour, never the second's, so two agents on one node do not make it flicker; and the `href` deselects — clicking the selected row clears the selection rather than re-selecting it.",
                frame: .leftPane
            ) {
                OutlineRow(
                    row: PreviewFixtures.row(
                        id: "Vr7Kd", depth: 2, type: "group", name: "Customers",
                        rect: PenRect(x: 728, y: 24, width: 320, height: 172),
                        clip: .partial, childCount: 4
                    ),
                    file: "a1b2c3d4e5f6",
                    artboard: "Cnv01",
                    state: ViewState(node: "Vr7Kd"),
                    editors: ["claude-b", "ben"]
                )
            },
            PreviewState(
                slug: "unnamed",
                name: "An unnamed leaf, three deep",
                note: "No name and no children: the label falls back to a faint mono `#id` and the disclosure box stays empty but keeps its 18 px, so this row's glyph still lines up with its siblings'. The one state where the id appears twice on the line — check the two do not read as two different nodes.",
                frame: .leftPane
            ) {
                OutlineRow(
                    row: PreviewFixtures.row(id: "g7Ttw", depth: 3, type: "rectangle"),
                    file: "a1b2c3d4e5f6",
                    artboard: "Cnv01",
                    state: ViewState()
                )
            },
            PreviewState(
                slug: "instance",
                name: "An instance, with its child count",
                note: "The kind mark *replaces* the type glyph rather than sitting beside it — a bare `◇` next to a labelled `◇ instance` is noise. `+4` is the count of what the instance expands to, and it is drawn only for an instance, because for anything else the disclosure control already says there is more.",
                frame: .leftPane
            ) {
                OutlineRow(
                    row: PreviewFixtures.row(
                        id: "qa1kL", depth: 2, type: "ref", name: "quickAction",
                        isInstance: true, childCount: 4
                    ),
                    file: "a1b2c3d4e5f6",
                    artboard: "Cnv01",
                    state: ViewState()
                )
            },
        ]
    )
}
