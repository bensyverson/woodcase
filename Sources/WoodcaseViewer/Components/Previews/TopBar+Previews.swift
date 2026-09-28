//
//  TopBar+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension TopBar {
    /// The chrome strip: at its busiest, wearing the unread dot, and at its emptiest.
    static let previews = PreviewComponent(
        slug: "top-bar",
        title: "Top bar",
        blurb: "The brand, the breadcrumb, the live badge, presence, follow, the theme picker and the keyboard hint, on one strip.",
        source: "Sources/WoodcaseViewer/Components/TopBar.swift",
        states: [
            PreviewState(
                slug: "artboard",
                name: "On an artboard page",
                note: "The busiest the bar gets: a map crumb wearing its glyph, a current crumb that is not a link, two identities, a theme axis and the presentation button. Every control in it is 11 px mono.",
                frame: .topBar
            ) {
                TopBar(
                    crumbs: [
                        TopBar.Crumb(label: "banking", href: "/files/a1b2c3d4e5f6", leads: .map),
                        TopBar.Crumb(label: "Dashboard"),
                    ],
                    presence: [
                        PreviewFixtures.identity("claude-a", secondsAgo: 4, events: 12),
                        PreviewFixtures.identity("ben", secondsAgo: 900, events: 3),
                    ],
                    clock: PreviewFixtures.clock,
                    axes: ["Mode": ["Light", "Dark"]],
                    state: ViewState(node: "Vr7Kd"),
                    action: "/files/a1b2c3d4e5f6/artboards/Cnv01",
                    subject: .artboard
                )
            },
            PreviewState(
                slug: "unread",
                name: "Something changed back on the map",
                note: "The file-wide unread dot, hung on the map crumb by setting the attribute the script sets — `data-unread=\"1\"` on `.v-crumb-map`. The crumb gains 10 px of right padding to make room, so check the trail does not jump sideways when the dot arrives, and that the dot's 2 px ring is the chrome tone rather than the panel tone it wears everywhere else.",
                frame: .topBar
            ) {
                TopBar(
                    crumbs: [
                        TopBar.Crumb(
                            label: "banking", href: "/files/a1b2c3d4e5f6",
                            leads: .map, unread: true
                        ),
                        TopBar.Crumb(label: "Dashboard"),
                    ],
                    presence: [PreviewFixtures.identity("claude-a", secondsAgo: 4, events: 12)],
                    clock: PreviewFixtures.clock,
                    axes: ["Mode": ["Light", "Dark"]],
                    state: ViewState(),
                    action: "/files/a1b2c3d4e5f6/artboards/Cnv01",
                    subject: .artboard
                )
            },
            PreviewState(
                slug: "dashboard",
                name: "Over the dashboard — no file to act on",
                note: "The emptiest the bar gets, and the reason `Subject` is a type rather than two flags: there is no file to follow and no artboard to present, so the follow picker and the presentation button are absent, not disabled. The theme picker renders nothing at all because there are no axes. What is left — brand, one crumb, live badge, presence, keyboard hint — is the bar's floor.",
                frame: .topBar
            ) {
                TopBar(
                    crumbs: [TopBar.Crumb(label: "files")],
                    presence: [
                        PreviewFixtures.identity("claude-a", secondsAgo: 4, events: 12),
                        PreviewFixtures.identity("ben", secondsAgo: 900, events: 3),
                    ],
                    clock: PreviewFixtures.clock,
                    subject: .files
                )
            },
        ]
    )
}
