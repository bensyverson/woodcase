//
//  PresenceStack.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// Who is working, as overlapping discs in the top bar.
///
/// Stacked and capped: three avatars and a `+N`, never a row that grows until it pushes
/// the theme picker off the bar. Clicking it reveals the full list with each identity's
/// last-seen age — and because that is a `<details>`, it works with the script switched
/// off, which is the rule for every affordance on this page.
///
/// Order is the log's order of first appearance, which the server already guarantees;
/// this component never sorts.
public struct PresenceStack: HTML {
    /// Creates a presence stack.
    ///
    /// - Parameters:
    ///   - identities: Who has written, in order of first appearance in the log.
    ///   - clock: The moment the page is rendered for.
    ///   - maximumShown: How many discs to stack before collapsing the rest into `+N`.
    public init(
        identities: [ViewerPresence.Identity],
        clock: ViewerClock,
        maximumShown: Int = 3
    ) {
        self.identities = identities
        self.clock = clock
        self.maximumShown = maximumShown
    }

    /// Who has written, in order of first appearance in the log.
    public let identities: [ViewerPresence.Identity]

    /// The moment the page is rendered for.
    public let clock: ViewerClock

    /// How many discs to stack before collapsing the rest into `+N`.
    public let maximumShown: Int

    /// The identities whose discs are drawn.
    var shown: [ViewerPresence.Identity] {
        Array(identities.prefix(maximumShown))
    }

    /// How many identities the stack could not show.
    var hidden: Int {
        max(0, identities.count - maximumShown)
    }

    /// The identity that wrote most recently inside the recency window, if any.
    ///
    /// The bar says "claude-a editing" for it — the one fact a person glancing at the
    /// page most often wants, and the reason presence is in the chrome rather than in a
    /// panel.
    var editing: ViewerPresence.Identity? {
        identities
            .filter { clock.isRecent($0.lastSeen) }
            .max { $0.lastSeen < $1.lastSeen }
    }

    public var body: some HTML {
        details(.class("v-presence"), .id(ViewerLink.Fragment.presence.target)) {
            summary(.class("v-presence-summary")) {
                span(.class("v-presence-stack")) {
                    for identity in shown {
                        AvatarView(identity: identity.name, size: .medium)
                    }
                    if hidden > 0 {
                        span(.class("v-avatar v-avatar-medium v-avatar-more")) { "+\(hidden)" }
                    }
                }
                span(.class("v-presence-note")) {
                    if identities.isEmpty {
                        "no identities yet"
                    } else if let editing {
                        // The handle gets its own element so it can be set in mono: it is an
                        // `--as` address, not a name, the same as in the activity row.
                        "\(identities.count) active · "
                        IdentityHandle(editing.name, className: "v-presence-name")
                        " editing"
                    } else {
                        "\(identities.count) active"
                    }
                }
            }
            ul(.class("v-presence-list")) {
                for identity in identities {
                    li(.class("v-presence-item")) {
                        AvatarView(identity: identity.name, size: .medium)
                        IdentityHandle(identity.name, className: "v-presence-name")
                        span(.class("v-presence-age")) {
                            clock.age(identity.lastSeen, style: .compact)
                        }
                        span(.class("v-presence-events")) {
                            "\(identity.events) \(identity.events == 1 ? "event" : "events")"
                        }
                    }
                }
            }
        }
    }
}
