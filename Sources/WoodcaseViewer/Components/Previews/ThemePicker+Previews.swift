//
//  ThemePicker+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension ThemePicker {
    /// The file's own theme axes: unpinned, pinned, and a file that declares none.
    static let previews = PreviewComponent(
        slug: "theme-picker",
        title: "Theme picker",
        blurb: "One `GET` form per theme axis, so the page works with the script switched off.",
        source: "Sources/WoodcaseViewer/Components/ThemePicker.swift",
        states: [
            PreviewState(
                slug: "default",
                name: "Two axes, nothing pinned",
                note: "Each axis is its own form and each selects `default`. This is the file's own theme, never the site's light and dark — the two must not share a control.",
                frame: .topBar
            ) {
                ThemePicker(
                    axes: ["Mode": ["Light", "Dark"], "Base": ["Slate", "Sand"]],
                    state: ViewState(),
                    action: "/files/a1b2c3d4e5f6"
                )
            },
            PreviewState(
                slug: "pinned",
                name: "Mode pinned to Dark",
                note: "The pinned value is the selected option, and the selection rides along in every other axis's hidden fields so submitting one never drops the other.",
                frame: .topBar
            ) {
                ThemePicker(
                    axes: ["Mode": ["Light", "Dark"], "Base": ["Slate", "Sand"]],
                    state: ViewState(node: "Vr7Kd", theme: ["Mode": "Dark"]),
                    action: "/files/a1b2c3d4e5f6"
                )
            },
        ]
    )
}
