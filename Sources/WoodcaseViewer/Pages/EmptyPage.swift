//
//  EmptyPage.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// What `/` serves when there is nothing to serve: the two commands that make something
/// appear.
///
/// An empty dashboard is the state a person is most likely to meet first — they ran
/// `woodcase serve` before editing anything — so it is a real page with the next command
/// on it, not a blank list. It also stays live: the moment the log names a file, the
/// server adopts it and pushes a `change`, and the `data-empty-file` marker below tells
/// `viewer.js` to reload this page into the dashboard. There is no fragment to swap —
/// the page that answers next is a different page — so the reload is the update.
public struct EmptyPage: HTML {
    /// Creates the empty state.
    ///
    /// - Parameters:
    ///   - logPath: Where the activity log lives.
    ///   - eventCount: How many events it holds — zero, usually, and worth saying.
    ///   - clock: The moment the page is rendered for.
    public init(logPath: String, eventCount: Int, clock: ViewerClock) {
        self.logPath = logPath
        self.eventCount = eventCount
        self.clock = clock
    }

    /// Where the activity log lives.
    public let logPath: String

    /// How many events it holds.
    public let eventCount: Int

    /// The moment the page is rendered for.
    public let clock: ViewerClock

    public var body: some HTML {
        ViewerDocument(title: "Nothing to show yet · woodcase serve", layout: .empty) {
            TopBar(crumbs: [], presence: [], clock: clock)
            main(.class("v-main")) {
                // Any file at all replaces this page, so the marker names none: the
                // script reloads on the first `change` it sees, whichever file it is
                // about. ``FileEmptyPage`` carries the same attribute with an id in it.
                section(.class("v-empty"), .data("empty-file", value: "")) {
                    h1(.class("v-empty-title")) { "Nothing to show yet" }
                    p(.class("v-empty-lede")) {
                        "Files appear here as the activity log sees them, or pass one on the command line."
                    }
                    // The fade is the block's overflow affordance and paints over its
                    // right edge, so the block needs a positioned parent to hang it on.
                    div(.class("v-empty-block")) {
                        pre(.class("v-mono v-empty-commands")) {
                            code(.class("is-primary")) { "woodcase serve ~/Designs/banking.pen" }
                            code { "woodcase set banking.pen Dashboard/Header/Title content=\"Overview\"" }
                        }
                        span(.class("v-empty-fade"), .custom(name: "aria-hidden", value: "true")) {}
                    }
                    p(.class("v-mono v-empty-note")) {
                        "watching \(logPath) · \(eventCount) \(eventCount == 1 ? "event" : "events")"
                    }
                }
            }
        }
    }
}
