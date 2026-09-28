//
//  ActivityRow+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension ActivityRow {
    /// One line of the feed, in the shapes the log actually produces.
    static let previews = PreviewComponent(
        slug: "activity-row",
        title: "Activity row",
        blurb: "One write from the log as five columns — time, avatar, identity, verb, path — expanding to the nodes it touched.",
        source: "Sources/WoodcaseViewer/Components/ActivityRow.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "One node set",
                note: "The ordinary row. The verb is the one bold mono word; the time carries the long age in its `title`, so a person hovering gets \"4 s ago\" without the column widening. The expander is a `<details>` — it works with the script switched off, which is the rule the whole page follows.",
                frame: .rightPane
            ) {
                ActivityRow(
                    event: PreviewFixtures.event(secondsAgo: 4),
                    clock: PreviewFixtures.clock
                )
            },
            PreviewState(
                slug: "many-nodes",
                name: "Four nodes at once",
                note: "The path column names the *first* path and says `+3`; the rest are one click away, in the detail's node list, each with its own copy chip. This is where the row is most likely to wrap — it must not, because a wrapped row destroys the column alignment the feed is scanned by.",
                frame: .rightPane
            ) {
                ActivityRow(
                    event: PreviewFixtures.event(
                        secondsAgo: 92, identity: "claude-b", op: .mv,
                        nodes: ["Crd01", "Crd02", "Crd03", "Crd04"],
                        paths: [
                            "Dashboard/Cards/Revenue",
                            "Dashboard/Cards/Customers",
                            "Dashboard/Cards/Churn",
                            "Dashboard/Cards/Runway",
                        ],
                        batch: "b7f10c2a"
                    ),
                    clock: PreviewFixtures.clock
                )
            },
            PreviewState(
                slug: "no-nodes",
                name: "A write that touched no node",
                note: "A variable or theme write edits the document rather than a node, so there is no path to print and the row says how many operations it carried instead — the only true thing there is to say in one column. The detail drops the node list entirely rather than showing an empty one.",
                frame: .rightPane
            ) {
                ActivityRow(
                    event: PreviewFixtures.event(
                        secondsAgo: 640, identity: "ben", op: .set, nodes: [], paths: [],
                        inverse: [
                            .setProperties(EditOperation.SetProperties(
                                nodeID: "Ttl01", properties: ["kind.content": AnyCodable("Overview")]
                            )),
                            .setProperties(EditOperation.SetProperties(
                                nodeID: "Ttl01", properties: ["kind.fontSize": AnyCodable(14)]
                            )),
                        ]
                    ),
                    clock: PreviewFixtures.clock
                )
            },
            PreviewState(
                slug: "cross-file",
                name: "On the dashboard, where the file matters",
                note: "The same row with `showsFile`, which the cross-file feed needs and a single file's does not. The file name and the path share one column separated by a middot; check the column does not grow so wide that the verb loses its place.",
                frame: .rightPane
            ) {
                ActivityRow(
                    event: PreviewFixtures.event(
                        secondsAgo: 1800, identity: ActivityEvent.unattributed, op: .rm,
                        file: "/Users/ana/Designs/onboarding.pen",
                        nodes: ["Ftr01"], paths: ["Welcome/Footer"]
                    ),
                    clock: PreviewFixtures.clock,
                    showsFile: true
                )
            },
        ]
    )
}
