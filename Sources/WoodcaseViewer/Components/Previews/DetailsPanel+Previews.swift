//
//  DetailsPanel+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension DetailsPanel {
    /// One node's properties: with a selection, and with none.
    static let previews = PreviewComponent(
        slug: "details-panel",
        title: "Details panel",
        blurb: "The selected node's properties, each row marked with where its value came from.",
        source: "Sources/WoodcaseViewer/Components/DetailsPanel.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "A literal, an override and a variable",
                note: "All three origin marks in one panel. The override names the instance it came from and what it was; the variable names the token it reads.",
                frame: .rightPane
            ) {
                DetailsPanel(details: DetailsPanel.detailsFixture, file: "a1b2c3d4e5f6")
            },
            PreviewState(
                slug: "empty",
                name: "Nothing selected",
                note: "The tab is always present, so it has to say something when no node is chosen rather than render an empty box.",
                frame: .rightPane
            ) {
                DetailsPanel(details: nil, file: "a1b2c3d4e5f6")
            },
        ]
    )

    /// A details model with one row of each origin, so the preview shows all three marks.
    static var detailsFixture: NodeDetails {
        NodeDetails(
            id: "Nav01/Lbl01",
            address: "Nav01/Lbl01",
            path: "Dashboard/Body/Nav/Label",
            name: "Label",
            type: "text",
            revision: "3f2a91c0d4e5b678",
            instance: "Nav01",
            rows: [
                NodeDetail(path: "common.name", key: "name", value: "Label", origin: .literal),
                NodeDetail(
                    path: "kind.content", key: "content", value: "Menu", origin: .override,
                    source: NodeDetail.Source(
                        instance: "Nav01", path: "Dashboard/Body/Nav", was: "Click"
                    )
                ),
                NodeDetail(
                    path: "kind.fontSize", key: "fontSize", value: "14",
                    origin: .variable, variables: ["textSize"]
                ),
            ]
        )
    }
}
