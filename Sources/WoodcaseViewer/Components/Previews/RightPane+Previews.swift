//
//  RightPane+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension RightPane {
    /// The right column: which tab is current, and which tabs exist at all.
    static let previews = PreviewComponent(
        slug: "right-pane",
        title: "Right pane",
        blurb: "The pill tab bar over Activity, Details, Export and Code — every panel rendered, the tab deciding which is shown.",
        source: "Sources/WoodcaseViewer/Components/RightPane.swift",
        states: [
            PreviewState(
                slug: "details",
                name: "Details, with a node selected",
                note: "The default landing. Look for all four panels in the markup, not just this one: they are all rendered and `data-tab` on the `<aside>` picks one, which is what makes the tabs work with the script off, lets a fragment land in a panel nobody is looking at, and makes switching instant. The tabs are real links to `?tab=`.",
                frame: .rightPane
            ) {
                RightPane(
                    file: "a1b2c3d4e5f6",
                    artboard: Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                    details: DetailsPanel.detailsFixture,
                    targets: ViewerCodeTarget.allCases,
                    code: ArtboardCode(
                        target: .react,
                        path: "pages/Dashboard.tsx",
                        text: "export function Dashboard() {\n  return <div />;\n}\n"
                    ),
                    events: [
                        PreviewFixtures.event(secondsAgo: 240, identity: "ben", op: .mv, nodes: ["Cht01"], paths: ["Dashboard/Chart"]),
                        PreviewFixtures.event(secondsAgo: 4),
                    ],
                    state: ViewState(node: "Nav01/Lbl01", tab: .details),
                    clock: PreviewFixtures.clock
                )
            },
            PreviewState(
                slug: "code",
                name: "Code, as a tab and not a second canvas",
                note: "Code used to open as the right-hand half of a split canvas and cost the render a third of its width. It is a pill like the rest now — it answers the same shape of question the other tabs answer, *what is this artboard, told another way*. Only `data-tab` differs from the Details state; the panels are identical.",
                frame: .rightPane
            ) {
                RightPane(
                    file: "a1b2c3d4e5f6",
                    artboard: Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                    details: DetailsPanel.detailsFixture,
                    targets: ViewerCodeTarget.allCases,
                    code: ArtboardCode(
                        target: .react,
                        path: "pages/Dashboard.tsx",
                        text: "export function Dashboard() {\n  return <div />;\n}\n"
                    ),
                    events: [PreviewFixtures.event(secondsAgo: 4)],
                    state: ViewState(node: "Nav01/Lbl01", tab: .code),
                    clock: PreviewFixtures.clock
                )
            },
            PreviewState(
                slug: "map",
                name: "On the map page — one tab, not four",
                note: "The map is looking at every artboard and at none, so Details, Export and Code have nothing to act on and the bar drops them rather than offering three tabs that open on an apology. Check that the lone Activity pill still reads as a tab bar and not as a stray label, and that its link goes to the file rather than to an artboard.",
                frame: .rightPane
            ) {
                RightPane(
                    file: "a1b2c3d4e5f6",
                    artboard: nil,
                    details: nil,
                    targets: ViewerCodeTarget.allCases,
                    events: [
                        PreviewFixtures.event(secondsAgo: 660, identity: "claude-b", op: .rm, nodes: ["Ftr01"], paths: ["Dashboard/Footer"]),
                        PreviewFixtures.event(secondsAgo: 4),
                    ],
                    state: ViewState(tab: .details),
                    clock: PreviewFixtures.clock
                )
            },
            PreviewState(
                slug: "unresolved",
                name: "A `?node=` that names nothing",
                note: "A link copied before a rename. The pane must say the address it could not find rather than falling back silently to \"nothing selected\" — a stale link that looks like an empty selection is how a person concludes the node was deleted. Nothing else on the page changes.",
                frame: .rightPane
            ) {
                RightPane(
                    file: "a1b2c3d4e5f6",
                    artboard: Artboard(id: "Cnv01", name: "Dashboard", width: 400, height: 300),
                    details: nil,
                    unresolved: "Dashboard/Header/Titel",
                    targets: ViewerCodeTarget.allCases,
                    events: [PreviewFixtures.event(secondsAgo: 4)],
                    state: ViewState(node: "Dashboard/Header/Titel", tab: .details),
                    clock: PreviewFixtures.clock
                )
            },
        ]
    )
}
