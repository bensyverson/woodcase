//
//  KindMark.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The badge marking a node as a reusable component definition, a placed instance, or a
/// slot frame.
///
/// A real file's top-level frames are often *all* definitions, with the screens on the
/// canvas being refs to them (`banking.pen`, `woodcase-app.pen`) — so a glyph alone is
/// not enough to read the outline or the artboard map at a glance. This mark adds a
/// title (for a hover) and a short visible label, styled distinctly per kind, wherever a
/// node carries one of the three roles.
public struct KindMark: HTML {
    /// The role a mark calls out.
    public enum Kind: String, Friendly {
        /// A reusable component definition (`reusable: true`).
        case component
        /// A placed instance of a component (a `ref`).
        case instance
        /// A slot frame, filled by an instance's descendant overrides.
        case slot

        /// The mark's glyph — one character, so it still reads in a dense list.
        var glyph: String {
            switch self {
            case .component: "◈"
            case .instance: "◇"
            case .slot: "▥"
            }
        }

        /// What the mark's `title` attribute says in full.
        var title: String {
            switch self {
            case .component: "Reusable component definition"
            case .instance: "Instance of a reusable component"
            case .slot: "Slot frame, filled by an instance's overrides"
            }
        }
    }

    /// Creates a mark for a node, or none.
    ///
    /// At most one role is drawn: a definition mark wins over an instance mark, which
    /// wins over a slot mark, because those are the questions asked in that order when
    /// reading an unfamiliar screen — "is this the real thing or a copy?" before "is this
    /// copy's parent also a hole to be filled?".
    ///
    /// - Parameters:
    ///   - isReusable: Whether the node is a component definition.
    ///   - isInstance: Whether the node is a `ref`.
    ///   - isSlot: Whether the node is a slot frame.
    public init(isReusable: Bool, isInstance: Bool, isSlot: Bool) {
        kind = if isReusable {
            .component
        } else if isInstance {
            .instance
        } else if isSlot {
            .slot
        } else {
            nil
        }
    }

    /// The role this mark draws, or `nil` for a node with none of the three.
    public let kind: Kind?

    public var body: some HTML {
        if let kind {
            span(.class("v-kind-mark v-kind-\(kind.rawValue)"), .title(kind.title)) {
                span(.class("v-kind-glyph")) { kind.glyph }
                span(.class("v-kind-label")) { kind.rawValue }
            }
        }
    }
}
