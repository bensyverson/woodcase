//
//  LiveBadge.swift
//  WoodcaseViewer
//

import Elementary
import Foundation

/// The dot in the top bar that says whether the page is still hearing from the server.
///
/// Every label the badge can show is server-rendered, all three at once; the script owns
/// only `data-state`, and the stylesheet shows the one that matches. That is why the
/// script never writes a word of text — the same rule the fragments follow — and why a
/// dropped stream now *reads* "disconnected" instead of turning amber while still
/// claiming to be live.
public struct LiveBadge: HTML {
    /// Creates a badge.
    ///
    /// - Parameter state: The state to render as current. Always ``ConnectionState/connecting``
    ///   in practice: the server cannot know whether this page's stream will open.
    public init(state: ConnectionState = .connecting) {
        self.state = state
    }

    /// The state the page starts in.
    public let state: ConnectionState

    public var body: some HTML {
        span(
            .class("v-live"),
            .id("v-live"),
            .data("state", value: state.rawValue)
        ) {
            for candidate in ConnectionState.allCases {
                span(.class("v-live-label"), .data("state", value: candidate.rawValue)) {
                    candidate.label
                }
            }
        }
    }
}
