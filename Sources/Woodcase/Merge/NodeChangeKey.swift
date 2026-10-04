//
//  NodeChangeKey.swift
//  Woodcase
//

import Foundation

/// One aspect of a node that differs between two documents.
///
/// The unit a three-way merge resolves on: two sides that changed the same key of the
/// same node conflict, and two sides that changed different keys do not. A node's own
/// content splits into ``property(_:)``, ``extra(_:)`` and ``type`` keys; its place in
/// the tree splits into ``parent``, ``children`` and ``declaredChildren``.
public enum NodeChangeKey: Friendly {
    /// A property in the ``NodePropertyCodec`` vocabulary changed, named by its path
    /// (`common.name`, `kind.width`, …) as ``PropertyDiff`` reports it.
    ///
    /// A ref's overrides are the coarse paths `kind.descendants` and
    /// `kind.rootOverrides`; a merge that resolves per override reads both maps from
    /// the ``NodeChange/from`` and ``NodeChange/to`` states.
    case property(String)

    /// A node extra — a key the model does not claim, see ``PenExtras`` — was added,
    /// removed or changed, named by its key.
    case extra(String)

    /// The node's type changed. This one key stands for every `kind.*` property: the
    /// payloads of two different types share no keys worth comparing, so none of them
    /// is reported beside it.
    case type

    /// The node sits under a different parent, or moved between the roots and a parent.
    ///
    /// A move within one parent is a ``children`` change of that parent, not this.
    case parent

    /// The node's ordered child list differs — a child joined, left or moved within it.
    case children

    /// The node declares `children` on one side and not on the other: a container
    /// written `"children": []` against one written without the key.
    ///
    /// Reported on its own because ``EditableDocument/revision(of:)`` hashes the two
    /// forms equal, so nothing else in the walk tells them apart.
    case declaredChildren

    /// The path this key sets in the property vocabulary, for keys that are one: the
    /// property's own path, `extras.<key>` for an extra and `kind.type` for a type
    /// change. `nil` for the placement keys, which are structural edits.
    public var propertyPath: String? {
        switch self {
        case let .property(path): path
        case let .extra(key): "extras.\(key)"
        case .type: "kind.type"
        case .parent, .children, .declaredChildren: nil
        }
    }
}
