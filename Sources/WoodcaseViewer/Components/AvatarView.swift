//
//  AvatarView.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// One identity, as a colored disc with its initial.
///
/// The primitive every other identity display is built from — activity rows, edit tags,
/// the presence stack, the variables list — so an agent is one recognizable mark
/// wherever it appears, and the same mark it has in the Jobs dashboard.
///
/// ```swift
/// AvatarView(identity: "claude-a")            // a 15 px disc
/// AvatarView(identity: "ben", size: .medium)  // a 20 px disc
/// ```
///
/// The color is written as the `--v-actor` custom property rather than as a class,
/// because it is hashed and there is no finite set of classes to write. It is also the
/// *only* place — with the edit markers — that an identity's color is allowed: a hashed
/// hue collides with the accent green often enough that colored text would read as a
/// link.
///
/// `--v-actor-ink` rides beside it, because a disc's initial cannot be white on every
/// hue the hash produces — see ``ActorColor/ink``. Two properties rather than one class
/// for the same reason: the pair is a fact about *this* identity, and only the element
/// that knows the identity can write it.
public struct AvatarView: HTML {
    /// Creates an avatar.
    ///
    /// - Parameters:
    ///   - identity: The `--as` name to draw.
    ///   - size: How big to draw it.
    public init(identity: String, size: Size = .small) {
        self.identity = identity
        self.size = size
    }

    /// How big a disc is.
    ///
    /// Three sizes rather than a number, so a row and a header cannot drift half a pixel
    /// apart and so the CSS carries the measurements.
    public enum Size: String, Friendly, CaseIterable {
        /// 15 px — a table row.
        case small
        /// 20 px — the top bar and the expanded presence list.
        case medium
        /// 28 px — an edit marker's tag.
        case large
    }

    /// The `--as` name being drawn.
    public let identity: String

    /// How big to draw it.
    public let size: Size

    /// The identity's hashed color.
    public var color: ActorColor {
        ActorColor(name: identity)
    }

    public var body: some HTML {
        span(
            .class("v-avatar v-avatar-\(size.rawValue)"),
            .style("--v-actor: \(color.css); --v-actor-ink: \(color.ink.rawValue)"),
            .title(IdentityHandle.text(identity)),
            .data("identity", value: identity)
        ) { color.initial }
    }
}
