//
//  LiveBadge+Previews.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension LiveBadge {
    /// The connection indicator in each of the three states it can be read in.
    ///
    /// A closed set of three, so all three are here: the badge's whole job is that the
    /// word and the color agree, and the only way to see that is side by side.
    static let previews = PreviewComponent(
        slug: "live-badge",
        title: "Live badge",
        blurb: "A dot and a word saying whether the page is still hearing from the server.",
        source: "Sources/WoodcaseViewer/Components/LiveBadge.swift",
        states: [
            PreviewState(
                slug: "connecting",
                name: "Connecting — what the server always sends",
                note: "The only state a page ever *arrives* in: the server cannot know whether this browser's stream will open. Muted, and the word is `connecting…` — the ellipsis says it is still in progress. All three labels are in the markup; `data-state` picks one.",
                frame: .strip
            ) { LiveBadge(state: .connecting) },
            PreviewState(
                slug: "live",
                name: "Live",
                note: "The stream is open. This is the one place the accent green is allowed in the chrome, and it should be the only green mark on the strip.",
                frame: .strip
            ) { LiveBadge(state: .live) },
            PreviewState(
                slug: "lost",
                name: "Disconnected",
                note: "The state that named the component: the badge used to go amber while still reading `live`. It must read `disconnected` — the raw value is `lost`, the word a person sees is not — and it must be warn, never accent.",
                frame: .strip
            ) { LiveBadge(state: .lost) },
        ]
    )
}
