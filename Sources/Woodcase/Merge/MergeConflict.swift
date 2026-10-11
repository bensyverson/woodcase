//
//  MergeConflict.swift
//  Woodcase
//

import Foundation

/// One place where a three-way merge could not take both sides' changes, and what it did.
///
/// A merge resolves every conflict itself — local changes win a same-key edit, and a
/// node one side deleted and the other edited follows the rules below — so a conflict
/// is a *report*, never a question. It carries the values involved so a consumer can
/// say what happened ("ben overrode claude's fill") and offer to take the other side.
///
/// Values are ``AnyCodable`` in the .pen file's own JSON shape: a property's value as
/// ``NodePropertyCodec`` reads it, a node's whole subtree for an existence conflict, a
/// list of ids for a child order. `nil` means the side does not hold the subject at all;
/// ``AnyCodable/null`` means it holds it unset — or, for a ``Subject/parent(nodeID:)``,
/// that the node is top-level.
public struct MergeConflict: Friendly {
    /// What the conflict is about.
    public enum Subject: Friendly {
        /// A property of a node, by its ``NodePropertyCodec`` path (`common.name`,
        /// `kind.width`, `extras.<key>`) — or one metadata entry, by its entry path
        /// (`common.metadata.woodcase.state`; ``NodePropertyCodec/metadataEntries(of:)``).
        case property(nodeID: String, path: String)

        /// One key of a `ref` node's override for one descendant, by the descendant's key
        /// in the `descendants` map. A `nil` key is the whole entry, which merges as one
        /// value when any side writes it as a whole-node replacement.
        case descendantOverride(nodeID: String, descendant: String, key: String?)

        /// One root override of a `ref` node, by its key.
        case rootOverride(nodeID: String, key: String)

        /// Whether a node exists at all.
        case existence(nodeID: String)

        /// Which node a node sits under.
        case parent(nodeID: String)

        /// The order of a container's children, or of the top-level nodes when `nil`.
        case childOrder(parentID: String?)

        /// A node's type, standing for every `kind.*` property.
        case nodeType(nodeID: String)

        /// A variable definition, by name.
        case variable(String)

        /// An import alias, by alias.
        case importAlias(String)

        /// A theme axis, by axis.
        case themeAxis(String)

        /// A document-level property, by its ``DocumentPropertyCodec`` key (`fonts`,
        /// `version`, `fileToken`, `extras.<key>`), or by table name (`variables`,
        /// `imports`, `themes`) for whether that table is declared.
        case document(key: String)
    }

    /// How the two sides collided, which says what the merge did.
    public enum Kind: String, Friendly {
        /// Both sides changed the subject to different values; the local value was kept.
        case bothChanged

        /// The local side edited a node — or something under it — that the external side
        /// deleted. The node is kept, with every ancestor the external side deleted.
        case editedLocallyDeletedExternally

        /// The local side deleted a node the external side edited, at it or below. It
        /// stays deleted; ``MergeConflict/theirs`` carries the external subtree so it can
        /// be restored.
        case deletedLocallyEditedExternally

        /// The external side added a node under one that does not survive the merge —
        /// one the local side deleted. It is dropped; ``MergeConflict/theirs`` carries it.
        case orphanedExternalInsert

        /// The external side deleted a component the merge still has an instance of. The
        /// component is kept, with its whole definition.
        case componentKeptForLocalInstance

        /// Both sides added a node with this id and set the subject differently; the
        /// local value was kept.
        case addedTwice

        /// The external change, merged with the local side's, would make components
        /// contain each other (``ComponentLoop``), so it was left out: an external insert
        /// is dropped (``Subject/existence(nodeID:)``, its subtree in
        /// ``MergeConflict/theirs``), an external move left undone
        /// (``Subject/parent(nodeID:)``), an external rewrite of the node left at the
        /// local value (``Subject/property(nodeID:path:)`` — the `ref`, the overrides or
        /// `reusable`). Every other change of theirs is taken.
        case wouldCloseComponentLoop
    }

    /// What the conflict is about.
    public var subject: Subject

    /// How the two sides collided.
    public var kind: Kind

    /// The subject's value in the common base, or `nil` if the base does not hold it.
    public var base: AnyCodable?

    /// The subject's value on the local side, or `nil` if it does not hold it.
    public var ours: AnyCodable?

    /// The subject's value on the external side, or `nil` if it does not hold it.
    public var theirs: AnyCodable?

    /// Creates a conflict report.
    ///
    /// - Parameters:
    ///   - subject: What the conflict is about.
    ///   - kind: How the two sides collided.
    ///   - base: The base value, or `nil` if the base does not hold the subject.
    ///   - ours: The local value, or `nil` if the local side does not hold it.
    ///   - theirs: The external value, or `nil` if the external side does not hold it.
    public init(subject: Subject, kind: Kind, base: AnyCodable? = nil, ours: AnyCodable? = nil, theirs: AnyCodable? = nil) {
        self.subject = subject
        self.kind = kind
        self.base = base
        self.ours = ours
        self.theirs = theirs
    }
}
