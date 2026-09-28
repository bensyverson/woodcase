//
//  ExportPanel+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension ExportPanel {
    /// Writing this artboard out, in every format the CLI supports.
    static let previews = PreviewComponent(
        slug: "export-panel",
        title: "Export panel",
        blurb: "The right pane's Export tab: one form offering every format `render` and `generate` can write.",
        source: "Sources/WoodcaseViewer/Components/ExportPanel.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "Every format",
                note: "The image formats and every code target in one list. Check that the artboard's own size is what the scale options are read against.",
                frame: .rightPane
            ) {
                ExportPanel(
                    file: "a1b2c3d4e5f6",
                    artboard: Artboard(id: "Cnv01", name: "Canvas", width: 400, height: 300),
                    targets: ViewerCodeTarget.allCases,
                    state: ViewState()
                )
            },
        ]
    )
}
