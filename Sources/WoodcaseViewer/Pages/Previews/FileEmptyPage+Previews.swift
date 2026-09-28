//
//  FileEmptyPage+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension FileEmptyPage {
    /// A real file that has no top-level frames yet.
    static let previews = PreviewComponent(
        slug: "file-empty-page",
        title: "File empty page",
        blurb: "A document the viewer can read but cannot draw: no artboards, so no map and no render.",
        source: "Sources/WoodcaseViewer/Pages/FileEmptyPage.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "No artboards yet",
                note: "The variables and the theme axes are already there, which is the point: the file is real, it just has nothing to draw. It names the file so the stream can replace it the moment a frame lands.",
                frame: .page
            ) {
                FileEmptyPage(
                    file: ViewerFile(url: URL(fileURLWithPath: "/Users/ana/Designs/banking.pen")),
                    variables: [
                        ViewerVariable(name: "accent", type: .color, value: "#2FBF6F", swatch: "#2FBF6F"),
                    ],
                    axes: ["Mode": ["Light", "Dark"]],
                    presence: [PreviewFixtures.identity("claude-a", secondsAgo: 4, events: 2)],
                    state: ViewState(),
                    clock: PreviewFixtures.clock
                )
            },
        ]
    )
}
