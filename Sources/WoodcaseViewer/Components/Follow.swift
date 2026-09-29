//
//  Follow.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// Whose writes the page should chase — view state, like the selection and the theme
/// pins, and carried in the query for the same reason: a reload keeps it and a URL an
/// agent pastes reopens the same watch.
///
/// Three states, and they are three different facts rather than a target plus a flag:
///
/// | State | Query | Means |
/// | --- | --- | --- |
/// | ``nobody`` | *(absent)* | Changes land where they land; the page never moves |
/// | ``following(_:)`` | `follow=anyone`, `follow=ana` | A matching change moves the page to the artboard it touched |
/// | ``paused(_:)`` | `follow=paused:ana` | Manual navigation turned it off, and the control offers to turn it back on |
///
/// ``paused(_:)`` is why this is not a two-case enum. Any manual navigation — an outline
/// row, an artboard, a tab — drops follow, and a control that then said only "nobody"
/// would make resuming a hunt through a dropdown. Remembering the target *in the query*
/// is what lets the resume affordance be server-rendered like everything else on this
/// page, rather than a second copy of the control written in JavaScript.
///
/// Following never touches the theme: a write carries no theme, so the artboard the page
/// moves to is rendered with exactly the pins that were already on screen.
public enum Follow: Friendly {
    /// Who a follow is aimed at.
    public enum Target: Friendly {
        /// Every identity — the live setting: any attributed write moves the page.
        case anyone

        /// One identity from the activity log, by name.
        case identity(String)

        /// The spelling this target takes in the query.
        ///
        /// An identity that happens to be named `anyone` reads back as ``anyone``. That
        /// is the one collision in the vocabulary and it is accepted: the alternative is
        /// a second parameter, and the log's identities are agent names.
        public var query: String {
            switch self {
            case .anyone: "anyone"
            case let .identity(name): name
            }
        }

        /// What the control reads as.
        public var label: String {
            query
        }
    }

    /// Follow nothing — the default.
    case nobody

    /// Follow a target: a matching change moves the page to the artboard it touched.
    case following(Target)

    /// A follow that manual navigation turned off, remembering what to resume.
    case paused(Target)

    /// The target, whether it is being followed or is only remembered.
    public var target: Target? {
        switch self {
        case .nobody: nil
        case let .following(target), let .paused(target): target
        }
    }

    /// Whether a change can move the page right now.
    public var isFollowing: Bool {
        if case .following = self { return true }
        return false
    }

    /// Whether a change by an identity is one this follow chases.
    ///
    /// An unattributed write — a save by an editor that does not log — matches nothing,
    /// including ``Target/anyone``: the page moves because *somebody* wrote, and nobody
    /// claimed that one.
    ///
    /// - Parameter identity: The change's identity, or `nil` when it has none.
    /// - Returns: Whether to follow this change.
    public func matches(_ identity: String?) -> Bool {
        guard case let .following(target) = self, let identity else { return false }
        switch target {
        case .anyone: return true
        case let .identity(name): return name == identity
        }
    }

    /// This follow, switched off but remembered — what manual navigation leaves behind.
    ///
    /// - Returns: The paused form, or ``nobody`` when there was nothing to pause.
    public func pausing() -> Follow {
        guard let target else { return .nobody }
        return .paused(target)
    }

    /// This follow, switched back on — what the resume affordance links to.
    ///
    /// - Returns: The following form, or ``nobody`` when there is nothing to resume.
    public func resuming() -> Follow {
        guard let target else { return .nobody }
        return .following(target)
    }

    /// The `follow=` value, or `nil` when there is nothing to write.
    ///
    /// ``nobody`` writes nothing rather than `follow=nobody`, so a page nobody is
    /// following has the same URL it always had.
    public var query: String? {
        switch self {
        case .nobody: nil
        case let .following(target): target.query
        case let .paused(target): Self.pausedPrefix + target.query
        }
    }

    /// The follow a `follow=` value names.
    ///
    /// Anything unrecognizable is an identity, because an identity is any name the log
    /// has seen and this is not the place to decide a name is wrong.
    ///
    /// - Parameter text: The parameter's value, or `nil` when the query has none.
    /// - Returns: The follow it spells.
    public static func of(_ text: String?) -> Follow {
        guard let text, !text.isEmpty, text != "nobody" else { return .nobody }
        guard text.hasPrefix(pausedPrefix) else { return .following(target(of: text)) }
        let remembered = String(text.dropFirst(pausedPrefix.count))
        guard !remembered.isEmpty, remembered != "nobody" else { return .nobody }
        return .paused(target(of: remembered))
    }

    /// What marks a remembered target in the query.
    static let pausedPrefix = "paused:"

    /// The target one name spells.
    private static func target(of name: String) -> Target {
        name == "anyone" ? .anyone : .identity(name)
    }
}
