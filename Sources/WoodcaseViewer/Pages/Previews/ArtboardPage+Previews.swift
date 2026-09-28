//
//  ArtboardPage+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension ArtboardPage {
    /// One artboard, with everything the page can show turned on at once.
    static let previews = PreviewComponent(
        slug: "artboard-page",
        title: "Artboard page",
        blurb: "One artboard rendered between the outline and the right pane — the page the viewer exists for.",
        source: "Sources/WoodcaseViewer/Pages/ArtboardPage.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "A selection and a live edit",
                note: "Customers is selected and Title is mid-write, with the theme pinned to Dark. Everything has to agree: the outline row, the box on the render, the marker and the Details tab all name the same node.",
                frame: .page
            ) {
                ArtboardPage(
                    file: ViewerFile(url: URL(fileURLWithPath: "/Users/ana/Designs/banking.pen")),
                    artboard: Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                    artboards: [
                        Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                        Artboard(id: "Brd01", name: "Settings", x: 500, y: 40, width: 400, height: 300),
                    ],
                    layout: PreviewFixtures.layout(),
                    layoutJSON: ArtboardPageBuilder.json(PreviewFixtures.layout()),
                    rows: [
                        PreviewFixtures.row(id: "Cnv01", name: "Dashboard", rect: PenRect(x: 0, y: 0, width: 400, height: 300)),
                        PreviewFixtures.row(id: "Hdr01", depth: 1, name: "Header", rect: PenRect(x: 0, y: 0, width: 400, height: 64)),
                        PreviewFixtures.row(id: "Ttl01", depth: 2, type: "text", name: "Title", rect: PenRect(x: 24, y: 20, width: 118, height: 24)),
                        PreviewFixtures.row(
                            id: "Vr7Kd", depth: 2, type: "ref", name: "Customers",
                            rect: PenRect(x: 328, y: 24, width: 120, height: 172),
                            clip: .partial, isInstance: true, childCount: 3
                        ),
                    ],
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
                    markers: [
                        EditMarker(node: "Ttl01", identities: ["claude-a"], op: .set, time: PreviewFixtures.now.addingTimeInterval(-4)),
                    ],
                    editors: ["Ttl01": ["claude-a"]],
                    // The selected node's own details, so the fourth witness agrees with
                    // the other three instead of saying nothing is selected (`nqnnV9`).
                    details: NodeDetails(
                        id: "Vr7Kd",
                        address: "Dashboard/Cards/Customers",
                        path: "Dashboard/Cards/Customers",
                        name: "Customers",
                        type: "ref",
                        revision: "3f2a91c0d4e5b678",
                        instance: nil,
                        rows: [
                            NodeDetail(path: "common.name", key: "name", value: "Customers", origin: .literal),
                            NodeDetail(path: "kind.ref", key: "ref", value: "StatCard", origin: .literal),
                            NodeDetail(path: "common.x", key: "x", value: "328", origin: .literal),
                            NodeDetail(path: "common.y", key: "y", value: "24", origin: .literal),
                        ]
                    ),
                    state: ViewState(node: "Vr7Kd", theme: ["Mode": "Dark"]),
                    clock: PreviewFixtures.clock
                )
            },
        ]
    )
}
