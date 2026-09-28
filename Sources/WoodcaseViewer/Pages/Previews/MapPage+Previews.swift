//
//  MapPage+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension MapPage {
    /// A file's landing page: every artboard at once.
    static let previews = PreviewComponent(
        slug: "map-page",
        title: "Map page",
        blurb: "A multi-artboard file's landing view: the map as the canvas, the artboard listing as the outline, Activity as the only right-pane tab.",
        source: "Sources/WoodcaseViewer/Pages/MapPage.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "Three artboards, theme pinned to Dark",
                note: "A plain frame, a definition and an instance. Details and Export are absent by design — the map has no one selection and no one artboard to write — and the trail starts at the file, because the brand is the way back to the root.",
                frame: .page
            ) {
                MapPage(
                    file: ViewerFile(url: URL(fileURLWithPath: "/Users/ana/Designs/banking.pen")),
                    artboards: [
                        Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                        Artboard(id: "nSNTs", name: "banking-home", x: 500, y: 0, width: 402, height: 874, isReusable: true),
                        Artboard(
                            id: "YGJ0d/nSNTs", name: "banking-home / Dark",
                            x: 1000, y: 0, width: 402, height: 874, isInstance: true
                        ),
                    ],
                    revision: "3f2a91c0d4e5b678",
                    variables: [
                        ViewerVariable(
                            name: "accent", type: .color, value: "#2FBF6F", swatch: "#2FBF6F",
                            lastEditor: "claude-a", lastChange: PreviewFixtures.now.addingTimeInterval(-4)
                        ),
                    ],
                    axes: ["Mode": ["Light", "Dark"]],
                    events: [
                        PreviewFixtures.event(secondsAgo: 300, identity: "ben", op: .mv, nodes: ["Hdr01"], paths: ["Dashboard/Header"]),
                        PreviewFixtures.event(secondsAgo: 4, identity: "claude-a"),
                    ],
                    presence: [
                        PreviewFixtures.identity("claude-a", secondsAgo: 4, events: 12),
                        PreviewFixtures.identity("ben", secondsAgo: 300, events: 3),
                    ],
                    editors: ["nSNTs": ["claude-a"]],
                    state: ViewState(theme: ["Mode": "Dark"]),
                    clock: PreviewFixtures.clock
                )
            },
        ]
    )
}
