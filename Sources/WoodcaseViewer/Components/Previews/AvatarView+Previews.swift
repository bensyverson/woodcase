//
//  AvatarView+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension AvatarView {
    /// The identity disc at each of its three sizes, and with no identity at all.
    static let previews = PreviewComponent(
        slug: "avatar",
        title: "Avatar",
        blurb: "One identity as a coloured disc with its initial — the atom every other identity display is built from.",
        source: "Sources/WoodcaseViewer/Components/AvatarView.swift",
        states: [
            PreviewState(
                slug: "small",
                name: "Small — 15 px",
                note: "The size a table row uses. The initial should sit dead centre and the hue is hashed from the name, never a class.",
                frame: .strip
            ) { AvatarView(identity: "claude-a", size: .small) },
            PreviewState(
                slug: "medium",
                name: "Medium — 20 px",
                note: "The top bar and the expanded presence list. Check it against Small: only the disc grows, the ring weight does not.",
                frame: .strip
            ) { AvatarView(identity: "claude-a", size: .medium) },
            PreviewState(
                slug: "large",
                name: "Large — 28 px",
                note: "An edit marker's tag. The biggest the disc ever gets, and the one place the initial has room to breathe.",
                frame: .strip
            ) { AvatarView(identity: "claude-a", size: .large) },
            PreviewState(
                slug: "unattributed",
                name: "Nobody",
                note: "``ActivityEvent/unattributed`` — a write made with no `--as`. The disc renders `?` and its `title` reads \"unattributed\", because an unattributed write is a real state and not a rendering bug. The hashed colour of the empty string is still a colour: check it is not so pale the `?` disappears.",
                frame: .strip
            ) { AvatarView(identity: ActivityEvent.unattributed) },
        ]
    )
}
