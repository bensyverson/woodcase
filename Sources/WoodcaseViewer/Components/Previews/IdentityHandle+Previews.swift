//
//  IdentityHandle+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension IdentityHandle {
    /// An identity written as text: a handle, and the absence of one.
    static let previews = PreviewComponent(
        slug: "identity-handle",
        title: "Identity handle",
        blurb: "An identity written out as text beside its disc — in the presence line and the activity row's identity column.",
        source: "Sources/WoodcaseViewer/Components/IdentityHandle.swift",
        states: [
            PreviewState(
                slug: "handle",
                name: "A handle",
                note: "The `--as` address a writer typed, set in mono because it is an address and not a person's name. Shown in the activity column's class, which is where it is densest.",
                frame: .strip
            ) { IdentityHandle("claude-a", className: "v-activity-identity") },
            PreviewState(
                slug: "unattributed",
                name: "A write made with no --as",
                note: "The word `unattributed`, faint like the `#id` that stands in for an unnamed node — the absence of a name, spelled out. Never a blank: a blank is a hole in the activity row's grid and reads `2 active ·  editing` in the presence line.",
                frame: .strip
            ) { IdentityHandle(ActivityEvent.unattributed, className: "v-activity-identity") },
        ]
    )
}
