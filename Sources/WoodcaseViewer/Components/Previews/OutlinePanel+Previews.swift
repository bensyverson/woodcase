//
//  OutlinePanel+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension OutlinePanel {
    /// The node tree: populated, empty, and showing the component vocabulary.
    static let previews = PreviewComponent(
        slug: "outline-panel",
        title: "Outline panel",
        blurb: "One artboard's node tree, depth-indented, with a glyph column, kind marks and a touched bar per row.",
        source: "Sources/WoodcaseViewer/Components/OutlinePanel.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "A selection, a clip and two editors",
                note: "Customers is selected, partially clipped and touched by two identities; the row takes the first editor's colour as a 3 px left bar. The unnamed row reads as a faint mono #id.",
                frame: .leftPane
            ) {
                OutlinePanel(
                    rows: [
                        PreviewFixtures.row(id: "cXe2d", name: "Dashboard", rect: PenRect(x: 0, y: 0, width: 1440, height: 900)),
                        PreviewFixtures.row(id: "kXFgb", depth: 1, name: "Header", rect: PenRect(x: 0, y: 0, width: 1440, height: 64)),
                        PreviewFixtures.row(id: "Zq81a", depth: 2, type: "text", name: "Title", rect: PenRect(x: 24, y: 20, width: 118, height: 24)),
                        PreviewFixtures.row(
                            id: "Vr7Kd", depth: 2, type: "ref", name: "Customers",
                            rect: PenRect(x: 728, y: 24, width: 320, height: 172),
                            clip: .partial, isInstance: true, childCount: 4
                        ),
                        PreviewFixtures.row(id: "g7Ttw", depth: 2, rect: PenRect(x: 40, y: 40, width: 1360, height: 520)),
                    ],
                    revision: "3f2a91c0d4e5b678",
                    file: "a1b2c3d4e5f6",
                    artboard: "Cnv01",
                    state: ViewState(node: "Vr7Kd"),
                    editors: ["Zq81a": ["claude-a"], "Vr7Kd": ["claude-b", "ben"]]
                )
            },
            PreviewState(
                slug: "empty",
                name: "Nothing in it",
                note: "The header keeps its shortened revision even with no rows, so the panel does not collapse to a bare word.",
                frame: .leftPane
            ) {
                OutlinePanel(
                    rows: [],
                    revision: "3f2a91c0d4e5b678",
                    file: "a1b2c3d4e5f6",
                    artboard: "Cnv01",
                    state: ViewState()
                )
            },
            PreviewState(
                slug: "kind-marks",
                name: "Definition, instance, slot and plain",
                note: "The four cases of the component vocabulary side by side. Each mark is glyph plus word, tinted by its own colour; a plain node carries no mark at all.",
                frame: .leftPane
            ) {
                OutlinePanel(
                    rows: [
                        PreviewFixtures.row(id: "oqIlX", name: "Component/Stat Card", isReusable: true, childCount: 2),
                        PreviewFixtures.row(id: "qa1", depth: 1, type: "ref", name: "quickAction", isInstance: true, childCount: 1),
                        PreviewFixtures.row(id: "Fld01", depth: 1, name: "content", isSlot: true),
                        PreviewFixtures.row(id: "plain", depth: 1, name: "Footer"),
                    ],
                    revision: "3f2a91c0d4e5b678",
                    file: "a1b2c3d4e5f6",
                    artboard: "Cnv01",
                    state: ViewState()
                )
            },
        ]
    )
}
