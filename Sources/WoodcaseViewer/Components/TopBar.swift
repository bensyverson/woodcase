//
//  TopBar.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The chrome: where you are, what theme the file is settled for, who is here, and
/// whether the stream is live.
///
/// It sits on `--v-chrome`, a tone set back from the panels, so an in-action state — a
/// row lighting up, an edit marker appearing — reads against something rather than being
/// white on white.
public struct TopBar: HTML {
    /// Creates a top bar.
    ///
    /// - Parameters:
    ///   - crumbs: The trail, root first. The last crumb is the page you are on and is
    ///     not a link.
    ///   - presence: Who has been writing, in the log's order of first appearance.
    ///   - clock: The moment the page is rendered for.
    ///   - axes: The file's theme axes, or empty on a page with no file.
    ///   - state: The current view state.
    ///   - action: Where the theme and follow forms submit — the page you are on.
    ///   - subject: What the bar sits over, which is what decides which controls it can
    ///     offer at all.
    public init(
        crumbs: [Crumb],
        presence: [ViewerPresence.Identity],
        clock: ViewerClock,
        axes: [String: [String]] = [:],
        state: ViewState = ViewState(),
        action: String = ViewerLink.dashboard,
        subject: Subject = .files
    ) {
        self.crumbs = crumbs
        self.presence = presence
        self.clock = clock
        self.axes = axes
        self.state = state
        self.action = action
        self.subject = subject
    }

    /// What the bar sits over.
    ///
    /// Two controls are not offered everywhere, and the reason is the same in both
    /// cases — there is nothing for them to act on — so the page names the *fact* and
    /// the controls follow, rather than each carrying its own flag.
    public enum Subject: String, Friendly, CaseIterable {
        /// The cross-file dashboard. No file to follow, no artboard to present.
        case files
        /// A file's map of artboards: a file to follow, but no one artboard to show.
        case map
        /// One artboard: everything the bar can do, it can do here.
        case artboard
        /// The preview catalog: fixtures, not a document anyone is writing to.
        ///
        /// Nothing on these pages is live, so the bar is the trail and nothing else. A
        /// badge, a presence stack or a keyboard hint here would also be a *second* copy
        /// of the one a state draws, with the same id, and the script and `popovertarget`
        /// would drive the chrome's copy rather than the state under review (`teQIgm`).
        case previews

        /// Whether following an identity means anything on this page.
        ///
        /// Following moves the page to the artboard a write touched, and the dashboard
        /// has none to move to.
        var canFollow: Bool {
            self == .map || self == .artboard
        }

        /// Whether there is one artboard to fill the screen with.
        var canPresent: Bool {
            self == .artboard
        }

        /// Whether the page is watching a live stream: who is here, whether the stream
        /// is up, the file's theme, and the keys that act on it.
        var isLive: Bool {
            self != .previews
        }
    }

    /// One step of the trail.
    public struct Crumb: Friendly {
        /// Creates a crumb.
        ///
        /// - Parameters:
        ///   - label: What it reads as.
        ///   - href: Where it goes, or `nil` for the page you are on.
        ///   - leads: What kind of place it leads to, when that is worth a glyph.
        ///   - unread: Whether something changed up there since this browser last
        ///     looked. Always `false` on the server — see ``unread``.
        public init(
            label: String,
            href: String? = nil,
            leads: Destination? = nil,
            unread: Bool = false
        ) {
            self.label = label
            self.href = href
            self.leads = leads
            self.unread = unread
        }

        /// What a crumb leads to, when it is somewhere the trail should name in a glyph.
        ///
        /// Only one kind so far, and it earns the type rather than a `Bool`: the map
        /// crumb is also where the "something changed elsewhere" dot hangs, so the fact
        /// this crumb goes *up to the map* decides two different things about it.
        public enum Destination: String, Friendly, CaseIterable {
            /// The file's bird's-eye map.
            case map

            /// The glyph drawn ahead of the label.
            var glyph: String {
                switch self {
                case .map: "▦"
                }
            }

            /// The class that marks the crumb, which the script hangs the unread dot on.
            var className: String {
                "v-crumb-\(rawValue)"
            }

            /// What the hover says.
            var title: String {
                switch self {
                case .map: "Every artboard in this file"
                }
            }
        }

        /// What it reads as.
        public let label: String

        /// Where it goes, or `nil` for the page you are on.
        public let href: String?

        /// What kind of place it leads to, when that is worth a glyph.
        public let leads: Destination?

        /// Whether the crumb wears the unread dot.
        ///
        /// The server always renders `false`: which artboards this browser has looked
        /// at lives in its own `localStorage`, and ``ViewerScript`` sets
        /// `data-unread="1"` on the map crumb once it knows. It is a parameter so the
        /// state can be *declared* — a preview sets exactly the attribute the script
        /// sets, and the stylesheet rule (`.v-crumb-map[data-unread="1"]::after`) is
        /// then the real one.
        public let unread: Bool
    }

    /// The trail, root first.
    public let crumbs: [Crumb]

    /// Who has been writing.
    public let presence: [ViewerPresence.Identity]

    /// The moment the page is rendered for.
    public let clock: ViewerClock

    /// The file's theme axes.
    public let axes: [String: [String]]

    /// The current view state.
    public let state: ViewState

    /// Where the theme and follow forms submit.
    public let action: String

    /// What the bar sits over.
    public let subject: Subject

    public var body: some HTML {
        header(.class("v-topbar")) {
            a(.class("v-brand"), .href(ViewerLink.dashboard), .title("Every file being served")) {
                "woodcase"
            }
            nav(.class("v-crumbs")) {
                for crumb in crumbs {
                    if let href = crumb.href {
                        a(
                            .class("v-crumb"),
                            .href(href),
                            .title(crumb.leads?.title ?? crumb.label)
                        ) {
                            if let leads = crumb.leads {
                                span(.class("v-crumb-glyph")) { leads.glyph }
                            }
                            crumb.label
                        }
                        .attributes(
                            .class(crumb.leads?.className ?? ""),
                            when: crumb.leads != nil
                        )
                        .attributes(.data("unread", value: "1"), when: crumb.unread)
                        span(.class("v-crumb-sep")) { "/" }
                    } else {
                        span(.class("v-crumb is-current")) { crumb.label }
                    }
                }
            }
            if subject.isLive {
                div(.class("v-topbar-controls")) {
                    if subject.canFollow {
                        FollowPicker(identities: presence, state: state, action: action)
                    }
                    ThemePicker(axes: axes, state: state, action: action)
                    PresenceStack(identities: presence, clock: clock)
                    LiveBadge()
                    if subject.canPresent {
                        button(
                            .class("v-present"),
                            .id("v-present"),
                            .type(.button),
                            .title("Presentation (f)")
                        ) { "⛶" }
                    }
                    KeyboardHint()
                }
            }
        }
    }
}
